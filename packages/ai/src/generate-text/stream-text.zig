const std = @import("std");
const generate_text = @import("generate-text.zig");
const provider_types = @import("provider");

const LanguageModelV3 = provider_types.LanguageModelV3;
const FinishReason = generate_text.FinishReason;
const LanguageModelUsage = generate_text.LanguageModelUsage;
const ToolCall = generate_text.ToolCall;
const ToolResult = generate_text.ToolResult;
const ContentPart = generate_text.ContentPart;
const ResponseMetadata = generate_text.ResponseMetadata;
const StepResult = generate_text.StepResult;
const CallSettings = generate_text.CallSettings;
const Message = generate_text.Message;
const ToolDefinition = generate_text.ToolDefinition;
const ToolChoice = generate_text.ToolChoice;

/// Stream part types emitted during streaming
pub const StreamPart = union(enum) {
    /// Text delta
    text_delta: TextDelta,

    /// Reasoning delta
    reasoning_delta: ReasoningDelta,

    /// Tool call start
    tool_call_start: ToolCallStart,

    /// Tool call delta (streaming arguments)
    tool_call_delta: ToolCallDelta,

    /// Tool call complete
    tool_call_complete: ToolCall,

    /// Tool result
    tool_result: ToolResult,

    /// Step finished
    step_finish: StepFinish,

    /// Stream finished
    finish: StreamFinish,

    /// Error occurred
    @"error": StreamError,
};

pub const TextDelta = struct {
    text: []const u8,
};

pub const ReasoningDelta = struct {
    text: []const u8,
};

pub const ToolCallStart = struct {
    tool_call_id: []const u8,
    tool_name: []const u8,
};

pub const ToolCallDelta = struct {
    tool_call_id: []const u8,
    args_delta: []const u8,
};

pub const StepFinish = struct {
    finish_reason: FinishReason,
    usage: LanguageModelUsage,
    step_type: StepType,
};

pub const StepType = enum {
    initial,
    tool_result,
    @"continue",
};

pub const StreamFinish = struct {
    finish_reason: FinishReason,
    usage: LanguageModelUsage,
    total_usage: LanguageModelUsage,
};

pub const StreamError = struct {
    message: []const u8,
    code: ?[]const u8 = null,
};

/// Callbacks for streaming text generation
pub const StreamCallbacks = struct {
    /// Called for each stream part
    on_part: *const fn (part: StreamPart, context: ?*anyopaque) void,

    /// Called when an error occurs
    on_error: *const fn (err: anyerror, context: ?*anyopaque) void,

    /// Called when streaming completes
    on_complete: *const fn (context: ?*anyopaque) void,

    /// User context passed to callbacks
    context: ?*anyopaque = null,
};

/// Options for streamText
pub const StreamTextOptions = struct {
    /// The language model to use
    model: *LanguageModelV3,

    /// System prompt
    system: ?[]const u8 = null,

    /// Simple text prompt (use this OR messages, not both)
    prompt: ?[]const u8 = null,

    /// Conversation messages (use this OR prompt, not both)
    messages: ?[]const Message = null,

    /// Available tools
    tools: ?[]const ToolDefinition = null,

    /// Tool choice strategy
    tool_choice: ToolChoice = .auto,

    /// Call settings
    settings: CallSettings = .{},

    /// Maximum number of steps for tool use loops
    max_steps: u32 = 1,

    /// Maximum retries on failure
    max_retries: u32 = 2,

    /// Context passed to tool execution
    context: ?*anyopaque = null,

    /// Stream callbacks
    callbacks: StreamCallbacks,

    /// Request context for timeout/cancellation
    request_context: ?*const @import("../context.zig").RequestContext = null,

    /// Retry policy for automatic retries
    retry_policy: ?@import("../retry.zig").RetryPolicy = null,
};

