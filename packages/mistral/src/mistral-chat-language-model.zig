const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");

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
            headers = headers_fn(&self.config, request_allocator) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        // Serialize request body
        var body_buffer = std.ArrayList(u8).empty;
        std.json.stringify(request_body, .{}, body_buffer.writer(request_allocator)) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Get HTTP client
        const http_client = self.config.http_client orelse {
            // No HTTP client - return placeholder for testing
            callback(callback_context, .{ .success = .{
                .content = &[_]lm.LanguageModelV3Content{},
                .finish_reason = .stop,
                .usage = lm.LanguageModelV3Usage.initWithTotals(0, 0),
            } });
            return;
        };

        // Convert headers to slice
        headers.put("Content-Type", "application/json") catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };
        var header_list = std.ArrayList(provider_utils.HttpClient.Header).empty;
        var header_iter = headers.iterator();
        while (header_iter.next()) |entry| {
            header_list.append(request_allocator, .{
                .name = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        // Synchronous HTTP response capture
        const ResponseCtx = struct {
            response_body: ?[]const u8 = null,
            response_error: ?provider_utils.HttpClient.HttpError = null,
        };
        var response_ctx = ResponseCtx{};

        http_client.request(
            .{
                .method = .POST,
                .url = url,
                .headers = header_list.items,
                .body = body_buffer.items,
            },
            request_allocator,
            struct {
                fn onResponse(ctx: ?*anyopaque, response: provider_utils.HttpClient.Response) void {
                    const rctx: *ResponseCtx = @ptrCast(@alignCast(ctx.?));
                    rctx.response_body = response.body;
                }
            }.onResponse,
            struct {
                fn onError(ctx: ?*anyopaque, err: provider_utils.HttpClient.HttpError) void {
                    const rctx: *ResponseCtx = @ptrCast(@alignCast(ctx.?));
                    rctx.response_error = err;
                }
            }.onError,
            &response_ctx,
        );

        if (response_ctx.response_error != null) {
            callback(callback_context, .{ .failure = error.HttpRequestFailed });
            return;
        }

        const response_body = response_ctx.response_body orelse {
            callback(callback_context, .{ .failure = error.NoResponse });
            return;
        };

        // Parse response JSON
        const parsed = std.json.parseFromSlice(std.json.Value, request_allocator, response_body, .{}) catch {
            callback(callback_context, .{ .failure = error.InvalidResponse });
            return;
        };
        const root = parsed.value;

        // Extract content from choices[0].message.content
        var content_list = std.ArrayList(lm.LanguageModelV3Content).empty;
        if (root.object.get("choices")) |choices_val| {
            if (choices_val.array.items.len > 0) {
                const choice = choices_val.array.items[0];
                if (choice.object.get("message")) |message| {
                    if (message.object.get("content")) |content_val| {
                        if (content_val == .string) {
                            content_list.append(result_allocator, .{ .text = .{ .text = content_val.string } }) catch {};
                        }
                    }
                }
            }
        }

        // Extract usage
        var input_tokens: u64 = 0;
        var output_tokens: u64 = 0;
        if (root.object.get("usage")) |usage_val| {
            if (usage_val.object.get("prompt_tokens")) |pt| {
                if (pt == .integer) input_tokens = @intCast(pt.integer);
            }
            if (usage_val.object.get("completion_tokens")) |ct| {
                if (ct == .integer) output_tokens = @intCast(ct.integer);
            }
        }

        // Extract finish reason
        var finish_reason: lm.LanguageModelV3FinishReason = .stop;
        if (root.object.get("choices")) |choices_val| {
            if (choices_val.array.items.len > 0) {
                const choice = choices_val.array.items[0];
                if (choice.object.get("finish_reason")) |fr| {
                    if (fr == .string) {
                        finish_reason = map_finish.mapMistralFinishReason(fr.string);
                    }
                }
            }
        }

        callback(callback_context, .{ .success = .{
            .content = content_list.toOwnedSlice(result_allocator) catch &[_]lm.LanguageModelV3Content{},
            .finish_reason = finish_reason,
            .usage = lm.LanguageModelV3Usage.initWithTotals(input_tokens, output_tokens),
        } });
    }

    /// Stream state for SSE parsing (OpenAI-compatible format)
    const StreamState = struct {
        callbacks: lm.LanguageModelV3.StreamCallbacks,
        result_allocator: std.mem.Allocator,
        request_allocator: std.mem.Allocator,
        is_text_active: bool = false,
        finish_reason: lm.LanguageModelV3FinishReason = .unknown,
        usage: lm.LanguageModelV3Usage = lm.LanguageModelV3Usage.init(),
        partial_line: std.ArrayList(u8),

        fn init(
            callbacks: lm.LanguageModelV3.StreamCallbacks,
            result_allocator: std.mem.Allocator,
            request_allocator: std.mem.Allocator,
        ) StreamState {
            return .{
                .callbacks = callbacks,
                .result_allocator = result_allocator,
                .request_allocator = request_allocator,
                .partial_line = std.ArrayList(u8).empty,
            };
        }

        fn processChunk(self: *StreamState, chunk: []const u8) void {
            self.partial_line.appendSlice(self.request_allocator, chunk) catch return;

            while (std.mem.indexOf(u8, self.partial_line.items, "\n")) |newline_pos| {
                const line = self.partial_line.items[0..newline_pos];
                self.processLine(line);

                const remaining = self.partial_line.items[newline_pos + 1 ..];
                std.mem.copyForwards(u8, self.partial_line.items[0..remaining.len], remaining);
                self.partial_line.shrinkRetainingCapacity(remaining.len);
            }
        }

        fn processLine(self: *StreamState, line: []const u8) void {
            const trimmed = std.mem.trim(u8, line, " \r\n");
            if (trimmed.len == 0) return;

            if (std.mem.startsWith(u8, trimmed, "data: ")) {
                const json_data = trimmed[6..];

                // Skip [DONE] marker
                if (std.mem.eql(u8, json_data, "[DONE]")) return;

                // Parse JSON
                const parsed = std.json.parseFromSlice(
                    std.json.Value,
                    self.request_allocator,
                    json_data,
                    .{},
                ) catch return;
                const root = parsed.value;

                // Extract delta content from choices[0].delta
                if (root.object.get("choices")) |choices_val| {
                    if (choices_val.array.items.len > 0) {
                        const choice = choices_val.array.items[0];

                        if (choice.object.get("delta")) |delta| {
                            if (delta.object.get("content")) |content_val| {
                                if (content_val == .string and content_val.string.len > 0) {
                                    if (!self.is_text_active) {
                                        self.callbacks.on_part(self.callbacks.ctx, .{
                                            .text_start = .{ .id = "text-0" },
                                        });
                                        self.is_text_active = true;
                                    }
                                    const text_copy = self.result_allocator.dupe(u8, content_val.string) catch return;
                                    self.callbacks.on_part(self.callbacks.ctx, .{
                                        .text_delta = .{ .id = "text-0", .delta = text_copy },
                                    });
                                }
                            }
                        }

                        if (choice.object.get("finish_reason")) |fr| {
                            if (fr == .string) {
                                self.finish_reason = map_finish.mapMistralFinishReason(fr.string);
                            }
                        }
                    }
                }

                // Extract usage
                if (root.object.get("usage")) |usage_val| {
                    if (usage_val.object.get("prompt_tokens")) |pt| {
                        if (pt == .integer) self.usage.input_tokens.total = @intCast(pt.integer);
                    }
                    if (usage_val.object.get("completion_tokens")) |ct| {
                        if (ct == .integer) self.usage.output_tokens.total = @intCast(ct.integer);
                    }
                }
            }
        }

        fn finish(self: *StreamState) void {
            if (self.is_text_active) {
                self.callbacks.on_part(self.callbacks.ctx, .{ .text_end = .{ .id = "text-0" } });
            }

            self.callbacks.on_part(self.callbacks.ctx, .{
                .finish = .{
                    .finish_reason = self.finish_reason,
                    .usage = self.usage,
                },
            });

            self.callbacks.on_complete(self.callbacks.ctx, null);
        }
    };

    /// Stream content
    pub fn doStream(
        self: *const Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        const request_allocator = arena.allocator();

        // Build the request body with streaming enabled
        var request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callbacks.on_error(callbacks.ctx, err);
            arena.deinit();
            return;
        };

        // Add stream flag
        if (request_body == .object) {
            request_body.object.put("stream", .{ .bool = true }) catch |err| {
                callbacks.on_error(callbacks.ctx, err);
                arena.deinit();
                return;
            };
        }

        // Build URL
        const url = config_mod.buildChatCompletionsUrl(
            request_allocator,
            self.config.base_url,
        ) catch |err| {
            callbacks.on_error(callbacks.ctx, err);
            arena.deinit();
            return;
        };

        // Get headers
        var headers = std.StringHashMap([]const u8).init(request_allocator);
        if (self.config.headers_fn) |headers_fn| {
            headers = headers_fn(&self.config, request_allocator) catch |err| {
                callbacks.on_error(callbacks.ctx, err);
                arena.deinit();
                return;
            };
        }

        headers.put("Content-Type", "application/json") catch |err| {
            callbacks.on_error(callbacks.ctx, err);
            arena.deinit();
            return;
        };

        // Serialize request body
        var body_buffer = std.ArrayList(u8).empty;
        std.json.stringify(request_body, .{}, body_buffer.writer(request_allocator)) catch |err| {
            callbacks.on_error(callbacks.ctx, err);
            arena.deinit();
            return;
        };

        // Get HTTP client
        const http_client = self.config.http_client orelse {
            // No HTTP client - emit empty completion
            callbacks.on_part(callbacks.ctx, .{
                .finish = .{
                    .finish_reason = .stop,
                    .usage = lm.LanguageModelV3Usage.init(),
                },
            });
            callbacks.on_complete(callbacks.ctx, null);
            arena.deinit();
            return;
        };

        // Convert headers to slice
        var header_list = std.ArrayList(provider_utils.HttpClient.Header).empty;
        var header_iter = headers.iterator();
        while (header_iter.next()) |entry| {
            header_list.append(request_allocator, .{
                .name = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            }) catch |err| {
                callbacks.on_error(callbacks.ctx, err);
                arena.deinit();
                return;
            };
        }

        // Create stream state
        var stream_state = StreamState.init(callbacks, result_allocator, request_allocator);

        // Make streaming HTTP request
        http_client.requestStreaming(
            .{
                .method = .POST,
                .url = url,
                .headers = header_list.items,
                .body = body_buffer.items,
            },
            request_allocator,
            .{
                .on_chunk = struct {
                    fn onChunk(ctx: ?*anyopaque, chunk: []const u8) void {
                        const state: *StreamState = @ptrCast(@alignCast(ctx.?));
                        state.processChunk(chunk);
                    }
                }.onChunk,
                .on_complete = struct {
                    fn onComplete(ctx: ?*anyopaque) void {
                        const state: *StreamState = @ptrCast(@alignCast(ctx.?));
                        state.finish();
                    }
                }.onComplete,
                .on_error = struct {
                    fn onError(ctx: ?*anyopaque, _: provider_utils.HttpClient.HttpError) void {
                        const state: *StreamState = @ptrCast(@alignCast(ctx.?));
                        state.callbacks.on_error(state.callbacks.ctx, error.HttpRequestFailed);
                    }
                }.onError,
                .ctx = &stream_state,
            },
        );
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
                        var text_parts = std.ArrayList([]const u8).empty;
                        for (msg.content.user) |part| {
                            switch (part) {
                                .text => |t| try text_parts.append(allocator, t.text),
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
            try body.put("top_p", .{ .float = top_p });
        }
        if (call_options.seed) |seed| {
            try body.put("random_seed", .{ .integer = try provider_utils.safeCast(i64, seed) });
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
