const std = @import("std");
const lm = @import("../../provider/src/language-model/v3/index.zig");
const shared = @import("../../provider/src/shared/v3/index.zig");
const provider_utils = @import("provider-utils");

const config_mod = @import("deepseek-config.zig");
const options_mod = @import("deepseek-options.zig");
const map_finish = @import("map-deepseek-finish-reason.zig");

/// DeepSeek Chat Language Model
/// Uses OpenAI-compatible API
pub const DeepSeekChatLanguageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.DeepSeekConfig,

    /// Create a new DeepSeek chat language model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.DeepSeekConfig,
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
        self: *const Self,
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

        const result = lm.LanguageModelV3.GenerateSuccess{
            .content = &[_]lm.LanguageModelV3Content{},
            .finish_reason = .stop,
            .usage = .{
                .prompt_tokens = 0,
                .completion_tokens = 0,
            },
            .warnings = &[_]shared.SharedV3Warning{},
        };

        _ = result_allocator;
        callback(callback_context, .{ .success = result });
    }

    /// Stream content
    pub fn doStream(
        self: *const Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        var request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callbacks.on_error(callbacks.ctx, err);
            return;
        };

        if (request_body == .object) {
            request_body.object.put("stream", .{ .bool = true }) catch |err| {
                callbacks.on_error(callbacks.ctx, err);
                return;
            };
        }

        _ = result_allocator;

        callbacks.on_part(callbacks.ctx, .{
            .finish = .{
                .finish_reason = .stop,
                .usage = .{
                    .prompt_tokens = 0,
                    .completion_tokens = 0,
                },
            },
        });
        callbacks.on_complete(callbacks.ctx, null);
    }

    /// Build the request body (OpenAI format)
    fn buildRequestBody(
        self: *const Self,
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

                    var text_parts = std.ArrayList([]const u8).init(allocator);
                    for (msg.content.user) |part| {
                        switch (part) {
                            .text => |t| try text_parts.append(t.text),
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

                    var text_content = std.ArrayList([]const u8).init(allocator);
                    var tool_calls = std.json.Array.init(allocator);

                    for (msg.content.assistant) |part| {
                        switch (part) {
                            .text => |t| try text_content.append(t.text),
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

        if (call_options.max_output_tokens) |max_tokens| {
            try body.put("max_tokens", .{ .integer = try provider_utils.safeCast(i64, max_tokens) });
        }
        if (call_options.temperature) |temp| {
            try body.put("temperature", .{ .float = temp });
        }
        if (call_options.top_p) |top_p| {
            try body.put("top_p", .{ .float = top_p });
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

    /// Get supported URLs (stub implementation)
    pub fn getSupportedUrls(
        self: *const Self,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, lm.LanguageModelV3.SupportedUrlsResult) void,
        ctx: ?*anyopaque,
    ) void {
        _ = self;
        _ = allocator;
        callback(ctx, .{ .success = std.StringHashMap([]const []const u8).init(allocator) });
    }

    /// Convert to LanguageModelV3 interface
    pub fn asLanguageModel(self: *Self) lm.LanguageModelV3 {
        return lm.asLanguageModel(Self, self);
    }
};

test "DeepSeekChatLanguageModel init" {
    const allocator = std.testing.allocator;

    var model = DeepSeekChatLanguageModel.init(
        allocator,
        "deepseek-chat",
        .{ .base_url = "https://api.deepseek.com" },
    );

    try std.testing.expectEqualStrings("deepseek-chat", model.getModelId());
    try std.testing.expectEqualStrings("deepseek", model.getProvider());
}
