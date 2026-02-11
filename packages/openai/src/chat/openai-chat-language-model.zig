const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");
const json_value = @import("provider").json_value;

const api = @import("openai-chat-api.zig");
const options_mod = @import("openai-chat-options.zig");
const convert = @import("convert-to-openai-chat-messages.zig");
const prepare_tools = @import("openai-chat-prepare-tools.zig");
const map_finish = @import("map-openai-finish-reason.zig");
const config_mod = @import("../openai-config.zig");
const error_mod = @import("../openai-error.zig");

/// OpenAI Chat Language Model implementation
pub const OpenAIChatLanguageModel = struct {
    const Self = @This();

    /// Model ID
    model_id: []const u8,

    /// Configuration
    config: config_mod.OpenAIConfig,

    /// Allocator for internal operations
    allocator: std.mem.Allocator,

    pub const specification_version = "v3";

    /// Initialize a new OpenAI chat language model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.OpenAIConfig,
    ) Self {
        return .{
            .model_id = model_id,
            .config = config,
            .allocator = allocator,
        };
    }

    /// Get the provider name
    pub fn getProvider(self: *const Self) []const u8 {
        return self.config.provider;
    }

    /// Get the model ID
    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    /// Generate a response (non-streaming)
    pub fn doGenerate(
        self: *const Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, GenerateResult) void,
        context: ?*anyopaque,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Build the result
        const result = self.doGenerateInternal(request_allocator, result_allocator, call_options) catch |err| {
            callback(context, .{ .err = err });
            return;
        };

        callback(context, .{ .ok = result });
    }

    fn doGenerateInternal(
        self: *const Self,
        request_allocator: std.mem.Allocator,
        result_allocator: std.mem.Allocator,
        call_options: lm.LanguageModelV3CallOptions,
    ) !GenerateResultOk {
        var all_warnings = std.ArrayList(shared.SharedV3Warning).empty;

        // Check for unsupported features
        if (call_options.top_k != null) {
            try all_warnings.append(request_allocator,shared.SharedV3Warning.unsupportedFeature("topK", null));
        }

        // Determine system message mode
        const is_reasoning = options_mod.isReasoningModel(self.model_id);
        const system_mode: convert.ConvertOptions.SystemMessageMode = if (is_reasoning) .developer else .system;

        // Convert messages
        const convert_result = try convert.convertToOpenAIChatMessages(request_allocator, .{
            .prompt = call_options.prompt,
            .system_message_mode = system_mode,
        });
        try all_warnings.appendSlice(request_allocator,convert_result.warnings);

        // Prepare tools
        const tools_result = try prepare_tools.prepareChatTools(request_allocator, .{
            .tools = call_options.tools,
            .tool_choice = call_options.tool_choice,
        });
        try all_warnings.appendSlice(request_allocator,tools_result.tool_warnings);

        // Build request body
        var request = api.OpenAIChatRequest{
            .model = self.model_id,
            .messages = convert_result.messages,
            .tools = tools_result.tools,
            .tool_choice = tools_result.tool_choice,
            .max_tokens = call_options.max_output_tokens,
            .temperature = call_options.temperature,
            .top_p = call_options.top_p,
            .frequency_penalty = call_options.frequency_penalty,
            .presence_penalty = call_options.presence_penalty,
            .stop = call_options.stop_sequences,
            .seed = call_options.seed,
            .stream = false,
        };

        // Handle reasoning model restrictions
        if (is_reasoning) {
            if (request.temperature != null) {
                request.temperature = null;
                try all_warnings.append(request_allocator,shared.SharedV3Warning.unsupportedFeature("temperature", "temperature is not supported for reasoning models"));
            }
            if (request.top_p != null) {
                request.top_p = null;
                try all_warnings.append(request_allocator,shared.SharedV3Warning.unsupportedFeature("topP", "topP is not supported for reasoning models"));
            }
            if (request.frequency_penalty != null) {
                request.frequency_penalty = null;
                try all_warnings.append(request_allocator,shared.SharedV3Warning.unsupportedFeature("frequencyPenalty", "frequencyPenalty is not supported for reasoning models"));
            }
            if (request.presence_penalty != null) {
                request.presence_penalty = null;
                try all_warnings.append(request_allocator,shared.SharedV3Warning.unsupportedFeature("presencePenalty", "presencePenalty is not supported for reasoning models"));
            }
            // Use max_completion_tokens for reasoning models
            if (request.max_tokens) |mt| {
                request.max_completion_tokens = mt;
                request.max_tokens = null;
            }
        }

        // Build URL
        const url = try self.config.buildUrl(request_allocator, "/chat/completions", self.model_id);

        // Get headers
        var headers = try self.config.getHeaders(request_allocator);
        if (call_options.headers) |user_headers| {
            var iter = user_headers.iterator();
            while (iter.next()) |entry| {
                try headers.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Make HTTP request
        const http_client = self.config.http_client orelse return error.NoHttpClient;

        // Serialize request body
        const body = try serializeRequest(request_allocator, request);

        // Make the request
        var response_data: ?[]const u8 = null;
        var response_headers: ?std.StringHashMap([]const u8) = null;

        try http_client.post(url, headers, body, request_allocator, struct {
            fn onResponse(ctx: *anyopaque, resp_headers: std.StringHashMap([]const u8), resp_body: []const u8) void {
                const data = @as(*struct { body: *?[]const u8, headers: *?std.StringHashMap([]const u8) }, @ptrCast(@alignCast(ctx)));
                data.body.* = resp_body;
                data.headers.* = resp_headers;
            }
            fn onError(_: *anyopaque, _: anyerror) void {}
        }.onResponse, struct {
            fn onError(_: *anyopaque, _: anyerror) void {}
        }.onError, &.{ .body = &response_data, .headers = &response_headers });

        const response_body = response_data orelse return error.NoResponse;

        // Parse response
        const parsed = std.json.parseFromSlice(api.OpenAIChatResponse, request_allocator, response_body, .{}) catch {
            return error.InvalidResponse;
        };
        const response = parsed.value;

        // Extract content
        var content = std.ArrayList(lm.LanguageModelV3Content).empty;

        if (response.choices.len > 0) {
            const choice = response.choices[0];

            // Add text content
            if (choice.message.content) |text| {
                if (text.len > 0) {
                    const text_copy = try result_allocator.dupe(u8, text);
                    try content.append(result_allocator, .{
                        .text = .{
                            .text = text_copy,
                        },
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

            // Add annotations/sources
            if (choice.message.annotations) |annotations| {
                for (annotations) |ann| {
                    try content.append(result_allocator, .{
                        .source = .{
                            .source_type = .url,
                            .id = try provider_utils.generateId(result_allocator),
                            .data = .{
                                .url = .{
                                    .url = try result_allocator.dupe(u8, ann.url_citation.url),
                                    .title = if (ann.url_citation.title) |t| try result_allocator.dupe(u8, t) else null,
                                },
                            },
                        },
                    });
                }
            }
        }

        // Convert usage
        const usage = api.convertOpenAIChatUsage(response.usage);

        // Get finish reason
        const finish_reason = if (response.choices.len > 0)
            map_finish.mapOpenAIFinishReason(response.choices[0].finish_reason)
        else
            .unknown;

        // Clone warnings to result allocator
        var result_warnings = try result_allocator.alloc(shared.SharedV3Warning, all_warnings.items.len);
        for (all_warnings.items, 0..) |w, i| {
            result_warnings[i] = w;
        }

        return .{
            .content = try content.toOwnedSlice(result_allocator),
            .finish_reason = finish_reason,
            .usage = usage,
            .warnings = result_warnings,
            .response_id = if (response.id.len > 0) try result_allocator.dupe(u8, response.id) else null,
            .model_id = if (response.model.len > 0) try result_allocator.dupe(u8, response.model) else null,
        };
    }

    /// Stream a response
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

        self.doStreamInternal(request_allocator, result_allocator, call_options, callbacks) catch |err| {
            callbacks.on_error(callbacks.ctx, err);
        };
    }

    fn doStreamInternal(
        self: *const Self,
        request_allocator: std.mem.Allocator,
        result_allocator: std.mem.Allocator,
        call_options: lm.LanguageModelV3CallOptions,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) !void {
        var all_warnings = std.ArrayList(shared.SharedV3Warning).empty;

        // Check for unsupported features
        if (call_options.top_k != null) {
            try all_warnings.append(request_allocator,shared.SharedV3Warning.unsupportedFeature("topK", null));
        }

        // Determine system message mode
        const is_reasoning = options_mod.isReasoningModel(self.model_id);
        const system_mode: convert.ConvertOptions.SystemMessageMode = if (is_reasoning) .developer else .system;

        // Convert messages
        const convert_result = try convert.convertToOpenAIChatMessages(request_allocator, .{
            .prompt = call_options.prompt,
            .system_message_mode = system_mode,
        });
        try all_warnings.appendSlice(request_allocator,convert_result.warnings);

        // Prepare tools
        const tools_result = try prepare_tools.prepareChatTools(request_allocator, .{
            .tools = call_options.tools,
            .tool_choice = call_options.tool_choice,
        });
        try all_warnings.appendSlice(request_allocator,tools_result.tool_warnings);

        // Build request body with streaming enabled
        var request = api.OpenAIChatRequest{
            .model = self.model_id,
            .messages = convert_result.messages,
            .tools = tools_result.tools,
            .tool_choice = tools_result.tool_choice,
            .max_tokens = call_options.max_output_tokens,
            .temperature = call_options.temperature,
            .top_p = call_options.top_p,
            .frequency_penalty = call_options.frequency_penalty,
            .presence_penalty = call_options.presence_penalty,
            .stop = call_options.stop_sequences,
            .seed = call_options.seed,
            .stream = true,
            .stream_options = .{ .include_usage = true },
        };

        // Handle reasoning model restrictions (same as doGenerate)
        if (is_reasoning) {
            if (request.temperature != null) {
                request.temperature = null;
            }
            if (request.top_p != null) {
                request.top_p = null;
            }
            if (request.frequency_penalty != null) {
                request.frequency_penalty = null;
            }
            if (request.presence_penalty != null) {
                request.presence_penalty = null;
            }
            if (request.max_tokens) |mt| {
                request.max_completion_tokens = mt;
                request.max_tokens = null;
            }
        }

        // Emit stream start
        const warnings_copy = try result_allocator.alloc(shared.SharedV3Warning, all_warnings.items.len);
        for (all_warnings.items, 0..) |w, i| {
            warnings_copy[i] = w;
        }
        callbacks.on_part(callbacks.ctx, .{ .stream_start = .{ .warnings = warnings_copy } });

        // Build URL
        const url = try self.config.buildUrl(request_allocator, "/chat/completions", self.model_id);

        // Get headers
        var headers = try self.config.getHeaders(request_allocator);
        if (call_options.headers) |user_headers| {
            var iter = user_headers.iterator();
            while (iter.next()) |entry| {
                try headers.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Make HTTP request
        const http_client = self.config.http_client orelse return error.NoHttpClient;

        // Serialize request body
        const body = try serializeRequest(request_allocator, request);

        // Stream state
        var stream_state = StreamState{
            .callbacks = callbacks,
            .result_allocator = result_allocator,
            .tool_calls = std.ArrayList(ToolCallState).empty,
            .is_text_active = false,
            .finish_reason = .unknown,
        };

        // Make the streaming request
        http_client.postStream(url, headers, body, request_allocator, struct {
            fn onChunk(ctx: *anyopaque, chunk: []const u8) void {
                const state = @as(*StreamState, @ptrCast(@alignCast(ctx)));
                state.processChunk(chunk) catch |err| {
                    state.callbacks.on_error(state.callbacks.ctx, err);
                };
            }
            fn onComplete(ctx: *anyopaque) void {
                const state = @as(*StreamState, @ptrCast(@alignCast(ctx)));
                state.finish();
            }
            fn onError(ctx: *anyopaque, err: anyerror) void {
                const state = @as(*StreamState, @ptrCast(@alignCast(ctx)));
                state.callbacks.on_error(state.callbacks.ctx, err);
            }
        }.onChunk, struct {
            fn onComplete(ctx: *anyopaque) void {
                const state = @as(*StreamState, @ptrCast(@alignCast(ctx)));
                state.finish();
            }
        }.onComplete, struct {
            fn onError(ctx: *anyopaque, err: anyerror) void {
                const state = @as(*StreamState, @ptrCast(@alignCast(ctx)));
                state.callbacks.on_error(state.callbacks.ctx, err);
            }
        }.onError, &stream_state);
    }

    /// Convert to LanguageModelV3 interface
    pub fn asLanguageModel(self: *Self) lm.LanguageModelV3 {
        return .{
            .vtable = &vtable,
            .impl = self,
        };
    }

    const vtable = lm.LanguageModelV3.VTable{
        .getProvider = getProviderVtable,
        .getModelId = getModelIdVtable,
        .getSupportedUrls = getSupportedUrlsVtable,
        .doGenerate = doGenerateVtable,
        .doStream = doStreamVtable,
    };

    fn getSupportedUrlsVtable(
        impl: *anyopaque,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, lm.LanguageModelV3.SupportedUrlsResult) void,
        ctx: ?*anyopaque,
    ) void {
        _ = impl;
        callback(ctx, .{ .success = std.StringHashMap([]const []const u8).init(allocator) });
    }

    fn getProviderVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getProvider();
    }

    fn getModelIdVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getModelId();
    }

    fn doGenerateVtable(
        impl: *anyopaque,
        options: lm.LanguageModelV3CallOptions,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, lm.LanguageModelV3.GenerateResult) void,
        context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        // Wrap callback to convert result type
        const Wrapper = struct {
            fn wrap(ctx: ?*anyopaque, result: GenerateResult) void {
                const cb_data = @as(*const struct { cb: *const fn (?*anyopaque, lm.LanguageModelV3.GenerateResult) void, user_ctx: ?*anyopaque }, @ptrCast(@alignCast(ctx)));
                switch (result) {
                    .ok => |ok| {
                        cb_data.cb(cb_data.user_ctx, .{
                            .success = .{
                                .content = ok.content,
                                .finish_reason = ok.finish_reason,
                                .usage = ok.usage,
                                .warnings = ok.warnings,
                            },
                        });
                    },
                    .err => |err| {
                        cb_data.cb(cb_data.user_ctx, .{ .failure = err });
                    },
                }
            }
        };
        var wrapper_data = struct { cb: *const fn (?*anyopaque, lm.LanguageModelV3.GenerateResult) void, user_ctx: ?*anyopaque }{ .cb = callback, .user_ctx = context };
        self.doGenerate(options, allocator, Wrapper.wrap, @ptrCast(&wrapper_data));
    }

    fn doStreamVtable(
        impl: *anyopaque,
        options: lm.LanguageModelV3CallOptions,
        allocator: std.mem.Allocator,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) void {
        _ = impl;
        _ = allocator;
        _ = options;
        // Stub for now - streaming not yet implemented
        callbacks.on_complete(callbacks.ctx, null);
    }
};

/// Result of generate call
pub const GenerateResult = union(enum) {
    ok: GenerateResultOk,
    err: anyerror,
};

pub const GenerateResultOk = struct {
    content: []lm.LanguageModelV3Content,
    finish_reason: lm.LanguageModelV3FinishReason,
    usage: lm.LanguageModelV3Usage,
    warnings: []shared.SharedV3Warning,
    response_id: ?[]const u8 = null,
    model_id: ?[]const u8 = null,
};

/// State for tracking tool calls during streaming
const ToolCallState = struct {
    id: []const u8,
    name: []const u8,
    arguments: std.ArrayList(u8),
    has_finished: bool,
};

/// State for stream processing
const StreamState = struct {
    callbacks: lm.LanguageModelV3.StreamCallbacks,
    result_allocator: std.mem.Allocator,
    tool_calls: std.ArrayList(ToolCallState),
    is_text_active: bool,
    finish_reason: lm.LanguageModelV3FinishReason,
    usage: ?lm.LanguageModelV3Usage = null,

    fn processChunk(self: *StreamState, chunk_data: []const u8) !void {
        // Parse SSE chunk (data: {...})
        var lines = std.mem.splitSequence(u8, chunk_data, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "data: ")) {
                const json_data = line[6..];
                if (std.mem.eql(u8, json_data, "[DONE]")) {
                    continue;
                }

                const parsed = std.json.parseFromSlice(api.OpenAIChatChunk, self.result_allocator, json_data, .{}) catch |err| {
                    // Report JSON parse error to caller but continue processing subsequent chunks
                    self.callbacks.on_part(self.callbacks.ctx, .{
                        .@"error" = .{ .err = err, .message = "Failed to parse SSE chunk JSON" },
                    });
                    continue;
                };
                const chunk = parsed.value;

                // Handle error chunks
                if (chunk.@"error") |err| {
                    self.finish_reason = .@"error";
                    self.callbacks.on_part(self.callbacks.ctx, .{
                        .@"error" = .{ .err = error.ApiError, .message = err.message },
                    });
                    continue;
                }

                // Handle usage
                if (chunk.usage) |usage| {
                    self.usage = api.convertOpenAIChatUsage(usage);
                }

                // Process choices
                if (chunk.choices.len == 0) continue;
                const choice = chunk.choices[0];

                // Update finish reason
                if (choice.finish_reason) |reason| {
                    self.finish_reason = map_finish.mapOpenAIFinishReason(reason);
                }

                // Process delta
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
                        .text_delta = .{
                            .id = "0",
                            .delta = content,
                        },
                    });
                }

                // Handle tool calls
                if (delta.tool_calls) |tool_calls| {
                    for (tool_calls) |tc| {
                        try self.processToolCallDelta(tc);
                    }
                }

                // Handle annotations
                if (delta.annotations) |annotations| {
                    for (annotations) |ann| {
                        self.callbacks.on_part(self.callbacks.ctx, .{
                            .source = .{
                                .source_type = .url,
                                .id = try provider_utils.generateId(self.result_allocator),
                                .url = ann.url_citation.url,
                                .title = ann.url_citation.title,
                            },
                        });
                    }
                }
            }
        }
    }

    fn processToolCallDelta(self: *StreamState, tc: api.OpenAIChatChunk.DeltaToolCall) !void {
        const index = tc.index;

        // Ensure we have enough tool call slots
        while (self.tool_calls.items.len <= index) {
            try self.tool_calls.append(self.result_allocator, .{
                .id = "",
                .name = "",
                .arguments = std.ArrayList(u8).empty,
                .has_finished = false,
            });
        }

        var tool_call = &self.tool_calls.items[index];

        // New tool call
        if (tc.id) |id| {
            tool_call.id = try self.result_allocator.dupe(u8, id);
        }

        if (tc.function) |func| {
            if (func.name) |name| {
                tool_call.name = try self.result_allocator.dupe(u8, name);

                // Emit tool input start
                self.callbacks.on_part(self.callbacks.ctx, .{
                    .tool_input_start = .{
                        .id = tool_call.id,
                        .tool_name = tool_call.name,
                    },
                });
            }

            if (func.arguments) |args| {
                try tool_call.arguments.appendSlice(self.result_allocator, args);

                // Emit tool input delta
                self.callbacks.on_part(self.callbacks.ctx, .{
                    .tool_input_delta = .{
                        .id = tool_call.id,
                        .delta = args,
                    },
                });

                // Check if complete (valid JSON)
                if (!tool_call.has_finished) {
                    if (isValidJson(self.result_allocator, tool_call.arguments.items)) {
                        tool_call.has_finished = true;

                        // Emit tool input end
                        self.callbacks.on_part(self.callbacks.ctx, .{
                            .tool_input_end = .{ .id = tool_call.id },
                        });

                        // Emit tool call
                        self.callbacks.on_part(self.callbacks.ctx, .{
                            .tool_call = .{
                                .tool_call_id = tool_call.id,
                                .tool_name = tool_call.name,
                                .input = json_value.JsonValue.parse(self.result_allocator, tool_call.arguments.items) catch .{ .object = json_value.JsonObject.init(self.result_allocator) },
                            },
                        });
                    }
                }
            }
        }
    }

    fn finish(self: *StreamState) void {
        // End text if active
        if (self.is_text_active) {
            self.callbacks.on_part(self.callbacks.ctx, .{
                .text_end = .{ .id = "0" },
            });
        }

        // Emit finish
        self.callbacks.on_part(self.callbacks.ctx, .{
            .finish = .{
                .finish_reason = self.finish_reason,
                .usage = self.usage orelse lm.LanguageModelV3Usage.init(),
            },
        });

        // Call complete callback
        self.callbacks.on_complete(self.callbacks.ctx, null);
    }
};

