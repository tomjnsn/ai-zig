const std = @import("std");
const provider_types = @import("provider");
const LanguageModelV3 = provider_types.LanguageModelV3;

/// Finish reasons for text generation
pub const FinishReason = enum {
    stop,
    length,
    tool_calls,
    content_filter,
    other,
    unknown,
};

/// Token usage information
pub const LanguageModelUsage = struct {
    input_tokens: ?u64 = null,
    output_tokens: ?u64 = null,
    total_tokens: ?u64 = null,
    reasoning_tokens: ?u64 = null,
    cached_input_tokens: ?u64 = null,

    pub fn add(self: LanguageModelUsage, other: LanguageModelUsage) LanguageModelUsage {
        return .{
            .input_tokens = addOptional(self.input_tokens, other.input_tokens),
            .output_tokens = addOptional(self.output_tokens, other.output_tokens),
            .total_tokens = addOptional(self.total_tokens, other.total_tokens),
            .reasoning_tokens = addOptional(self.reasoning_tokens, other.reasoning_tokens),
            .cached_input_tokens = addOptional(self.cached_input_tokens, other.cached_input_tokens),
        };
    }

    fn addOptional(a: ?u64, b: ?u64) ?u64 {
        if (a == null and b == null) return null;
        return (a orelse 0) + (b orelse 0);
    }
};

/// Tool call representation
pub const ToolCall = struct {
    tool_call_id: []const u8,
    tool_name: []const u8,
    input: std.json.Value,
};

/// Tool result representation
pub const ToolResult = struct {
    tool_call_id: []const u8,
    tool_name: []const u8,
    output: std.json.Value,
};

/// Content part types
pub const ContentPart = union(enum) {
    text: TextPart,
    tool_call: ToolCall,
    tool_result: ToolResult,
    reasoning: ReasoningPart,
    file: FilePart,
};

pub const TextPart = struct {
    text: []const u8,
};

pub const ReasoningPart = struct {
    text: []const u8,
    signature: ?[]const u8 = null,
};

pub const FilePart = struct {
    data: []const u8,
    mime_type: []const u8,
};

/// Response metadata
pub const ResponseMetadata = struct {
    id: []const u8,
    model_id: []const u8,
    timestamp: i64,
    headers: ?std.StringHashMap([]const u8) = null,
};

/// Step result for multi-step generation
pub const StepResult = struct {
    content: []const ContentPart,
    text: []const u8,
    reasoning_text: ?[]const u8 = null,
    finish_reason: FinishReason,
    usage: LanguageModelUsage,
    tool_calls: []const ToolCall,
    tool_results: []const ToolResult,
    response: ResponseMetadata,
    warnings: ?[]const []const u8 = null,
};

/// Result of generateText
pub const GenerateTextResult = struct {
    /// The generated text from the last step
    text: []const u8,

    /// Reasoning text if available
    reasoning_text: ?[]const u8 = null,

    /// Content parts from the last step
    content: []const ContentPart,

    /// Tool calls made in the last step
    tool_calls: []const ToolCall,

    /// Tool results from the last step
    tool_results: []const ToolResult,

    /// Reason generation finished
    finish_reason: FinishReason,

    /// Token usage for the last step
    usage: LanguageModelUsage,

    /// Total usage across all steps
    total_usage: LanguageModelUsage,

    /// Response metadata
    response: ResponseMetadata,

    /// All steps in multi-step generation
    steps: []const StepResult,

    /// Warnings from the model
    warnings: ?[]const []const u8 = null,

    /// Clean up resources
    pub fn deinit(self: *GenerateTextResult, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Arena allocator handles cleanup
    }
};

/// Call settings for text generation
pub const CallSettings = struct {
    max_output_tokens: ?u32 = null,
    temperature: ?f64 = null,
    top_p: ?f64 = null,
    top_k: ?u32 = null,
    presence_penalty: ?f64 = null,
    frequency_penalty: ?f64 = null,
    stop_sequences: ?[]const []const u8 = null,
    seed: ?u64 = null,
};

/// Message roles
pub const MessageRole = enum {
    system,
    user,
    assistant,
    tool,
};

