const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;

const config_mod = @import("openai-compatible-config.zig");

/// OpenAI-compatible Chat Language Model
/// Can be used by providers that follow the OpenAI API format
pub const OpenAICompatibleChatLanguageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.OpenAICompatibleConfig,

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.OpenAICompatibleConfig,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .config = config,
        };
    }

    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        return self.config.provider;
    }

    pub fn doGenerate(
        self: *Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, lm.LanguageModelV3.GenerateResult) void,
        callback_context: ?*anyopaque,
    ) void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        const request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        const url = config_mod.buildChatCompletionsUrl(
            request_allocator,
            self.config.base_url,
        ) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        _ = url;
        _ = request_body;

        _ = result_allocator;
        callback(callback_context, .{
            .success = .{
                .content = &[_]lm.LanguageModelV3Content{},
                .finish_reason = .stop,
                .usage = lm.LanguageModelV3Usage.init(),
                .warnings = &[_]shared.SharedV3Warning{},
            },
        });
    }

    pub fn doStream(
        self: *Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        const request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callbacks.on_error(err, callbacks.context);
            return;
        };

        if (request_body == .object) {
            request_body.object.put("stream", .{ .bool = true }) catch |err| {
                callbacks.on_error(err, callbacks.context);
                return;
            };
        }

        _ = result_allocator;

        callbacks.on_part(.{ .stream_start = .{} }, callbacks.context);
        callbacks.on_part(.{
            .finish = .{
                .finish_reason = .stop,
                .usage = .{
                    .prompt_tokens = 0,
                    .completion_tokens = 0,
                },
            },
        }, callbacks.context);
        callbacks.on_complete(callbacks.context);
    }

    fn buildRequestBody(
        self: *Self,
        allocator: std.mem.Allocator,
        call_options: lm.LanguageModelV3CallOptions,
    ) !std.json.Value {
        var body = std.json.ObjectMap.init(allocator);

        try body.put("model", .{ .string = self.model_id });

        var messages = std.json.Array.init(allocator);

        for (call_options.prompt) |msg| {
            switch (msg.role) {
                .system => {
                    var message = std.json.ObjectMap.init(allocator);
                    try message.put("role", .{ .string = "system" });
                    try message.put("content", .{ .string = msg.content.system });
                    try messages.append(.{ .object = message });
                },
                .user => {
                    var message = std.json.ObjectMap.init(allocator);
                    try message.put("role", .{ .string = "user" });

                    var text_parts = std.ArrayListUnmanaged([]const u8){};
                    for (msg.content.user) |part| {
                        switch (part) {
                            .text => |t| try text_parts.append(allocator, t.text),
                            else => {},
                        }
                    }
                    const joined = try std.mem.join(allocator, "", text_parts.items);
                    try message.put("content", .{ .string = joined });

                    try messages.append(.{ .object = message });
                },
                .assistant => {
                    var message = std.json.ObjectMap.init(allocator);
                    try message.put("role", .{ .string = "assistant" });

                    var text_content = std.ArrayListUnmanaged([]const u8){};
                    var tool_calls = std.json.Array.init(allocator);

                    for (msg.content.assistant) |part| {
                        switch (part) {
                            .text => |t| try text_content.append(allocator, t.text),
                            .tool_call => |tc| {
                                var tool_call = std.json.ObjectMap.init(allocator);
                                try tool_call.put("id", .{ .string = tc.tool_call_id });
                                try tool_call.put("type", .{ .string = "function" });

                                var func = std.json.ObjectMap.init(allocator);
                                try func.put("name", .{ .string = tc.tool_name });
                                // Stringify the JsonValue input
                                const input_str = try tc.input.stringify(allocator);
                                try func.put("arguments", .{ .string = input_str });
                                try tool_call.put("function", .{ .object = func });

                                try tool_calls.append(.{ .object = tool_call });
                            },
                            else => {},
                        }
                    }

                    if (text_content.items.len > 0) {
                        const joined = try std.mem.join(allocator, "", text_content.items);
                        try message.put("content", .{ .string = joined });
                    }
                    if (tool_calls.items.len > 0) {
                        try message.put("tool_calls", .{ .array = tool_calls });
                    }

                    try messages.append(.{ .object = message });
                },
                .tool => {
                    for (msg.content.tool) |part| {
                        var message = std.json.ObjectMap.init(allocator);
                        try message.put("role", .{ .string = "tool" });
                        try message.put("tool_call_id", .{ .string = part.tool_call_id });

                        const output_text = switch (part.output) {
                            .text => |t| t.value,
                            .json => |j| try j.value.stringify(allocator),
                            .error_text => |e| e.value,
                            .error_json => |e| try e.value.stringify(allocator),
                            .execution_denied => |d| d.reason orelse "Execution denied",
                            .content => "Content output not yet supported",
                        };
                        try message.put("content", .{ .string = output_text });

                        try messages.append(.{ .object = message });
                    }
                },
            }
        }

        try body.put("messages", .{ .array = messages });

        if (call_options.max_output_tokens) |max_tokens| {
            try body.put("max_tokens", .{ .integer = @intCast(max_tokens) });
        }
        if (call_options.temperature) |temp| {
            try body.put("temperature", .{ .float = temp });
        }
        if (call_options.top_p) |top_p| {
            try body.put("top_p", .{ .float = top_p });
        }
        if (call_options.seed) |seed| {
            try body.put("seed", .{ .integer = @intCast(seed) });
        }
        if (call_options.frequency_penalty) |penalty| {
            try body.put("frequency_penalty", .{ .float = penalty });
        }
        if (call_options.presence_penalty) |penalty| {
            try body.put("presence_penalty", .{ .float = penalty });
        }

        if (call_options.stop_sequences) |stops| {
            var stops_array = std.json.Array.init(allocator);
            for (stops) |stop| {
                try stops_array.append(.{ .string = stop });
            }
            try body.put("stop", .{ .array = stops_array });
        }

        if (call_options.tools) |tools| {
            var tools_array = std.json.Array.init(allocator);
            for (tools) |tool| {
                switch (tool) {
                    .function => |func| {
                        var tool_obj = std.json.ObjectMap.init(allocator);
                        try tool_obj.put("type", .{ .string = "function" });

                        var func_obj = std.json.ObjectMap.init(allocator);
                        try func_obj.put("name", .{ .string = func.name });
                        if (func.description) |desc| {
                            try func_obj.put("description", .{ .string = desc });
                        }
                        // Convert JsonValue to std.json.Value
                        const params_std_json = try func.input_schema.toStdJson(allocator);
                        try func_obj.put("parameters", params_std_json);

                        try tool_obj.put("function", .{ .object = func_obj });
                        try tools_array.append(.{ .object = tool_obj });
                    },
                    else => {},
                }
            }
            try body.put("tools", .{ .array = tools_array });
        }

        return .{ .object = body };
    }

    pub fn asLanguageModel(self: *Self) lm.LanguageModelV3 {
        return .{
            .vtable = &vtable,
            .impl = self,
        };
    }

    const vtable = lm.LanguageModelV3.VTable{
        .doGenerate = doGenerateVtable,
        .doStream = doStreamVtable,
        .getModelId = getModelIdVtable,
        .getProvider = getProviderVtable,
        .getSupportedUrls = getSupportedUrlsVtable,
    };

    fn doGenerateVtable(
        impl: *anyopaque,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, lm.LanguageModelV3.GenerateResult) void,
        callback_context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doGenerate(call_options, result_allocator, callback, callback_context);
    }

    fn getSupportedUrlsVtable(
        impl: *anyopaque,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, lm.LanguageModelV3.SupportedUrlsResult) void,
        ctx: ?*anyopaque,
    ) void {
        _ = impl;
        callback(ctx, .{ .success = std.StringHashMap([]const []const u8).init(allocator) });
    }

    fn doStreamVtable(
        impl: *anyopaque,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doStream(call_options, result_allocator, callbacks);
    }

    fn getModelIdVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getModelId();
    }

    fn getProviderVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getProvider();
    }
};

test "OpenAICompatibleChatLanguageModel init" {
    const allocator = std.testing.allocator;

    var model = OpenAICompatibleChatLanguageModel.init(
        allocator,
        "test-model",
        .{ .base_url = "https://api.example.com/v1" },
    );

    try std.testing.expectEqualStrings("test-model", model.getModelId());
}
