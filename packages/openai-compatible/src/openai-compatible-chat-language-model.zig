const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");
const HttpClient = provider_utils.HttpClient;

const config_mod = @import("openai-compatible-config.zig");

/// OpenAI-compatible chat completion response
const ChatCompletionResponse = struct {
    id: []const u8 = "",
    model: []const u8 = "",
    choices: []const Choice = &.{},
    usage: ?Usage = null,

    const Choice = struct {
        message: Message = .{},
        finish_reason: ?[]const u8 = null,
    };

    const Message = struct {
        content: ?[]const u8 = null,
        tool_calls: ?[]const ToolCall = null,
    };

    const ToolCall = struct {
        id: ?[]const u8 = null,
        type: []const u8 = "function",
        function: Function = .{},
    };

    const Function = struct {
        name: []const u8 = "",
        arguments: ?[]const u8 = null,
    };

    const Usage = struct {
        prompt_tokens: u64 = 0,
        completion_tokens: u64 = 0,
        total_tokens: u64 = 0,
    };
};

/// OpenAI-compatible streaming chunk
const ChatCompletionChunk = struct {
    id: ?[]const u8 = null,
    model: ?[]const u8 = null,
    choices: []const ChunkChoice = &.{},
    usage: ?ChatCompletionResponse.Usage = null,

    const ChunkChoice = struct {
        delta: Delta = .{},
        finish_reason: ?[]const u8 = null,
    };

    const Delta = struct {
        content: ?[]const u8 = null,
        tool_calls: ?[]const DeltaToolCall = null,
    };

    const DeltaToolCall = struct {
        index: usize = 0,
        id: ?[]const u8 = null,
        function: ?DeltaFunction = null,
    };

    const DeltaFunction = struct {
        name: ?[]const u8 = null,
        arguments: ?[]const u8 = null,
    };
};

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
        const result = self.doGenerateInternal(call_options, result_allocator);
        switch (result) {
            .ok => |ok| callback(callback_context, .{ .success = ok }),
            .err => |err| callback(callback_context, .{ .failure = err }),
        }
    }

    const GenerateInternalResult = union(enum) {
        ok: lm.LanguageModelV3.GenerateSuccess,
        err: anyerror,
    };

    fn doGenerateInternal(
        self: *Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
    ) GenerateInternalResult {
        const success = self.doGenerateInternalImpl(call_options, result_allocator) catch |err| return .{ .err = err };
        return .{ .ok = success };
    }

    fn doGenerateInternalImpl(
        self: *Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
    ) !lm.LanguageModelV3.GenerateSuccess {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Build request body
        const request_body = try self.buildRequestBody(request_allocator, call_options);

        // Build URL
        const url = try config_mod.buildChatCompletionsUrl(request_allocator, self.config.base_url);

        // Get headers
        var headers = if (self.config.headers_fn) |headers_fn|
            try headers_fn(&self.config, request_allocator)
        else
            std.StringHashMap([]const u8).init(request_allocator);
        if (call_options.headers) |user_headers| {
            var iter = user_headers.iterator();
            while (iter.next()) |entry| {
                try headers.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Get HTTP client
        const http_client = self.config.http_client orelse return error.NoHttpClient;

        // Serialize request body to JSON string
        const body = try serializeJsonValue(request_allocator, request_body);

        // Make the request
        const HttpCallCtx = struct {
            response: ?provider_utils.HttpResponse = null,
            http_error: ?provider_utils.HttpError = null,
        };
        var call_ctx = HttpCallCtx{};

        try http_client.post(url, headers, body, request_allocator,
            struct {
                fn onResponse(ctx: ?*anyopaque, resp: provider_utils.HttpResponse) void {
                    const c: *HttpCallCtx = @ptrCast(@alignCast(ctx.?));
                    c.response = resp;
                }
            }.onResponse,
            struct {
                fn onError(ctx: ?*anyopaque, err: provider_utils.HttpError) void {
                    const c: *HttpCallCtx = @ptrCast(@alignCast(ctx.?));
                    c.http_error = err;
                }
            }.onError,
            @as(?*anyopaque, @ptrCast(&call_ctx)),
        );

        // Handle HTTP error
        if (call_ctx.http_error) |http_err| {
            if (call_options.error_diagnostic) |diag| {
                diag.provider = self.config.provider;
                diag.kind = .network;
                diag.setMessage(http_err.message);
                if (http_err.status_code) |code| {
                    diag.status_code = code;
                    diag.classifyStatus();
                }
            }
            return error.ApiCallError;
        }

        // Handle missing response
        const http_response = call_ctx.response orelse return error.NoResponse;

        // Handle non-success status
        if (!http_response.isSuccess()) {
            if (call_options.error_diagnostic) |diag| {
                diag.provider = self.config.provider;
                diag.populateFromResponse(http_response.status_code, http_response.body);
            }
            return error.ApiCallError;
        }

        // Parse response
        const parsed = std.json.parseFromSlice(ChatCompletionResponse, request_allocator, http_response.body, .{
            .ignore_unknown_fields = true,
        }) catch {
            return error.InvalidResponse;
        };
        defer parsed.deinit();
        const response = parsed.value;

        // Extract content
        var content: std.ArrayListUnmanaged(lm.LanguageModelV3Content) = .{};

        if (response.choices.len > 0) {
            const choice = response.choices[0];

            // Add text content
            if (choice.message.content) |text| {
                if (text.len > 0) {
                    try content.append(result_allocator, .{
                        .text = .{ .text = try result_allocator.dupe(u8, text) },
                    });
                }
            }

            // Add tool calls
            if (choice.message.tool_calls) |tool_calls| {
                for (tool_calls) |tc| {
                    try content.append(result_allocator, .{
                        .tool_call = .{
                            .tool_call_id = try result_allocator.dupe(u8, tc.id orelse ""),
                            .tool_name = try result_allocator.dupe(u8, tc.function.name),
                            .input = try result_allocator.dupe(u8, tc.function.arguments orelse "{}"),
                        },
                    });
                }
            }
        }

        // Convert usage
        const usage = convertUsage(response.usage);

        // Get finish reason
        const finish_reason = if (response.choices.len > 0)
            mapFinishReason(response.choices[0].finish_reason)
        else
            .unknown;

        return .{
            .content = try content.toOwnedSlice(result_allocator),
            .finish_reason = finish_reason,
            .usage = usage,
            .warnings = &[_]shared.SharedV3Warning{},
            .response = .{
                .metadata = .{
                    .id = if (response.id.len > 0) try result_allocator.dupe(u8, response.id) else null,
                    .model_id = if (response.model.len > 0) try result_allocator.dupe(u8, response.model) else null,
                },
            },
        };
    }

    pub fn doStream(
        self: *Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) void {
        self.doStreamInternal(call_options, result_allocator, callbacks) catch |err| {
            callbacks.on_error(callbacks.ctx, err);
        };
    }

    fn doStreamInternal(
        self: *Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Build request body with stream=true
        var request_body = try self.buildRequestBody(request_allocator, call_options);
        if (request_body == .object) {
            try request_body.object.put("stream", .{ .bool = true });
        }

        // Build URL
        const url = try config_mod.buildChatCompletionsUrl(request_allocator, self.config.base_url);

        // Get headers
        var headers = if (self.config.headers_fn) |headers_fn|
            try headers_fn(&self.config, request_allocator)
        else
            std.StringHashMap([]const u8).init(request_allocator);
        if (call_options.headers) |user_headers| {
            var iter = user_headers.iterator();
            while (iter.next()) |entry| {
                try headers.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Emit stream start
        callbacks.on_part(callbacks.ctx, .{ .stream_start = .{ .warnings = &[_]shared.SharedV3Warning{} } });

        // Get HTTP client
        const http_client = self.config.http_client orelse return error.NoHttpClient;

        // Serialize request body
        const body = try serializeJsonValue(request_allocator, request_body);

        // Stream state
        var stream_state = StreamState{
            .callbacks = callbacks,
            .result_allocator = result_allocator,
            .tool_calls = .{},
            .is_text_active = false,
            .finish_reason = .unknown,
        };

        // Make the streaming request
        try http_client.postStream(url, headers, body, request_allocator, .{
            .on_chunk = struct {
                fn cb(ctx: ?*anyopaque, chunk: []const u8) void {
                    const state: *StreamState = @ptrCast(@alignCast(ctx.?));
                    state.processChunk(chunk) catch |err| {
                        state.callbacks.on_error(state.callbacks.ctx, err);
                    };
                }
            }.cb,
            .on_complete = struct {
                fn cb(ctx: ?*anyopaque) void {
                    const state: *StreamState = @ptrCast(@alignCast(ctx.?));
                    state.finish();
                }
            }.cb,
            .on_error = struct {
                fn cb(ctx: ?*anyopaque, _: HttpClient.HttpError) void {
                    const state: *StreamState = @ptrCast(@alignCast(ctx.?));
                    state.callbacks.on_error(state.callbacks.ctx, error.ApiCallError);
                }
            }.cb,
            .ctx = @as(?*anyopaque, @ptrCast(&stream_state)),
        });
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
            try body.put("max_tokens", .{ .integer = try provider_utils.safeCast(i64, max_tokens) });
        }
        if (call_options.temperature) |temp| {
            try body.put("temperature", .{ .float = temp });
        }
        if (call_options.top_p) |top_p| {
            try body.put("top_p", .{ .float = top_p });
        }
        if (call_options.seed) |seed| {
            try body.put("seed", .{ .integer = try provider_utils.safeCast(i64, seed) });
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

/// State for tracking tool calls during streaming
const ToolCallState = struct {
    id: []const u8,
    name: []const u8,
    arguments: std.ArrayListUnmanaged(u8),
    has_finished: bool,
};

/// State for stream processing
const StreamState = struct {
    callbacks: lm.LanguageModelV3.StreamCallbacks,
    result_allocator: std.mem.Allocator,
    tool_calls: std.ArrayListUnmanaged(ToolCallState),
    is_text_active: bool,
    finish_reason: lm.LanguageModelV3FinishReason,
    usage: ?lm.LanguageModelV3Usage = null,

    fn processChunk(self: *StreamState, chunk_data: []const u8) !void {
        var lines = std.mem.splitSequence(u8, chunk_data, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "data: ")) {
                const json_data = line[6..];
                if (std.mem.eql(u8, json_data, "[DONE]")) continue;

                const parsed = std.json.parseFromSlice(ChatCompletionChunk, self.result_allocator, json_data, .{
                    .ignore_unknown_fields = true,
                }) catch {
                    continue;
                };
                defer parsed.deinit();
                const chunk = parsed.value;

                // Handle usage
                if (chunk.usage) |usage| {
                    self.usage = convertUsage(usage);
                }

                // Process choices
                if (chunk.choices.len == 0) continue;
                const choice = chunk.choices[0];

                // Update finish reason
                if (choice.finish_reason) |reason| {
                    self.finish_reason = mapFinishReason(reason);
                }

                const delta = choice.delta;

                // Handle text content
                if (delta.content) |content| {
                    if (!self.is_text_active) {
                        self.callbacks.on_part(self.callbacks.ctx, .{
                            .text_start = .{ .id = "0" },
                        });
                        self.is_text_active = true;
                    }
                    self.callbacks.on_part(self.callbacks.ctx, .{
                        .text_delta = .{ .id = "0", .delta = content },
                    });
                }

                // Handle tool calls
                if (delta.tool_calls) |tool_calls| {
                    for (tool_calls) |tc| {
                        try self.processToolCallDelta(tc);
                    }
                }
            }
        }
    }

    fn processToolCallDelta(self: *StreamState, tc: ChatCompletionChunk.DeltaToolCall) !void {
        const index = tc.index;

        // Ensure we have enough tool call slots
        while (self.tool_calls.items.len <= index) {
            try self.tool_calls.append(self.result_allocator, .{
                .id = "",
                .name = "",
                .arguments = .{},
                .has_finished = false,
            });
        }

        var tool_call = &self.tool_calls.items[index];

        if (tc.id) |id| {
            tool_call.id = try self.result_allocator.dupe(u8, id);
        }

        if (tc.function) |func| {
            if (func.name) |name| {
                tool_call.name = try self.result_allocator.dupe(u8, name);
                self.callbacks.on_part(self.callbacks.ctx, .{
                    .tool_input_start = .{
                        .id = tool_call.id,
                        .tool_name = tool_call.name,
                    },
                });
            }

            if (func.arguments) |args| {
                try tool_call.arguments.appendSlice(self.result_allocator, args);
                self.callbacks.on_part(self.callbacks.ctx, .{
                    .tool_input_delta = .{
                        .id = tool_call.id,
                        .delta = args,
                    },
                });

                if (!tool_call.has_finished) {
                    if (isValidJson(self.result_allocator, tool_call.arguments.items)) {
                        tool_call.has_finished = true;
                        self.callbacks.on_part(self.callbacks.ctx, .{
                            .tool_input_end = .{ .id = tool_call.id },
                        });
                    }
                }
            }
        }
    }

    fn finish(self: *StreamState) void {
        if (self.is_text_active) {
            self.callbacks.on_part(self.callbacks.ctx, .{
                .text_end = .{ .id = "0" },
            });
        }

        self.callbacks.on_part(self.callbacks.ctx, .{
            .finish = .{
                .finish_reason = self.finish_reason,
                .usage = self.usage orelse lm.LanguageModelV3Usage.init(),
            },
        });

        self.callbacks.on_complete(self.callbacks.ctx, null);
    }
};

/// Map finish reason string to enum
fn mapFinishReason(reason: ?[]const u8) lm.LanguageModelV3FinishReason {
    const r = reason orelse return .unknown;
    if (std.mem.eql(u8, r, "stop")) return .stop;
    if (std.mem.eql(u8, r, "length")) return .length;
    if (std.mem.eql(u8, r, "content_filter")) return .content_filter;
    if (std.mem.eql(u8, r, "tool_calls")) return .tool_calls;
    if (std.mem.eql(u8, r, "function_call")) return .tool_calls;
    return .other;
}

/// Convert usage from response to LanguageModelV3Usage
fn convertUsage(usage: ?ChatCompletionResponse.Usage) lm.LanguageModelV3Usage {
    if (usage) |u| {
        return .{
            .input_tokens = .{ .total = u.prompt_tokens },
            .output_tokens = .{ .total = u.completion_tokens },
        };
    }
    return lm.LanguageModelV3Usage.init();
}

/// Serialize std.json.Value to a JSON string
fn serializeJsonValue(allocator: std.mem.Allocator, value: std.json.Value) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, value, .{});
}

/// Check if a string is valid JSON
fn isValidJson(allocator: std.mem.Allocator, data: []const u8) bool {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return false;
    defer parsed.deinit();
    return true;
}

test "OpenAICompatibleChatLanguageModel init" {
    const allocator = std.testing.allocator;

    var model = OpenAICompatibleChatLanguageModel.init(
        allocator,
        "test-model",
        .{ .base_url = "https://api.example.com/v1" },
    );

    try std.testing.expectEqualStrings("test-model", model.getModelId());
}

test "mapFinishReason" {
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.stop, mapFinishReason("stop"));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.length, mapFinishReason("length"));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.content_filter, mapFinishReason("content_filter"));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.tool_calls, mapFinishReason("tool_calls"));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.tool_calls, mapFinishReason("function_call"));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.other, mapFinishReason("something_else"));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.unknown, mapFinishReason(null));
}

test "convertUsage" {
    const usage = ChatCompletionResponse.Usage{
        .prompt_tokens = 10,
        .completion_tokens = 20,
        .total_tokens = 30,
    };
    const result = convertUsage(usage);
    try std.testing.expectEqual(@as(?u64, 10), result.input_tokens.total);
    try std.testing.expectEqual(@as(?u64, 20), result.output_tokens.total);
}

test "convertUsage null" {
    const result = convertUsage(null);
    try std.testing.expectEqual(@as(?u64, null), result.input_tokens.total);
    try std.testing.expectEqual(@as(?u64, null), result.output_tokens.total);
}

test "serializeJsonValue" {
    const allocator = std.testing.allocator;
    var obj = std.json.ObjectMap.init(allocator);
    defer obj.deinit();
    try obj.put("model", .{ .string = "test" });
    const json_str = try serializeJsonValue(allocator, .{ .object = obj });
    defer allocator.free(json_str);
    try std.testing.expectEqualStrings("{\"model\":\"test\"}", json_str);
}
