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
            callback(context, .{ .failure = err });
            return;
        };

        callback(context, .{ .success = result });
    }

    fn doGenerateInternal(
        self: *const Self,
        request_allocator: std.mem.Allocator,
        result_allocator: std.mem.Allocator,
        call_options: lm.LanguageModelV3CallOptions,
    ) !GenerateResultOk {
        var all_warnings = std.array_list.Managed(shared.SharedV3Warning).init(request_allocator);

        // Check for unsupported features
        if (call_options.top_k != null) {
            try all_warnings.append(shared.SharedV3Warning.unsupportedFeature("topK", null));
        }

        // Determine system message mode
        const is_reasoning = options_mod.isReasoningModel(self.model_id);
        const system_mode: convert.ConvertOptions.SystemMessageMode = if (is_reasoning) .developer else .system;

        // Convert messages
        const convert_result = try convert.convertToOpenAIChatMessages(request_allocator, .{
            .prompt = call_options.prompt,
            .system_message_mode = system_mode,
        });
        try all_warnings.appendSlice(convert_result.warnings);

        // Prepare tools
        const tools_result = try prepare_tools.prepareChatTools(request_allocator, .{
            .tools = call_options.tools,
            .tool_choice = call_options.tool_choice,
        });
        try all_warnings.appendSlice(tools_result.tool_warnings);

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
                try all_warnings.append(shared.SharedV3Warning.unsupportedFeature("temperature", "temperature is not supported for reasoning models"));
            }
            if (request.top_p != null) {
                request.top_p = null;
                try all_warnings.append(shared.SharedV3Warning.unsupportedFeature("topP", "topP is not supported for reasoning models"));
            }
            if (request.frequency_penalty != null) {
                request.frequency_penalty = null;
                try all_warnings.append(shared.SharedV3Warning.unsupportedFeature("frequencyPenalty", "frequencyPenalty is not supported for reasoning models"));
            }
            if (request.presence_penalty != null) {
                request.presence_penalty = null;
                try all_warnings.append(shared.SharedV3Warning.unsupportedFeature("presencePenalty", "presencePenalty is not supported for reasoning models"));
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
        var headers = self.config.getHeaders(request_allocator);
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

        http_client.post(url, headers, body, request_allocator, struct {
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
        var content = std.array_list.Managed(lm.LanguageModelV3Content).init(result_allocator);

        if (response.choices.len > 0) {
            const choice = response.choices[0];

            // Add text content
            if (choice.message.content) |text| {
                if (text.len > 0) {
                    const text_copy = try result_allocator.dupe(u8, text);
                    try content.append(.{
                        .text = .{
                            .text = text_copy,
                        },
                    });
                }
            }

            // Add tool calls
            if (choice.message.tool_calls) |tool_calls| {
                for (tool_calls) |tc| {
                    try content.append(.{
                        .tool_call = .{
                            .tool_call_id = try result_allocator.dupe(u8, tc.id orelse ""),
                            .tool_name = try result_allocator.dupe(u8, tc.function.name),
                            .input = json_value.JsonValue.parse(result_allocator, tc.function.arguments orelse "{}") catch .{ .object = json_value.JsonObject.init(result_allocator) },
                        },
                    });
                }
            }

            // Add annotations/sources
            if (choice.message.annotations) |annotations| {
                for (annotations) |ann| {
                    try content.append(.{
                        .source = .{
                            .source_type = .url,
                            .id = try provider_utils.generateId(result_allocator),
                            .url = try result_allocator.dupe(u8, ann.url_citation.url),
                            .title = if (ann.url_citation.title) |t| try result_allocator.dupe(u8, t) else null,
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
            .content = try content.toOwnedSlice(),
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
        callbacks: provider_utils.StreamCallbacks(lm.LanguageModelV3StreamPart),
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        self.doStreamInternal(request_allocator, result_allocator, call_options, callbacks) catch |err| {
            callbacks.on_error(err, callbacks.context);
        };
    }

    fn doStreamInternal(
        self: *const Self,
        request_allocator: std.mem.Allocator,
        result_allocator: std.mem.Allocator,
        call_options: lm.LanguageModelV3CallOptions,
        callbacks: provider_utils.StreamCallbacks(lm.LanguageModelV3StreamPart),
    ) !void {
        var all_warnings = std.array_list.Managed(shared.SharedV3Warning).init(request_allocator);

        // Check for unsupported features
        if (call_options.top_k != null) {
            try all_warnings.append(shared.SharedV3Warning.unsupportedFeature("topK", null));
        }

        // Determine system message mode
        const is_reasoning = options_mod.isReasoningModel(self.model_id);
        const system_mode: convert.ConvertOptions.SystemMessageMode = if (is_reasoning) .developer else .system;

        // Convert messages
        const convert_result = try convert.convertToOpenAIChatMessages(request_allocator, .{
            .prompt = call_options.prompt,
            .system_message_mode = system_mode,
        });
        try all_warnings.appendSlice(convert_result.warnings);

        // Prepare tools
        const tools_result = try prepare_tools.prepareChatTools(request_allocator, .{
            .tools = call_options.tools,
            .tool_choice = call_options.tool_choice,
        });
        try all_warnings.appendSlice(tools_result.tool_warnings);

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
        callbacks.on_part(.{ .stream_start = .{ .warnings = warnings_copy } }, callbacks.context);

        // Build URL
        const url = try self.config.buildUrl(request_allocator, "/chat/completions", self.model_id);

        // Get headers
        var headers = self.config.getHeaders(request_allocator);
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
            .tool_calls = std.array_list.Managed(ToolCallState).init(request_allocator),
            .is_text_active = false,
            .finish_reason = .unknown,
        };

        // Make the streaming request
        http_client.postStream(url, headers, body, request_allocator, struct {
            fn onChunk(ctx: *anyopaque, chunk: []const u8) void {
                const state = @as(*StreamState, @ptrCast(@alignCast(ctx)));
                state.processChunk(chunk) catch |err| {
                    state.callbacks.on_error(err, state.callbacks.context);
                };
            }
            fn onComplete(ctx: *anyopaque) void {
                const state = @as(*StreamState, @ptrCast(@alignCast(ctx)));
                state.finish();
            }
            fn onError(ctx: *anyopaque, err: anyerror) void {
                const state = @as(*StreamState, @ptrCast(@alignCast(ctx)));
                state.callbacks.on_error(err, state.callbacks.context);
            }
        }.onChunk, struct {
            fn onComplete(ctx: *anyopaque) void {
                const state = @as(*StreamState, @ptrCast(@alignCast(ctx)));
                state.finish();
            }
        }.onComplete, struct {
            fn onError(ctx: *anyopaque, err: anyerror) void {
                const state = @as(*StreamState, @ptrCast(@alignCast(ctx)));
                state.callbacks.on_error(err, state.callbacks.context);
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
    callbacks: provider_utils.StreamCallbacks(lm.LanguageModelV3StreamPart),
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

                const parsed = std.json.parseFromSlice(api.OpenAIChatChunk, self.result_allocator, json_data, .{}) catch continue;
                const chunk = parsed.value;

                // Handle error chunks
                if (chunk.@"error") |err| {
                    self.finish_reason = .@"error";
                    self.callbacks.on_part(.{
                        .@"error" = .{
                            .error_value = .{
                                .message = err.message,
                            },
                        },
                    }, self.callbacks.context);
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
                        self.callbacks.on_part(.{
                            .text_start = .{ .id = "0" },
                        }, self.callbacks.context);
                        self.is_text_active = true;
                    }

                    self.callbacks.on_part(.{
                        .text_delta = .{
                            .id = "0",
                            .delta = content,
                        },
                    }, self.callbacks.context);
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
                        self.callbacks.on_part(.{
                            .source = .{
                                .source_type = .url,
                                .id = try provider_utils.generateId(self.result_allocator),
                                .url = ann.url_citation.url,
                                .title = ann.url_citation.title,
                            },
                        }, self.callbacks.context);
                    }
                }
            }
        }
    }

    fn processToolCallDelta(self: *StreamState, tc: api.OpenAIChatChunk.DeltaToolCall) !void {
        const index = tc.index;

        // Ensure we have enough tool call slots
        while (self.tool_calls.items.len <= index) {
            try self.tool_calls.append(.{
                .id = "",
                .name = "",
                .arguments = std.array_list.Managed(u8).init(self.result_allocator),
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
                self.callbacks.on_part(.{
                    .tool_input_start = .{
                        .id = tool_call.id,
                        .tool_name = tool_call.name,
                    },
                }, self.callbacks.context);
            }

            if (func.arguments) |args| {
                try tool_call.arguments.appendSlice(args);

                // Emit tool input delta
                self.callbacks.on_part(.{
                    .tool_input_delta = .{
                        .id = tool_call.id,
                        .delta = args,
                    },
                }, self.callbacks.context);

                // Check if complete (valid JSON)
                if (!tool_call.has_finished) {
                    if (isValidJson(tool_call.arguments.items)) {
                        tool_call.has_finished = true;

                        // Emit tool input end
                        self.callbacks.on_part(.{
                            .tool_input_end = .{ .id = tool_call.id },
                        }, self.callbacks.context);

                        // Emit tool call
                        self.callbacks.on_part(.{
                            .tool_call = .{
                                .tool_call_id = tool_call.id,
                                .tool_name = tool_call.name,
                                .input = json_value.JsonValue.parse(self.result_allocator, tool_call.arguments.items) catch .{ .object = json_value.JsonObject.init(self.result_allocator) },
                            },
                        }, self.callbacks.context);
                    }
                }
            }
        }
    }

    fn finish(self: *StreamState) void {
        // End text if active
        if (self.is_text_active) {
            self.callbacks.on_part(.{
                .text_end = .{ .id = "0" },
            }, self.callbacks.context);
        }

        // Emit finish
        self.callbacks.on_part(.{
            .finish = .{
                .finish_reason = self.finish_reason,
                .usage = self.usage orelse lm.LanguageModelV3Usage.init(),
            },
        }, self.callbacks.context);

        // Call complete callback
        self.callbacks.on_complete(self.callbacks.context);
    }
};

/// Check if a string is valid JSON
fn isValidJson(data: []const u8) bool {
    _ = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, data, .{}) catch return false;
    return true;
}

/// Serialize request to JSON
fn serializeRequest(allocator: std.mem.Allocator, request: api.OpenAIChatRequest) ![]const u8 {
    var buffer = std.array_list.Managed(u8).init(allocator);
    try std.json.stringify(request, .{}, buffer.writer());
    return buffer.toOwnedSlice();
}

test "OpenAIChatLanguageModel basic" {
    const allocator = std.testing.allocator;

    const config = config_mod.OpenAIConfig{
        .provider = "openai.chat",
        .base_url = "https://api.openai.com/v1",
        .headers_fn = struct {
            fn getHeaders(_: *const config_mod.OpenAIConfig) std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(std.testing.allocator);
            }
        }.getHeaders,
    };

    const model = OpenAIChatLanguageModel.init(allocator, "gpt-4o", config);
    try std.testing.expectEqualStrings("openai.chat", model.getProvider());
    try std.testing.expectEqualStrings("gpt-4o", model.getModelId());
}