/// Result handle for streaming text generation
pub const StreamTextResult = struct {
    allocator: std.mem.Allocator,
    options: StreamTextOptions,

    /// The accumulated text so far
    text: std.array_list.Managed(u8),

    /// The accumulated reasoning text
    reasoning_text: std.array_list.Managed(u8),

    /// Tool calls collected
    tool_calls: std.array_list.Managed(ToolCall),

    /// Tool results collected
    tool_results: std.array_list.Managed(ToolResult),

    /// Steps completed
    steps: std.array_list.Managed(StepResult),

    /// Current finish reason
    finish_reason: ?FinishReason = null,

    /// Current usage
    usage: LanguageModelUsage = .{},

    /// Total usage across all steps
    total_usage: LanguageModelUsage = .{},

    /// Response metadata
    response: ?ResponseMetadata = null,

    /// Whether streaming is complete
    is_complete: bool = false,

    pub fn init(allocator: std.mem.Allocator, options: StreamTextOptions) StreamTextResult {
        return .{
            .allocator = allocator,
            .options = options,
            .text = std.array_list.Managed(u8).init(allocator),
            .reasoning_text = std.array_list.Managed(u8).init(allocator),
            .tool_calls = std.array_list.Managed(ToolCall).init(allocator),
            .tool_results = std.array_list.Managed(ToolResult).init(allocator),
            .steps = std.array_list.Managed(StepResult).init(allocator),
        };
    }

    pub fn deinit(self: *StreamTextResult) void {
        self.text.deinit();
        self.reasoning_text.deinit();
        self.tool_calls.deinit();
        self.tool_results.deinit();
        self.steps.deinit();
    }

    /// Get the accumulated text
    pub fn getText(self: *const StreamTextResult) []const u8 {
        return self.text.items;
    }

    /// Get the accumulated reasoning text
    pub fn getReasoningText(self: *const StreamTextResult) ?[]const u8 {
        if (self.reasoning_text.items.len == 0) return null;
        return self.reasoning_text.items;
    }

    /// Check if streaming completed normally
    pub fn isStreamComplete(self: *const StreamTextResult) bool {
        if (self.finish_reason) |reason| {
            return reason == .stop or reason == .tool_calls;
        }
        return false;
    }

    /// Get total token count (input + output)
    pub fn totalTokens(self: *const StreamTextResult) u64 {
        return (self.total_usage.input_tokens orelse 0) +
            (self.total_usage.output_tokens orelse 0);
    }

    /// Check if there are any tool calls
    pub fn hasToolCalls(self: *const StreamTextResult) bool {
        return self.tool_calls.items.len > 0;
    }

    /// Process a stream part (internal use)
    pub fn processPart(self: *StreamTextResult, part: StreamPart) !void {
        switch (part) {
            .text_delta => |delta| {
                try self.text.appendSlice(delta.text);
            },
            .reasoning_delta => |delta| {
                try self.reasoning_text.appendSlice(delta.text);
            },
            .tool_call_complete => |tool_call| {
                try self.tool_calls.append(tool_call);
            },
            .tool_result => |result| {
                try self.tool_results.append(result);
            },
            .step_finish => |step| {
                self.usage = step.usage;
                self.total_usage = self.total_usage.add(step.usage);
            },
            .finish => |finish| {
                self.finish_reason = finish.finish_reason;
                self.usage = finish.usage;
                self.total_usage = finish.total_usage;
                self.is_complete = true;
            },
            else => {},
        }
    }
};

/// Error types for stream text
pub const StreamTextError = error{
    ModelError,
    NetworkError,
    InvalidPrompt,
    ToolExecutionError,
    MaxStepsExceeded,
    Cancelled,
    OutOfMemory,
};

