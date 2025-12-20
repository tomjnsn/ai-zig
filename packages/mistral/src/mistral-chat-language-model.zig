const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;

const config_mod = @import("mistral-config.zig");
const options_mod = @import("mistral-options.zig");
const map_finish = @import("map-mistral-finish-reason.zig");
const prepare_tools = @import("mistral-prepare-tools.zig");

/// Mistral Chat Language Model
pub const MistralChatLanguageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.MistralConfig,

    /// Create a new Mistral chat language model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.MistralConfig,
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
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Build the request body
        const request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Build URL
        const url = config_mod.buildChatCompletionsUrl(
            request_allocator,
            self.config.base_url,
        ) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Get headers
        var headers = std.StringHashMap([]const u8).init(request_allocator);
        if (self.config.headers_fn) |headers_fn| {
            headers = headers_fn(&self.config);
        }

        // Serialize request body
        var body_buffer = std.ArrayList(u8).init(request_allocator);
        std.json.stringify(request_body, .{}, body_buffer.writer()) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // TODO: Use url, headers, and body_buffer to make actual HTTP request
        _ = url;
        headers.deinit();
        body_buffer.deinit();

        // For now, return placeholder result
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
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Build the request body with streaming enabled
        var request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callbacks.on_error(callbacks.ctx, err);
            return;
        };

        // Add stream flag
        if (request_body == .object) {
            request_body.object.put("stream", .{ .bool = true }) catch |err| {
                callbacks.on_error(callbacks.ctx, err);
                return;
            };
        }

        // Build URL
        const url = config_mod.buildChatCompletionsUrl(
            request_allocator,
            self.config.base_url,
        ) catch |err| {
            callbacks.on_error(callbacks.ctx, err);
            return;
        };

        _ = url;
        _ = result_allocator;

        // For now, emit completion
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

    /// Build the request body for the chat completions API
    fn buildRequestBody(
        self: *const Self,
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

                    // Check if we need array content (images, etc.)
                    var has_non_text = false;
                    for (msg.content.user) |part| {
                        switch (part) {
                            .file => {
                                has_non_text = true;
                                break;
                            },
                            else => {},
                        }
                    }

                    if (has_non_text) {
                        var content = std.json.Array.init(allocator);
                        for (msg.content.user) |part| {
                            switch (part) {
                                .text => |t| {
                                    var text_obj = std.json.ObjectMap.init(allocator);
                                    try text_obj.put("type", .{ .string = "text" });
                                    try text_obj.put("text", .{ .string = t.text });
                                    try content.append(.{ .object = text_obj });
                                },
                                .file => |f| {
                                    if (f.media_type) |mt| {
                                        if (std.mem.startsWith(u8, mt, "image/")) {
                                            var image_obj = std.json.ObjectMap.init(allocator);
                                            try image_obj.put("type", .{ .string = "image_url" });

                                            var url_obj = std.json.ObjectMap.init(allocator);
                                            switch (f.data) {
                                                .base64 => |data| {
                                                    const data_url = try std.fmt.allocPrint(
                                                        allocator,
                                                        "data:{s};base64,{s}",
                                                        .{ mt, data },
                                                    );
                                                    try url_obj.put("url", .{ .string = data_url });
                                                },
                                                .url => |url| {
                                                    try url_obj.put("url", .{ .string = url });
                                                },
                                                else => {},
                                            }
                                            try image_obj.put("image_url", .{ .object = url_obj });
                                            try content.append(.{ .object = image_obj });
                                        }
                                    }
                                },
                            }
                        }
                        try message.put("content", .{ .array = content });
                    } else {
                        // Simple text content
                        var text_parts = std.array_list.Managed([]const u8).init(allocator);
                        for (msg.content.user) |part| {
                            switch (part) {
                                .text => |t| try text_parts.append(t.text),
                                else => {},
                            }
                        }
                        const joined = try std.mem.join(allocator, "", text_parts.items);
                        try message.put("content", .{ .string = joined });
                    }

                    try messages.append(.{ .object = message });
                },
                .assistant => {
                    var message = std.json.ObjectMap.init(allocator);
                    try message.put("role", .{ .string = "assistant" });

                    var text_content = std.array_list.Managed([]const u8).init(allocator);
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

        // Add inference config
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
            try body.put("random_seed", .{ .integer = @intCast(seed) });
        }

        // Add tools if present
        if (call_options.tools) |tools| {
            const prepared = try prepare_tools.prepareTools(allocator, tools, call_options.tool_choice);
            if (prepared.tools) |t| {
                const tools_json = try prepare_tools.serializeToolsToJson(allocator, t);
                try body.put("tools", tools_json);
            }
            if (prepared.tool_choice) |tc| {
                try body.put("tool_choice", .{ .string = tc.toString() });
            }
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
        callback(ctx, .{ .success = std.StringHashMap([]const []const u8).init(allocator) });
    }

    /// Convert to LanguageModelV3 interface
    pub fn asLanguageModel(self: *Self) lm.LanguageModelV3 {
        return lm.asLanguageModel(Self, self);
    }
};

test "MistralChatLanguageModel init" {
    const allocator = std.testing.allocator;

    var model = MistralChatLanguageModel.init(
        allocator,
        "mistral-large-latest",
        .{ .base_url = "https://api.mistral.ai/v1" },
    );

    try std.testing.expectEqualStrings("mistral-large-latest", model.getModelId());
    try std.testing.expectEqualStrings("mistral", model.getProvider());
}