/// Check if a string is valid JSON
fn isValidJson(allocator: std.mem.Allocator, data: []const u8) bool {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return false;
    defer parsed.deinit();
    return true;
}

/// Serialize request to JSON - manually to avoid HashMap serialization issues
fn serializeRequest(allocator: std.mem.Allocator, request: api.OpenAIChatRequest) ![]const u8 {
    var obj = json_value.JsonObject.init(allocator);

    try obj.put("model", .{ .string = request.model });

    // Serialize messages array
    var messages_list = std.ArrayList(json_value.JsonValue).empty;
    for (request.messages) |msg| {
        var msg_obj = json_value.JsonObject.init(allocator);
        try msg_obj.put("role", .{ .string = msg.role });
        if (msg.content) |content| {
            switch (content) {
                .text => |t| try msg_obj.put("content", .{ .string = t }),
                .parts => |parts| {
                    var parts_list = std.ArrayList(json_value.JsonValue).empty;
                    for (parts) |part| {
                        var part_obj = json_value.JsonObject.init(allocator);
                        switch (part) {
                            .text => |tp| {
                                try part_obj.put("type", .{ .string = "text" });
                                try part_obj.put("text", .{ .string = tp.text });
                            },
                            .image_url => |ip| {
                                try part_obj.put("type", .{ .string = "image_url" });
                                var img_obj = json_value.JsonObject.init(allocator);
                                try img_obj.put("url", .{ .string = ip.image_url.url });
                                if (ip.image_url.detail) |d| try img_obj.put("detail", .{ .string = d });
                                try part_obj.put("image_url", .{ .object = img_obj });
                            },
                        }
                        try parts_list.append(allocator, .{ .object = part_obj });
                    }
                    try msg_obj.put("content", .{ .array = try parts_list.toOwnedSlice(allocator) });
                },
            }
        }
        if (msg.name) |n| try msg_obj.put("name", .{ .string = n });
        if (msg.tool_call_id) |tid| try msg_obj.put("tool_call_id", .{ .string = tid });
        if (msg.tool_calls) |tcs| {
            var tcs_list = std.ArrayList(json_value.JsonValue).empty;
            for (tcs) |tc| {
                var tc_obj = json_value.JsonObject.init(allocator);
                if (tc.id) |id| try tc_obj.put("id", .{ .string = id });
                try tc_obj.put("type", .{ .string = tc.type });
                var fn_obj = json_value.JsonObject.init(allocator);
                try fn_obj.put("name", .{ .string = tc.function.name });
                if (tc.function.arguments) |args| try fn_obj.put("arguments", .{ .string = args });
                try tc_obj.put("function", .{ .object = fn_obj });
                try tcs_list.append(allocator, .{ .object = tc_obj });
            }
            try msg_obj.put("tool_calls", .{ .array = try tcs_list.toOwnedSlice(allocator) });
        }
        try messages_list.append(allocator, .{ .object = msg_obj });
    }
    try obj.put("messages", .{ .array = try messages_list.toOwnedSlice(allocator) });

    // Add optional fields
    if (request.max_tokens) |mt| try obj.put("max_tokens", .{ .integer = try provider_utils.safeCast(i64, mt) });
    if (request.max_completion_tokens) |mct| try obj.put("max_completion_tokens", .{ .integer = try provider_utils.safeCast(i64, mct) });
    if (request.temperature) |t| try obj.put("temperature", .{ .float = t });
    if (request.top_p) |tp| try obj.put("top_p", .{ .float = tp });
    if (request.frequency_penalty) |fp| try obj.put("frequency_penalty", .{ .float = fp });
    if (request.presence_penalty) |pp| try obj.put("presence_penalty", .{ .float = pp });
    if (request.seed) |s| try obj.put("seed", .{ .integer = try provider_utils.safeCast(i64, s) });

    if (request.stop) |stops| {
        var stop_list = std.ArrayList(json_value.JsonValue).empty;
        for (stops) |s| try stop_list.append(allocator, .{ .string = s });
        try obj.put("stop", .{ .array = try stop_list.toOwnedSlice(allocator) });
    }

    if (request.tools) |tools| {
        var tools_list = std.ArrayList(json_value.JsonValue).empty;
        for (tools) |tool| {
            var tool_obj = json_value.JsonObject.init(allocator);
            try tool_obj.put("type", .{ .string = tool.type });
            var fn_obj = json_value.JsonObject.init(allocator);
            try fn_obj.put("name", .{ .string = tool.function.name });
            if (tool.function.description) |d| try fn_obj.put("description", .{ .string = d });
            if (tool.function.parameters) |p| try fn_obj.put("parameters", p);
            if (tool.function.strict) |st| try fn_obj.put("strict", .{ .bool = st });
            try tool_obj.put("function", .{ .object = fn_obj });
            try tools_list.append(allocator, .{ .object = tool_obj });
        }
        try obj.put("tools", .{ .array = try tools_list.toOwnedSlice(allocator) });
    }

    if (request.tool_choice) |tc| {
        switch (tc) {
            .auto => |a| try obj.put("tool_choice", .{ .string = a }),
            .none => |n| try obj.put("tool_choice", .{ .string = n }),
            .required => |r| try obj.put("tool_choice", .{ .string = r }),
            .function => |f| {
                var tc_obj = json_value.JsonObject.init(allocator);
                try tc_obj.put("type", .{ .string = f.type });
                var fn_obj = json_value.JsonObject.init(allocator);
                try fn_obj.put("name", .{ .string = f.function.name });
                try tc_obj.put("function", .{ .object = fn_obj });
                try obj.put("tool_choice", .{ .object = tc_obj });
            },
        }
    }

    if (request.response_format) |rf| {
        switch (rf) {
            .text => |t| {
                var rf_obj = json_value.JsonObject.init(allocator);
                try rf_obj.put("type", .{ .string = t.type });
                try obj.put("response_format", .{ .object = rf_obj });
            },
            .json_object => |jo| {
                var rf_obj = json_value.JsonObject.init(allocator);
                try rf_obj.put("type", .{ .string = jo.type });
                try obj.put("response_format", .{ .object = rf_obj });
            },
            .json_schema => |js| {
                var rf_obj = json_value.JsonObject.init(allocator);
                try rf_obj.put("type", .{ .string = js.type });
                var schema_obj = json_value.JsonObject.init(allocator);
                try schema_obj.put("name", .{ .string = js.json_schema.name });
                if (js.json_schema.description) |d| try schema_obj.put("description", .{ .string = d });
                try schema_obj.put("schema", js.json_schema.schema);
                try schema_obj.put("strict", .{ .bool = js.json_schema.strict });
                try rf_obj.put("json_schema", .{ .object = schema_obj });
                try obj.put("response_format", .{ .object = rf_obj });
            },
        }
    }

    if (request.stream) try obj.put("stream", .{ .bool = true });
    if (request.stream_options) |so| {
        var so_obj = json_value.JsonObject.init(allocator);
        try so_obj.put("include_usage", .{ .bool = so.include_usage });
        try obj.put("stream_options", .{ .object = so_obj });
    }

    if (request.logprobs) |lp| try obj.put("logprobs", .{ .bool = lp });
    if (request.top_logprobs) |tlp| try obj.put("top_logprobs", .{ .integer = try provider_utils.safeCast(i64, tlp) });
    if (request.user) |u| try obj.put("user", .{ .string = u });
    if (request.store) |st| try obj.put("store", .{ .bool = st });
    if (request.reasoning_effort) |re| try obj.put("reasoning_effort", .{ .string = re });
    if (request.service_tier) |st| try obj.put("service_tier", .{ .string = st });
    if (request.verbosity) |v| try obj.put("verbosity", .{ .string = v });

    // Note: logit_bias and metadata (HashMap types) are not serialized here

    const json_val = json_value.JsonValue{ .object = obj };
    return json_val.stringify(allocator);
}