/// Stream text generation using a language model
/// This function is non-blocking and uses callbacks for streaming
pub fn streamText(
    allocator: std.mem.Allocator,
    options: StreamTextOptions,
) StreamTextError!*StreamTextResult {
    // Validate options
    if (options.prompt == null and options.messages == null) {
        return StreamTextError.InvalidPrompt;
    }
    if (options.prompt != null and options.messages != null) {
        return StreamTextError.InvalidPrompt;
    }

    // Check request context for cancellation/timeout
    if (options.request_context) |ctx| {
        if (ctx.isDone()) return StreamTextError.Cancelled;
    }

    // Create result handle
    const result = allocator.create(StreamTextResult) catch return StreamTextError.OutOfMemory;
    errdefer {
        result.deinit();
        allocator.destroy(result);
    }
    result.* = StreamTextResult.init(allocator, options);

    // Build prompt using arena for temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var messages_list = std.array_list.Managed(Message).init(arena_allocator);
    if (options.system) |sys| {
        messages_list.append(.{ .role = .system, .content = .{ .text = sys } }) catch return StreamTextError.OutOfMemory;
    }
    if (options.prompt) |p| {
        messages_list.append(.{ .role = .user, .content = .{ .text = p } }) catch return StreamTextError.OutOfMemory;
    } else if (options.messages) |msgs| {
        for (msgs) |msg| {
            messages_list.append(msg) catch return StreamTextError.OutOfMemory;
        }
    }

    // Convert to provider-level prompt
    var prompt_msgs = std.array_list.Managed(provider_types.LanguageModelV3Message).init(arena_allocator);
    for (messages_list.items) |msg| {
        switch (msg.content) {
            .text => |text| {
                switch (msg.role) {
                    .system => {
                        prompt_msgs.append(provider_types.language_model.systemMessage(text)) catch return StreamTextError.OutOfMemory;
                    },
                    .user => {
                        const m = provider_types.language_model.userTextMessage(arena_allocator, text) catch return StreamTextError.OutOfMemory;
                        prompt_msgs.append(m) catch return StreamTextError.OutOfMemory;
                    },
                    .assistant => {
                        const m = provider_types.language_model.assistantTextMessage(arena_allocator, text) catch return StreamTextError.OutOfMemory;
                        prompt_msgs.append(m) catch return StreamTextError.OutOfMemory;
                    },
                    .tool => {},
                }
            },
            .parts => {},
        }
    }

    // Build call options
    const call_options = provider_types.LanguageModelV3CallOptions{
        .prompt = prompt_msgs.items,
        .max_output_tokens = options.settings.max_output_tokens,
        .temperature = if (options.settings.temperature) |t| @as(f32, @floatCast(t)) else null,
        .stop_sequences = options.settings.stop_sequences,
        .top_p = if (options.settings.top_p) |p| @as(f32, @floatCast(p)) else null,
        .top_k = options.settings.top_k,
        .presence_penalty = if (options.settings.presence_penalty) |p| @as(f32, @floatCast(p)) else null,
        .frequency_penalty = if (options.settings.frequency_penalty) |f| @as(f32, @floatCast(f)) else null,
        .seed = if (options.settings.seed) |s| @as(i64, @intCast(s)) else null,
    };

    // Bridge: translate provider-level stream parts to ai-level
    const BridgeCtx = struct {
        res: *StreamTextResult,
        cbs: StreamCallbacks,

        fn onPart(ctx_ptr: ?*anyopaque, part: provider_types.LanguageModelV3StreamPart) void {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr.?));
            const ai_part = translatePart(part) orelse return;
            self.res.processPart(ai_part) catch |err| {
                self.cbs.on_error(err, self.cbs.context);
                return;
            };
            self.cbs.on_part(ai_part, self.cbs.context);
        }

        fn onError(ctx_ptr: ?*anyopaque, err: anyerror) void {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr.?));
            self.cbs.on_error(err, self.cbs.context);
        }

        fn onComplete(ctx_ptr: ?*anyopaque, _: ?LanguageModelV3.StreamCompleteInfo) void {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr.?));
            self.cbs.on_complete(self.cbs.context);
        }

        fn translatePart(part: provider_types.LanguageModelV3StreamPart) ?StreamPart {
            return switch (part) {
                .text_delta => |d| .{ .text_delta = .{ .text = d.delta } },
                .reasoning_delta => |d| .{ .reasoning_delta = .{ .text = d.delta } },
                .finish => |f| .{ .finish = .{
                    .finish_reason = mapFinishReason(f.finish_reason),
                    .usage = mapUsage(f.usage),
                    .total_usage = mapUsage(f.usage),
                } },
                .@"error" => |e| .{ .@"error" = .{
                    .message = e.message orelse "Unknown error",
                } },
                else => null,
            };
        }

        fn mapFinishReason(fr: provider_types.LanguageModelV3FinishReason) FinishReason {
            return switch (fr) {
                .stop => .stop,
                .length => .length,
                .tool_calls => .tool_calls,
                .content_filter => .content_filter,
                .@"error" => .other,
                .other => .other,
                .unknown => .unknown,
            };
        }

        fn mapUsage(u: provider_types.LanguageModelV3Usage) LanguageModelUsage {
            return .{
                .input_tokens = u.input_tokens.total,
                .output_tokens = u.output_tokens.total,
            };
        }
    };

    var bridge = BridgeCtx{ .res = result, .cbs = options.callbacks };
    const bridge_ptr: *anyopaque = @ptrCast(&bridge);

    // Call model's doStream
    options.model.doStream(call_options, allocator, .{
        .on_part = BridgeCtx.onPart,
        .on_error = BridgeCtx.onError,
        .on_complete = BridgeCtx.onComplete,
        .ctx = bridge_ptr,
    });

    return result;
}

