const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");

const config_mod = @import("cohere-config.zig");
const options_mod = @import("cohere-options.zig");
const map_finish = @import("map-cohere-finish-reason.zig");

/// Cohere Chat Language Model
pub const CohereChatLanguageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.CohereConfig,

    /// Create a new Cohere chat language model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.CohereConfig,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .config = config,
        };
    }

    /// Get the model ID
    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    /// Get the provider name
    pub fn getProvider(self: *const Self) []const u8 {
        return self.config.provider;
    }

    /// Generate content (non-streaming)
    pub fn doGenerate(
        self: *Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?lm.LanguageModelV3.GenerateResult, ?anyerror, ?*anyopaque) void,
        callback_context: ?*anyopaque,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Build the request body
        const request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        // Build URL
        const url = config_mod.buildChatUrl(
            request_allocator,
            self.config.base_url,
        ) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        // Get headers
        var headers = std.StringHashMap([]const u8).init(request_allocator);
        if (self.config.headers_fn) |headers_fn| {
            headers = headers_fn(&self.config, request_allocator) catch |err| {
                callback(null, err, callback_context);
                return;
            };
        }

        // Serialize request body
        var body_buffer = std.ArrayList(u8).empty;
        std.json.stringify(request_body, .{}, body_buffer.writer(request_allocator)) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        // These are used in actual implementation for HTTP request
        // but for now we just use placeholder result
        _ = url;
        _ = body_buffer.items;

        // For now, return placeholder result
        const result = lm.LanguageModelV3.GenerateResult{
            .content = &[_]lm.LanguageModelV3Content{},
            .finish_reason = .stop,
            .usage = .{
                .prompt_tokens = 0,
                .completion_tokens = 0,
            },
            .warnings = &[_]shared.SharedV3Warning{},
        };

        _ = result_allocator;
        callback(result, null, callback_context);
    }

    /// Stream content
    pub fn doStream(
        self: *Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Build the request body with streaming enabled
        var request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callbacks.on_error(err, callbacks.context);
            return;
        };

        // Add stream flag
        if (request_body == .object) {
            request_body.object.put("stream", .{ .bool = true }) catch |err| {
                callbacks.on_error(err, callbacks.context);
                return;
            };
        }

        // Build URL
        const url = config_mod.buildChatUrl(
            request_allocator,
            self.config.base_url,
        ) catch |err| {
            callbacks.on_error(err, callbacks.context);
            return;
        };

        _ = url;
        _ = result_allocator;

        // Emit stream start
        callbacks.on_part(.{ .stream_start = .{} }, callbacks.context);

        // For now, emit completion
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

    /// Build the request body for the chat API
    fn buildRequestBody(
        self: *Self,
        allocator: std.mem.Allocator,
        call_options: lm.LanguageModelV3CallOptions,
    ) !std.json.Value {
        var body = std.json.ObjectMap.init(allocator);

        // Add model ID
        try body.put("model", .{ .string = self.model_id });

        // Build messages
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

                    var text_parts = std.ArrayList([]const u8).empty;
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

                    var text_content = std.ArrayList([]const u8).empty;
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
                                try func.put("arguments", .{ .string = tc.input });
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

        // Add inference config
        if (call_options.max_output_tokens) |max_tokens| {
            try body.put("max_tokens", .{ .integer = try provider_utils.safeCast(i64, max_tokens) });
        }
        if (call_options.temperature) |temp| {
            try body.put("temperature", .{ .float = temp });
        }
        if (call_options.top_p) |top_p| {
            try body.put("p", .{ .float = top_p });
        }
        if (call_options.top_k) |top_k| {
            try body.put("k", .{ .integer = try provider_utils.safeCast(i64, top_k) });
        }
        if (call_options.seed) |seed| {
            try body.put("seed", .{ .integer = try provider_utils.safeCast(i64, seed) });
        }

        // Add stop sequences
        if (call_options.stop_sequences) |stops| {
            var stops_array = std.json.Array.init(allocator);
            for (stops) |stop| {
                try stops_array.append(.{ .string = stop });
            }
            try body.put("stop_sequences", .{ .array = stops_array });
        }

        // Add tools if present
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
                        try func_obj.put("parameters", func.input_schema);

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

    /// Convert to LanguageModelV3 interface
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
    };

    fn doGenerateVtable(
        impl: *anyopaque,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?lm.LanguageModelV3.GenerateResult, ?anyerror, ?*anyopaque) void,
        callback_context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doGenerate(call_options, result_allocator, callback, callback_context);
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

test "CohereChatLanguageModel init" {
    const allocator = std.testing.allocator;

    var model = CohereChatLanguageModel.init(
        allocator,
        "command-r-plus",
        .{ .base_url = "https://api.cohere.com/v2" },
    );

    try std.testing.expectEqualStrings("command-r-plus", model.getModelId());
    try std.testing.expectEqualStrings("cohere", model.getProvider());
}