test "OpenAIChatLanguageModel basic" {
    const allocator = std.testing.allocator;

    const config = config_mod.OpenAIConfig{
        .provider = "openai.chat",
        .base_url = "https://api.openai.com/v1",
        .headers_fn = struct {
            fn getHeaders(_: *const config_mod.OpenAIConfig, alloc: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(alloc);
            }
        }.getHeaders,
    };

    const model = OpenAIChatLanguageModel.init(allocator, "gpt-4o", config);
    try std.testing.expectEqualStrings("openai.chat", model.getProvider());
    try std.testing.expectEqualStrings("gpt-4o", model.getModelId());
}

test "OpenAI response parsing - basic completion" {
    const allocator = std.testing.allocator;
    const response_json =
        \\{"id":"chatcmpl-123","object":"chat.completion","created":1677652288,"model":"gpt-4o","choices":[{"index":0,"message":{"role":"assistant","content":"Hello! How can I help?"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":8,"total_tokens":18}}
    ;

    const parsed = std.json.parseFromSlice(api.OpenAIChatResponse, allocator, response_json, .{}) catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return err;
    };
    defer parsed.deinit();
    const response = parsed.value;

    try std.testing.expectEqualStrings("chatcmpl-123", response.id);
    try std.testing.expectEqualStrings("gpt-4o", response.model);
    try std.testing.expectEqual(@as(usize, 1), response.choices.len);
    try std.testing.expectEqualStrings("Hello! How can I help?", response.choices[0].message.content.?);
    try std.testing.expectEqualStrings("stop", response.choices[0].finish_reason.?);
    try std.testing.expectEqual(@as(u64, 10), response.usage.?.prompt_tokens);
    try std.testing.expectEqual(@as(u64, 8), response.usage.?.completion_tokens);
}

test "OpenAI response parsing - with tool calls" {
    const allocator = std.testing.allocator;
    const response_json =
        \\{"id":"chatcmpl-456","object":"chat.completion","created":1677652288,"model":"gpt-4o","choices":[{"index":0,"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_123","type":"function","function":{"name":"get_weather","arguments":"{\"location\":\"NYC\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":15,"completion_tokens":20,"total_tokens":35}}
    ;

    const parsed = try std.json.parseFromSlice(api.OpenAIChatResponse, allocator, response_json, .{});
    defer parsed.deinit();
    const response = parsed.value;

    try std.testing.expectEqual(@as(usize, 1), response.choices.len);
    try std.testing.expect(response.choices[0].message.content == null);
    try std.testing.expectEqual(@as(usize, 1), response.choices[0].message.tool_calls.?.len);

    const tool_call = response.choices[0].message.tool_calls.?[0];
    try std.testing.expectEqualStrings("call_123", tool_call.id.?);
    try std.testing.expectEqualStrings("function", tool_call.type);
    try std.testing.expectEqualStrings("get_weather", tool_call.function.name);
    try std.testing.expectEqualStrings("{\"location\":\"NYC\"}", tool_call.function.arguments.?);
}

test "OpenAI finish reason mapping" {
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.stop, map_finish.mapOpenAIFinishReason("stop"));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.length, map_finish.mapOpenAIFinishReason("length"));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.tool_calls, map_finish.mapOpenAIFinishReason("tool_calls"));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.content_filter, map_finish.mapOpenAIFinishReason("content_filter"));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.other, map_finish.mapOpenAIFinishReason("unknown_reason"));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.unknown, map_finish.mapOpenAIFinishReason(null));
}