/// Helper to convert streaming result to non-streaming result
pub fn toGenerateTextResult(stream_result: *StreamTextResult) generate_text.GenerateTextResult {
    return .{
        .text = stream_result.getText(),
        .reasoning_text = stream_result.getReasoningText(),
        .content = &[_]ContentPart{},
        .tool_calls = stream_result.tool_calls.items,
        .tool_results = stream_result.tool_results.items,
        .finish_reason = stream_result.finish_reason orelse .stop,
        .usage = stream_result.usage,
        .total_usage = stream_result.total_usage,
        .response = stream_result.response orelse .{
            .id = "",
            .model_id = "",
            .timestamp = 0,
        },
        .steps = stream_result.steps.items,
        .warnings = null,
    };
}

test "StreamTextResult init and deinit" {
    const allocator = std.testing.allocator;
    const callbacks = StreamCallbacks{
        .on_part = struct {
            fn f(_: StreamPart, _: ?*anyopaque) void {}
        }.f,
        .on_error = struct {
            fn f(_: anyerror, _: ?*anyopaque) void {}
        }.f,
        .on_complete = struct {
            fn f(_: ?*anyopaque) void {}
        }.f,
    };

    const model: LanguageModelV3 = undefined;
    var result = StreamTextResult.init(allocator, .{
        .model = @constCast(&model),
        .prompt = "Hello",
        .callbacks = callbacks,
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.text.items.len);
}

test "streamText delivers chunks from mock provider" {
    const allocator = std.testing.allocator;

    const MockModel = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-model";
        }

        pub fn getSupportedUrls(
            _: *const Self,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.SupportedUrlsResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.Unsupported });
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.NotImplemented });
        }

        pub fn doStream(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callbacks: LanguageModelV3.StreamCallbacks,
        ) void {
            // Emit text deltas
            callbacks.on_part(callbacks.ctx, provider_types.language_model.textDelta("t1", "Hello"));
            callbacks.on_part(callbacks.ctx, provider_types.language_model.textDelta("t1", " World"));
            // Emit finish
            callbacks.on_part(callbacks.ctx, provider_types.language_model.finish(
                provider_types.LanguageModelV3Usage.initWithTotals(5, 10),
                .stop,
            ));
            callbacks.on_complete(callbacks.ctx, null);
        }
    };

    var mock = MockModel{};
    var model = provider_types.asLanguageModel(MockModel, &mock);

    // Track received text via ai-level callbacks
    const TestCtx = struct {
        text_buf: std.array_list.Managed(u8),

        fn onPart(part: StreamPart, ctx_raw: ?*anyopaque) void {
            if (ctx_raw) |p| {
                const self: *@This() = @ptrCast(@alignCast(p));
                switch (part) {
                    .text_delta => |d| {
                        self.text_buf.appendSlice(d.text) catch @panic("OOM in test");
                    },
                    else => {},
                }
            }
        }

        fn onError(_: anyerror, _: ?*anyopaque) void {}
        fn onComplete(_: ?*anyopaque) void {}
    };

    var test_ctx = TestCtx{ .text_buf = std.array_list.Managed(u8).init(allocator) };
    defer test_ctx.text_buf.deinit();

    const ctx_ptr: *anyopaque = @ptrCast(&test_ctx);
    const result = try streamText(allocator, .{
        .model = &model,
        .prompt = "Say hello",
        .callbacks = .{
            .on_part = TestCtx.onPart,
            .on_error = TestCtx.onError,
            .on_complete = TestCtx.onComplete,
            .context = ctx_ptr,
        },
    });
    defer {
        result.deinit();
        allocator.destroy(result);
    }

    // The streaming should have delivered "Hello World" via the model's doStream
    try std.testing.expectEqualStrings("Hello World", result.getText());
}

test "StreamTextResult process text delta" {
    const allocator = std.testing.allocator;
    const callbacks = StreamCallbacks{
        .on_part = struct {
            fn f(_: StreamPart, _: ?*anyopaque) void {}
        }.f,
        .on_error = struct {
            fn f(_: anyerror, _: ?*anyopaque) void {}
        }.f,
        .on_complete = struct {
            fn f(_: ?*anyopaque) void {}
        }.f,
    };

    const model: LanguageModelV3 = undefined;
    var result = StreamTextResult.init(allocator, .{
        .model = @constCast(&model),
        .prompt = "Hello",
        .callbacks = callbacks,
    });
    defer result.deinit();

    try result.processPart(.{ .text_delta = .{ .text = "Hello" } });
    try result.processPart(.{ .text_delta = .{ .text = " World" } });

    try std.testing.expectEqualStrings("Hello World", result.getText());
}

