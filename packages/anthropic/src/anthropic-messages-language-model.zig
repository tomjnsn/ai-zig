const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");
const json_value = @import("provider").json_value;

const api = @import("anthropic-messages-api.zig");
const options_mod = @import("anthropic-messages-options.zig");
const convert = @import("convert-to-anthropic-messages-prompt.zig");
const prepare_tools = @import("anthropic-prepare-tools.zig");
const map_stop = @import("map-anthropic-stop-reason.zig");
const config_mod = @import("anthropic-config.zig");
const error_mod = @import("anthropic-error.zig");

/// Anthropic Messages Language Model implementation
pub const AnthropicMessagesLanguageModel = struct {
    const Self = @This();

    /// Model ID
    model_id: []const u8,

    /// Configuration
    config: config_mod.AnthropicConfig,

    /// Allocator for internal operations
    allocator: std.mem.Allocator,

    pub const specification_version = "v3";

    /// Initialize a new Anthropic messages language model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.AnthropicConfig,
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
        var all_warnings = std.ArrayList(shared.SharedV3Warning).empty;
        var all_betas = std.StringHashMap(void).init(request_allocator);

        // Check for unsupported features
        if (call_options.frequency_penalty != null) {
            try all_warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature("frequencyPenalty", null));
        }

        if (call_options.presence_penalty != null) {
            try all_warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature("presencePenalty", null));
        }

        if (call_options.seed != null) {
            try all_warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature("seed", null));
        }

        // Clamp temperature
        var temperature = call_options.temperature;
        if (temperature) |t| {
            if (t > 1.0) {
                temperature = 1.0;
                try all_warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature("temperature", "Temperature exceeds anthropic maximum of 1.0, clamped to 1.0"));
            } else if (t < 0.0) {
                temperature = 0.0;
                try all_warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature("temperature", "Temperature below anthropic minimum of 0, clamped to 0"));
            }
        }

        // Get model capabilities
        const capabilities = options_mod.getModelCapabilities(self.model_id);

        // Determine max tokens
        const max_tokens = call_options.max_output_tokens orelse capabilities.max_output_tokens;

        // Convert messages
        var convert_result = try convert.convertToAnthropicMessagesPrompt(request_allocator, .{
            .prompt = call_options.prompt,
            .send_reasoning = true,
        });
        try all_warnings.appendSlice(request_allocator, convert_result.warnings);

        // Merge betas from message conversion
        var beta_iter = convert_result.betas.iterator();
        while (beta_iter.next()) |entry| {
            try all_betas.put(entry.key_ptr.*, {});
        }

        // Prepare tools
        var tools_result = try prepare_tools.prepareTools(request_allocator, .{
            .tools = call_options.tools,
            .tool_choice = call_options.tool_choice,
        });
        try all_warnings.appendSlice(request_allocator, tools_result.tool_warnings);

        // Merge betas from tools
        var tools_beta_iter = tools_result.betas.iterator();
        while (tools_beta_iter.next()) |entry| {
            try all_betas.put(entry.key_ptr.*, {});
        }

        // Build request body
        const request = api.AnthropicMessagesRequest{
            .model = self.model_id,
            .messages = convert_result.messages,
            .max_tokens = max_tokens,
            .system = convert_result.system,
            .temperature = temperature,
            .top_p = call_options.top_p,
            .top_k = call_options.top_k,
            .stop_sequences = call_options.stop_sequences,
            .tools = tools_result.tools,
            .tool_choice = tools_result.tool_choice,
            .stream = false,
        };

        // Build URL
        const url = try self.config.buildUrl(request_allocator, "/messages", self.model_id);

        // Get headers
        var headers = try self.config.getHeaders(request_allocator);

        // Add beta header if needed
        if (all_betas.count() > 0) {
            var beta_list = std.ArrayList(u8).empty;
            var iter = all_betas.iterator();
            var first = true;
            while (iter.next()) |entry| {
                if (!first) {
                    try beta_list.appendSlice(request_allocator, ",");
                }
                try beta_list.appendSlice(request_allocator, entry.key_ptr.*);
                first = false;
            }
            try headers.put("anthropic-beta", try beta_list.toOwnedSlice(request_allocator));
        }

        if (call_options.headers) |user_headers| {
            var hiter = user_headers.iterator();
            while (hiter.next()) |entry| {
                try headers.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Make HTTP request
        const http_client = self.config.http_client orelse return error.NoHttpClient;

        // Serialize request body
        const body = try serializeRequest(request_allocator, request);

        // Make the request
        var call_response: ?provider_utils.HttpResponse = null;

        try http_client.post(url, headers, body, request_allocator,
            struct {
                fn onResponse(ctx: ?*anyopaque, resp: provider_utils.HttpResponse) void {
                    const r: *?provider_utils.HttpResponse = @ptrCast(@alignCast(ctx.?));
                    r.* = resp;
                }
            }.onResponse,
            struct {
                fn onError(_: ?*anyopaque, _: provider_utils.HttpError) void {}
            }.onError,
            @as(?*anyopaque, @ptrCast(&call_response)),
        );

        const http_response = call_response orelse return error.NoResponse;
        if (!http_response.isSuccess()) return error.ApiCallError;
        const response_body = http_response.body;

        // Parse response
        const parsed = std.json.parseFromSlice(api.AnthropicMessagesResponse, request_allocator, response_body, .{}) catch {
            return error.InvalidResponse;
        };
        const response = parsed.value;

        // Extract content
        var content = std.ArrayList(lm.LanguageModelV3Content).empty;

        for (response.content) |block| {
            switch (block) {
                .text => |text| {
                    const text_copy = try result_allocator.dupe(u8, text.text);
                    try content.append(result_allocator, .{
                        .text = .{
                            .text = text_copy,
                        },
                    });
                },
                .thinking => |thinking| {
                    try content.append(result_allocator, .{
                        .reasoning = .{
                            .text = try result_allocator.dupe(u8, thinking.thinking),
                        },
                    });
                },
                .redacted_thinking => |_| {
                    try content.append(result_allocator, .{
                        .reasoning = .{
                            .text = "",
                        },
                    });
                },
                .tool_use => |tc| {
                    try content.append(result_allocator, .{
                        .tool_call = .{
                            .tool_call_id = try result_allocator.dupe(u8, tc.id),
                            .tool_name = try result_allocator.dupe(u8, tc.name),
                            .input = try tc.input.clone(result_allocator),
                        },
                    });
                },
                .server_tool_use => |tc| {
                    try content.append(result_allocator, .{
                        .tool_call = .{
                            .tool_call_id = try result_allocator.dupe(u8, tc.id),
                            .tool_name = try result_allocator.dupe(u8, tc.name),
                            .input = try tc.input.clone(result_allocator),
                        },
                    });
                },
                else => {},
            }
        }

        // Convert usage
        const usage = api.convertAnthropicMessagesUsage(response.usage);

        // Get finish reason
        const finish_reason = map_stop.mapAnthropicStopReason(response.stop_reason, false);

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

        // Check for unsupported features (same as doGenerate)
        if (call_options.frequency_penalty != null) {
            try all_warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature("frequencyPenalty", null));
        }
        if (call_options.presence_penalty != null) {
            try all_warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature("presencePenalty", null));
        }
        if (call_options.seed != null) {
            try all_warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature("seed", null));
        }

        // Clamp temperature
        var temperature = call_options.temperature;
        if (temperature) |t| {
            if (t > 1.0) temperature = 1.0;
            if (t < 0.0) temperature = 0.0;
        }

        // Get model capabilities
        const capabilities = options_mod.getModelCapabilities(self.model_id);
        const max_tokens = call_options.max_output_tokens orelse capabilities.max_output_tokens;

        // Convert messages
        const convert_result = try convert.convertToAnthropicMessagesPrompt(request_allocator, .{
            .prompt = call_options.prompt,
            .send_reasoning = true,
        });
        try all_warnings.appendSlice(request_allocator, convert_result.warnings);

        // Prepare tools
        const tools_result = try prepare_tools.prepareTools(request_allocator, .{
            .tools = call_options.tools,
            .tool_choice = call_options.tool_choice,
        });
        try all_warnings.appendSlice(request_allocator, tools_result.tool_warnings);

        // Emit stream start
        const warnings_copy = try result_allocator.alloc(shared.SharedV3Warning, all_warnings.items.len);
        for (all_warnings.items, 0..) |w, i| {
            warnings_copy[i] = w;
        }
        callbacks.on_part(callbacks.ctx, .{ .stream_start = .{ .warnings = warnings_copy } });

        // Build request body with streaming enabled
        const request = api.AnthropicMessagesRequest{
            .model = self.model_id,
            .messages = convert_result.messages,
            .max_tokens = max_tokens,
            .system = convert_result.system,
            .temperature = temperature,
            .top_p = call_options.top_p,
            .top_k = call_options.top_k,
            .stop_sequences = call_options.stop_sequences,
            .tools = tools_result.tools,
            .tool_choice = tools_result.tool_choice,
            .stream = true,
        };

        // Build URL
        const url = try self.config.buildUrl(request_allocator, "/messages", self.model_id);

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
            .content_blocks = std.AutoHashMap(u32, ContentBlockState).init(request_allocator),
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

    fn getProviderVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getProvider();
    }

    fn getModelIdVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getModelId();
    }

    fn getSupportedUrlsVtable(
        impl: *anyopaque,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, lm.LanguageModelV3.SupportedUrlsResult) void,
        context: ?*anyopaque,
    ) void {
        _ = impl;
        // Anthropic doesn't support URL-based file inputs
        const empty_map = std.StringHashMap([]const []const u8).init(allocator);
        callback(context, .{ .success = empty_map });
    }

    fn doGenerateVtable(
        impl: *anyopaque,
        options: lm.LanguageModelV3CallOptions,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, lm.LanguageModelV3.GenerateResult) void,
        context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doGenerate(options, allocator, callback, context);
    }

    fn doStreamVtable(
        impl: *anyopaque,
        options: lm.LanguageModelV3CallOptions,
        allocator: std.mem.Allocator,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doStream(options, allocator, callbacks);
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

/// State for tracking content blocks during streaming
const ContentBlockState = struct {
    block_type: BlockType,
    tool_call_id: ?[]const u8 = null,
    tool_name: ?[]const u8 = null,
    input: std.ArrayList(u8),

    const BlockType = enum {
        text,
        thinking,
        tool_use,
    };
};

/// State for stream processing
const StreamState = struct {
    callbacks: lm.LanguageModelV3.StreamCallbacks,
    result_allocator: std.mem.Allocator,
    content_blocks: std.AutoHashMap(u32, ContentBlockState),
    finish_reason: lm.LanguageModelV3FinishReason,
    usage: ?lm.LanguageModelV3Usage = null,

    fn processChunk(self: *StreamState, chunk_data: []const u8) !void {
        // Parse SSE chunk (event: type\ndata: {...})
        var lines = std.mem.splitSequence(u8, chunk_data, "\n");
        var event_type: ?[]const u8 = null;

        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "event: ")) {
                event_type = line[7..];
            } else if (std.mem.startsWith(u8, line, "data: ")) {
                const json_data = line[6..];

                const parsed = std.json.parseFromSlice(api.AnthropicMessagesChunk, self.result_allocator, json_data, .{}) catch |err| {
                    // Report JSON parse error to caller but continue processing subsequent chunks
                    self.callbacks.on_part(self.callbacks.ctx, .{
                        .@"error" = .{ .err = err, .message = "Failed to parse SSE chunk JSON" },
                    });
                    continue;
                };
                const chunk = parsed.value;

                try self.processAnthropicChunk(chunk, event_type);
            }
        }
    }

    fn processAnthropicChunk(self: *StreamState, chunk: api.AnthropicMessagesChunk, event_type: ?[]const u8) !void {
        const chunk_type = event_type orelse chunk.type;

        if (std.mem.eql(u8, chunk_type, "message_start")) {
            if (chunk.message) |msg| {
                self.callbacks.on_part(self.callbacks.ctx, .{
                    .response_metadata = .{
                        .id = msg.id,
                        .model_id = msg.model,
                    },
                });
            }
        } else if (std.mem.eql(u8, chunk_type, "content_block_start")) {
            const index = chunk.index orelse return;

            if (chunk.content_block) |block| {
                switch (block) {
                    .text => {
                        try self.content_blocks.put(index, .{
                            .block_type = .text,
                            .input = std.ArrayList(u8).empty,
                        });
                        self.callbacks.on_part(self.callbacks.ctx, .{
                            .text_start = .{ .id = try std.fmt.allocPrint(self.result_allocator, "{d}", .{index}) },
                        });
                    },
                    .thinking => {
                        try self.content_blocks.put(index, .{
                            .block_type = .thinking,
                            .input = std.ArrayList(u8).empty,
                        });
                        self.callbacks.on_part(self.callbacks.ctx, .{
                            .reasoning_start = .{ .id = try std.fmt.allocPrint(self.result_allocator, "{d}", .{index}) },
                        });
                    },
                    .tool_use => |tu| {
                        try self.content_blocks.put(index, .{
                            .block_type = .tool_use,
                            .tool_call_id = tu.id,
                            .tool_name = tu.name,
                            .input = std.ArrayList(u8).empty,
                        });
                        self.callbacks.on_part(self.callbacks.ctx, .{
                            .tool_input_start = .{
                                .id = tu.id,
                                .tool_name = tu.name,
                            },
                        });
                    },
                    else => {},
                }
            }
        } else if (std.mem.eql(u8, chunk_type, "content_block_delta")) {
            const index = chunk.index orelse return;

            if (chunk.delta) |delta| {
                switch (delta) {
                    .text_delta => |td| {
                        self.callbacks.on_part(self.callbacks.ctx, .{
                            .text_delta = .{
                                .id = try std.fmt.allocPrint(self.result_allocator, "{d}", .{index}),
                                .delta = td.text,
                            },
                        });
                    },
                    .thinking_delta => |td| {
                        self.callbacks.on_part(self.callbacks.ctx, .{
                            .reasoning_delta = .{
                                .id = try std.fmt.allocPrint(self.result_allocator, "{d}", .{index}),
                                .delta = td.thinking,
                            },
                        });
                    },
                    .input_json_delta => |jd| {
                        if (self.content_blocks.get(index)) |block| {
                            if (block.block_type == .tool_use) {
                                self.callbacks.on_part(self.callbacks.ctx, .{
                                    .tool_input_delta = .{
                                        .id = block.tool_call_id orelse "",
                                        .delta = jd.partial_json,
                                    },
                                });
                            }
                        }
                    },
                    else => {},
                }
            }
        } else if (std.mem.eql(u8, chunk_type, "content_block_stop")) {
            const index = chunk.index orelse return;

            if (self.content_blocks.get(index)) |block| {
                const id = try std.fmt.allocPrint(self.result_allocator, "{d}", .{index});

                switch (block.block_type) {
                    .text => {
                        self.callbacks.on_part(self.callbacks.ctx, .{ .text_end = .{ .id = id } });
                    },
                    .thinking => {
                        self.callbacks.on_part(self.callbacks.ctx, .{ .reasoning_end = .{ .id = id } });
                    },
                    .tool_use => {
                        self.callbacks.on_part(self.callbacks.ctx, .{
                            .tool_input_end = .{ .id = block.tool_call_id orelse "" },
                        });

                        // Emit tool call
                        self.callbacks.on_part(self.callbacks.ctx, .{
                            .tool_call = .{
                                .tool_call_id = block.tool_call_id orelse "",
                                .tool_name = block.tool_name orelse "",
                                .input = json_value.JsonValue.parse(self.result_allocator, block.input.items) catch .{ .object = json_value.JsonObject.init(self.result_allocator) },
                            },
                        });
                    },
                }

                _ = self.content_blocks.remove(index);
            }
        } else if (std.mem.eql(u8, chunk_type, "message_delta")) {
            if (chunk.delta) |delta| {
                switch (delta) {
                    .message_delta => |md| {
                        self.finish_reason = map_stop.mapAnthropicStopReason(md.stop_reason, false);
                    },
                    else => {},
                }
            }

            if (chunk.usage) |usage| {
                self.usage = .{
                    .input_tokens = .{},
                    .output_tokens = .{ .total = usage.output_tokens },
                };
            }
        } else if (std.mem.eql(u8, chunk_type, "message_stop")) {
            // Message complete
        } else if (std.mem.eql(u8, chunk_type, "error")) {
            if (chunk.@"error") |err| {
                self.finish_reason = .@"error";
                self.callbacks.on_part(self.callbacks.ctx, .{
                    .@"error" = .{
                        .error_value = .{ .message = err.message },
                    },
                });
            }
        }
    }

    fn finish(self: *StreamState) void {
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

/// Serialize request to JSON
fn serializeRequest(allocator: std.mem.Allocator, request: api.AnthropicMessagesRequest) ![]const u8 {
    var buffer = std.ArrayList(u8).empty;
    try std.json.stringify(request, .{}, buffer.writer(allocator));
    return buffer.toOwnedSlice(allocator);
}

test "AnthropicMessagesLanguageModel basic" {
    const allocator = std.testing.allocator;

    const config = config_mod.AnthropicConfig{
        .provider = "anthropic.messages",
        .base_url = "https://api.anthropic.com/v1",
        .headers_fn = struct {
            fn getHeaders(_: *const config_mod.AnthropicConfig, alloc: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(alloc);
            }
        }.getHeaders,
    };

    const model = AnthropicMessagesLanguageModel.init(allocator, "claude-sonnet-4-5", config);
    try std.testing.expectEqualStrings("anthropic.messages", model.getProvider());
    try std.testing.expectEqualStrings("claude-sonnet-4-5", model.getModelId());
}

test "Anthropic API version constant" {
    try std.testing.expectEqualStrings("2024-06-01", config_mod.anthropic_version);
}

test "Anthropic stop reason mapping" {
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.stop, map_stop.mapAnthropicStopReason("end_turn", false));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.stop, map_stop.mapAnthropicStopReason("pause_turn", false));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.tool_calls, map_stop.mapAnthropicStopReason("tool_use", false));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.stop, map_stop.mapAnthropicStopReason("tool_use", true));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.length, map_stop.mapAnthropicStopReason("max_tokens", false));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.content_filter, map_stop.mapAnthropicStopReason("refusal", false));
}

test "Anthropic usage conversion" {
    const usage = api.AnthropicMessagesResponse.Usage{
        .input_tokens = 100,
        .output_tokens = 50,
        .cache_creation_input_tokens = 10,
        .cache_read_input_tokens = 5,
    };

    const converted = api.convertAnthropicMessagesUsage(usage);
    try std.testing.expectEqual(@as(u64, 100), converted.input_tokens.total.?);
    try std.testing.expectEqual(@as(u64, 50), converted.output_tokens.total.?);
}

test "Anthropic config buildUrl" {
    const allocator = std.testing.allocator;

    const config = config_mod.AnthropicConfig{
        .provider = "anthropic.messages",
        .base_url = "https://api.anthropic.com/v1",
        .headers_fn = struct {
            fn getHeaders(_: *const config_mod.AnthropicConfig, alloc: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(alloc);
            }
        }.getHeaders,
    };

    const url = try config.buildUrl(allocator, "/messages", "claude-sonnet-4-5");
    defer allocator.free(url);

    try std.testing.expectEqualStrings("https://api.anthropic.com/v1/messages", url);
}