test "OpenAI reasoning model detection" {
    try std.testing.expect(options_mod.isReasoningModel("o1"));
    try std.testing.expect(options_mod.isReasoningModel("o1-mini"));
    try std.testing.expect(options_mod.isReasoningModel("o1-preview"));
    try std.testing.expect(options_mod.isReasoningModel("o3"));
    try std.testing.expect(options_mod.isReasoningModel("o3-mini"));
    try std.testing.expect(!options_mod.isReasoningModel("gpt-4o"));
    try std.testing.expect(!options_mod.isReasoningModel("gpt-4-turbo"));
    try std.testing.expect(!options_mod.isReasoningModel("gpt-3.5-turbo"));
}

test "OpenAI request serialization - basic" {
    // Use arena allocator since serializeRequest allocates many intermediate objects
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const request = api.OpenAIChatRequest{
        .model = "gpt-4o",
        .messages = &[_]api.OpenAIChatRequest.RequestMessage{
            .{ .role = "user", .content = .{ .text = "Hello" } },
        },
        .max_tokens = 100,
        .temperature = 0.7,
        .stream = false,
    };

    const body = try serializeRequest(allocator, request);

    // Parse back to verify structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});

    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("gpt-4o", obj.get("model").?.string);
    try std.testing.expectEqual(@as(i64, 100), obj.get("max_tokens").?.integer);
    try std.testing.expect(obj.get("messages") != null);
}