test "streamText calls error callback on model failure" {
    const MockFailStreamModel = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-fail-stream";
        }

        pub fn getSupportedUrls(
            _: *const Self,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.SupportedUrlsResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.Unsupported });
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.ModelError });
        }

        pub fn doStream(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callbacks: LanguageModelV3.StreamCallbacks,
        ) void {
            // Simulate error during streaming
            callbacks.on_error(callbacks.ctx, error.HttpRequestFailed);
        }
    };

    const TestCtx = struct {
        error_received: bool = false,
        complete_received: bool = false,

        fn onPart(_: StreamPart, _: ?*anyopaque) void {}
        fn onError(_: anyerror, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.error_received = true;
        }
        fn onComplete(ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.complete_received = true;
        }
    };

    var test_ctx = TestCtx{};

    var mock = MockFailStreamModel{};
    var model = provider_types.asLanguageModel(MockFailStreamModel, &mock);

    const result = try streamText(std.testing.allocator, .{
        .model = &model,
        .prompt = "This should fail during streaming",
        .callbacks = .{
            .on_part = TestCtx.onPart,
            .on_error = TestCtx.onError,
            .on_complete = TestCtx.onComplete,
            .context = @ptrCast(&test_ctx),
        },
    });
    defer {
        result.deinit();
        std.testing.allocator.destroy(result);
    }

    try std.testing.expect(test_ctx.error_received);
}

test "streamText with empty prompt returns error" {
    const MockModel3 = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getSupportedUrls(
            _: *const Self,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.SupportedUrlsResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.Unsupported });
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.ModelError });
        }

        pub fn doStream(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callbacks: LanguageModelV3.StreamCallbacks,
        ) void {
            callbacks.on_complete(callbacks.ctx, null);
        }
    };

    var mock = MockModel3{};
    var model = provider_types.asLanguageModel(MockModel3, &mock);

    const callbacks = StreamCallbacks{
        .on_part = struct {
            fn f(_: StreamPart, _: ?*anyopaque) void {}
        }.f,
        .on_error = struct {
            fn f(_: anyerror, _: ?*anyopaque) void {}
        }.f,
        .on_complete = struct {
            fn f(_: ?*anyopaque) void {}
        }.f,
    };

    // Neither prompt nor messages provided
    const result = streamText(std.testing.allocator, .{
        .model = &model,
        .callbacks = callbacks,
    });

    try std.testing.expectError(StreamTextError.InvalidPrompt, result);
}

test "streamText many chunks don't leak memory" {
    const MockManyChunksModel = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-chunks";
        }

        pub fn getSupportedUrls(
            _: *const Self,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.SupportedUrlsResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.Unsupported });
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.ModelError });
        }

        pub fn doStream(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callbacks: LanguageModelV3.StreamCallbacks,
        ) void {
            // Emit 100 text delta chunks
            callbacks.on_part(callbacks.ctx, .{ .text_start = .{ .id = "text-0" } });
            var i: u32 = 0;
            while (i < 100) : (i += 1) {
                callbacks.on_part(callbacks.ctx, .{ .text_delta = .{ .id = "text-0", .delta = "chunk " } });
            }
            callbacks.on_part(callbacks.ctx, .{ .text_end = .{ .id = "text-0" } });
            callbacks.on_part(callbacks.ctx, .{
                .finish = .{
                    .finish_reason = .stop,
                    .usage = provider_types.LanguageModelV3Usage.initWithTotals(10, 100),
                },
            });
            callbacks.on_complete(callbacks.ctx, null);
        }
    };

    const TestCtx = struct {
        chunk_count: u32 = 0,
        completed: bool = false,

        fn onPart(_: StreamPart, context: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.chunk_count += 1;
        }

        fn onError(_: anyerror, _: ?*anyopaque) void {}

        fn onComplete(context: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.completed = true;
        }
    };

    var test_ctx = TestCtx{};

    var mock = MockManyChunksModel{};
    var model = provider_types.asLanguageModel(MockManyChunksModel, &mock);

    const result = try streamText(std.testing.allocator, .{
        .model = &model,
        .prompt = "Generate a long response",
        .callbacks = .{
            .on_part = TestCtx.onPart,
            .on_error = TestCtx.onError,
            .on_complete = TestCtx.onComplete,
            .context = @ptrCast(&test_ctx),
        },
    });
    defer {
        result.deinit();
        std.testing.allocator.destroy(result);
    }

    try std.testing.expect(test_ctx.completed);
    // translatePart skips text_start and text_end (returns null)
    // Only 100 text_deltas + 1 finish = 101 parts reach the callback
    try std.testing.expectEqual(@as(u32, 101), test_ctx.chunk_count);
}