/// Message content types
pub const MessageContent = union(enum) {
    text: []const u8,
    parts: []const ContentPart,
};

/// A single message in the conversation
pub const Message = struct {
    role: MessageRole,
    content: MessageContent,
};

/// Tool definition
pub const ToolDefinition = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    parameters: std.json.Value,
    execute: ?*const fn (input: std.json.Value, context: ?*anyopaque) anyerror!std.json.Value = null,
};

/// Tool choice options
pub const ToolChoice = union(enum) {
    auto,
    none,
    required,
    tool: []const u8,
};

/// Options for generateText
pub const GenerateTextOptions = struct {
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

    /// Callback when each step finishes
    on_step_finish: ?*const fn (step: StepResult, context: ?*anyopaque) void = null,

    /// Callback context
    callback_context: ?*anyopaque = null,
};

/// Error types for text generation
pub const GenerateTextError = error{
    ModelError,
    NetworkError,
    InvalidPrompt,
    ToolExecutionError,
    MaxStepsExceeded,
    Cancelled,
    OutOfMemory,
};

/// Generate text using a language model
pub fn generateText(
    allocator: std.mem.Allocator,
    options: GenerateTextOptions,
) GenerateTextError!GenerateTextResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Validate options
    if (options.prompt == null and options.messages == null) {
        return GenerateTextError.InvalidPrompt;
    }
    if (options.prompt != null and options.messages != null) {
        return GenerateTextError.InvalidPrompt;
    }

    // Build initial prompt
    var messages = std.array_list.Managed(Message).init(arena_allocator);

    if (options.system) |sys| {
        messages.append(.{
            .role = .system,
            .content = .{ .text = sys },
        }) catch return GenerateTextError.OutOfMemory;
    }

    if (options.prompt) |p| {
        messages.append(.{
            .role = .user,
            .content = .{ .text = p },
        }) catch return GenerateTextError.OutOfMemory;
    } else if (options.messages) |msgs| {
        for (msgs) |msg| {
            messages.append(msg) catch return GenerateTextError.OutOfMemory;
        }
    }

    // Track steps
    var steps = std.array_list.Managed(StepResult).init(arena_allocator);
    var total_usage = LanguageModelUsage{};

    // Multi-step loop
    var step_count: u32 = 0;
    while (step_count < options.max_steps) : (step_count += 1) {
        // Convert messages to provider-level prompt
        var prompt_msgs = std.array_list.Managed(provider_types.LanguageModelV3Message).init(arena_allocator);
        for (messages.items) |msg| {
            switch (msg.content) {
                .text => |text| {
                    switch (msg.role) {
                        .system => {
                            prompt_msgs.append(provider_types.language_model.systemMessage(text)) catch return GenerateTextError.OutOfMemory;
                        },
                        .user => {
                            const m = provider_types.language_model.userTextMessage(arena_allocator, text) catch return GenerateTextError.OutOfMemory;
                            prompt_msgs.append(m) catch return GenerateTextError.OutOfMemory;
                        },
                        .assistant => {
                            const m = provider_types.language_model.assistantTextMessage(arena_allocator, text) catch return GenerateTextError.OutOfMemory;
                            prompt_msgs.append(m) catch return GenerateTextError.OutOfMemory;
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

        // Synchronous callback to capture result
        const CallbackCtx = struct { result: ?LanguageModelV3.GenerateResult = null };
        var cb_ctx = CallbackCtx{};

        // Call model's doGenerate
        const ctx_ptr: *anyopaque = @ptrCast(&cb_ctx);
        options.model.doGenerate(call_options, allocator, struct {
            fn onResult(ptr: ?*anyopaque, result: LanguageModelV3.GenerateResult) void {
                const ctx: *CallbackCtx = @ptrCast(@alignCast(ptr.?));
                ctx.result = result;
            }
        }.onResult, ctx_ptr);

        // Handle result
        const gen_success = switch (cb_ctx.result orelse return GenerateTextError.ModelError) {
            .success => |s| s,
            .failure => return GenerateTextError.ModelError,
        };

        // Extract text from content (first text part)
        var generated_text: []const u8 = "";
        for (gen_success.content) |content_item| {
            switch (content_item) {
                .text => |t| {
                    generated_text = t.text;
                    break;
                },
                else => {},
            }
        }

        // Map finish reason
        const finish_reason: FinishReason = switch (gen_success.finish_reason) {
            .stop => .stop,
            .length => .length,
            .tool_calls => .tool_calls,
            .content_filter => .content_filter,
            .@"error" => .other,
            .other => .other,
            .unknown => .unknown,
        };

        const step_result = StepResult{
            .content = &[_]ContentPart{},
            .text = generated_text,
            .finish_reason = finish_reason,
            .usage = .{
                .input_tokens = gen_success.usage.input_tokens.total,
                .output_tokens = gen_success.usage.output_tokens.total,
            },
            .tool_calls = &[_]ToolCall{},
            .tool_results = &[_]ToolResult{},
            .response = .{
                .id = if (gen_success.response) |r| r.metadata.id orelse "" else "",
                .model_id = if (gen_success.response) |r| r.metadata.model_id orelse options.model.getModelId() else options.model.getModelId(),
                .timestamp = std.time.timestamp(),
            },
        };

        total_usage = total_usage.add(step_result.usage);
        steps.append(step_result) catch return GenerateTextError.OutOfMemory;

        // Call step callback if provided
        if (options.on_step_finish) |callback| {
            callback(step_result, options.callback_context);
        }

        // Check if we should continue (tool calls present and not all resolved)
        if (step_result.finish_reason != .tool_calls) {
            break;
        }

        // Execute tools and add results to messages
        // TODO: Implement tool execution
    }

    const final_step = if (steps.items.len > 0) steps.items[steps.items.len - 1] else StepResult{
        .content = &[_]ContentPart{},
        .text = "",
        .finish_reason = .stop,
        .usage = .{},
        .tool_calls = &[_]ToolCall{},
        .tool_results = &[_]ToolResult{},
        .response = .{
            .id = "",
            .model_id = "",
            .timestamp = 0,
        },
    };

    return GenerateTextResult{
        .text = final_step.text,
        .reasoning_text = final_step.reasoning_text,
        .content = final_step.content,
        .tool_calls = final_step.tool_calls,
        .tool_results = final_step.tool_results,
        .finish_reason = final_step.finish_reason,
        .usage = final_step.usage,
        .total_usage = total_usage,
        .response = final_step.response,
        .steps = steps.toOwnedSlice() catch return GenerateTextError.OutOfMemory,
        .warnings = final_step.warnings,
    };
}

test "GenerateTextOptions default values" {
    const model: LanguageModelV3 = undefined;
    const options = GenerateTextOptions{
        .model = @constCast(&model),
        .prompt = "Hello",
    };
    try std.testing.expect(options.max_steps == 1);
    try std.testing.expect(options.max_retries == 2);
}

test "generateText returns text from mock provider" {
    const MockModel = struct {
        const Self = @This();

        const mock_content = [_]provider_types.LanguageModelV3Content{
            .{ .text = .{ .text = "Hello from mock model!" } },
        };

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
            callback(ctx, .{ .success = .{
                .content = &mock_content,
                .finish_reason = .stop,
                .usage = provider_types.LanguageModelV3Usage.initWithTotals(10, 20),
            } });
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

    var mock = MockModel{};
    var model = provider_types.asLanguageModel(MockModel, &mock);

    const result = try generateText(std.testing.allocator, .{
        .model = &model,
        .prompt = "Say hello",
    });

    // This should return the text from the mock model's doGenerate response
    try std.testing.expectEqualStrings("Hello from mock model!", result.text);
}

test "LanguageModelUsage add" {
    const usage1 = LanguageModelUsage{
        .input_tokens = 100,
        .output_tokens = 50,
    };
    const usage2 = LanguageModelUsage{
        .input_tokens = 200,
        .output_tokens = 100,
    };
    const total = usage1.add(usage2);
    try std.testing.expectEqual(@as(?u64, 300), total.input_tokens);
    try std.testing.expectEqual(@as(?u64, 150), total.output_tokens);
}