test "OpenAI usage conversion" {
    const usage = api.OpenAIChatResponse.Usage{
        .prompt_tokens = 100,
        .completion_tokens = 50,
        .total_tokens = 150,
        .prompt_tokens_details = .{ .cached_tokens = 20 },
        .completion_tokens_details = .{ .reasoning_tokens = 10 },
    };

    const converted = api.convertOpenAIChatUsage(usage);
    try std.testing.expectEqual(@as(u64, 100), converted.input_tokens.total.?);
    try std.testing.expectEqual(@as(u64, 50), converted.output_tokens.total.?);
}

test "OpenAI streaming chunk parsing" {
    const allocator = std.testing.allocator;
    const chunk_json =
        \\{"id":"chatcmpl-123","object":"chat.completion.chunk","created":1677652288,"model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"},"finish_reason":null}]}
    ;

    const parsed = try std.json.parseFromSlice(api.OpenAIChatChunk, allocator, chunk_json, .{});
    defer parsed.deinit();
    const chunk = parsed.value;

    try std.testing.expectEqualStrings("chatcmpl-123", chunk.id.?);
    try std.testing.expectEqual(@as(usize, 1), chunk.choices.len);
    try std.testing.expectEqualStrings("Hello", chunk.choices[0].delta.content.?);
    try std.testing.expect(chunk.choices[0].finish_reason == null);
}
