const std = @import("std");
const provider_types = @import("provider");
const LanguageModelV3 = provider_types.LanguageModelV3;
const prompt_types = provider_types.language_model.language_model_v3_prompt;

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

    /// Get the generated text, returning error if no content was generated
    pub fn getText(self: *const GenerateTextResult) ![]const u8 {
        if (self.text.len == 0 and self.finish_reason == .other) {
            return error.NoContentGenerated;
        }
        return self.text;
    }

    /// Check if generation completed normally (stop or tool_calls)
    pub fn isComplete(self: *const GenerateTextResult) bool {
        return self.finish_reason == .stop or self.finish_reason == .tool_calls;
    }

    /// Get total token count (input + output)
    pub fn totalTokens(self: *const GenerateTextResult) u64 {
        return (self.usage.input_tokens orelse 0) +
            (self.usage.output_tokens orelse 0);
    }

    /// Check if there are any tool calls
    pub fn hasToolCalls(self: *const GenerateTextResult) bool {
        return self.tool_calls.len > 0;
    }

    /// Clean up resources allocated by generateText.
    /// Must be called when the result is no longer needed.
    pub fn deinit(self: *GenerateTextResult, allocator: std.mem.Allocator) void {
        // Free owned strings in each step
        for (self.steps) |step| {
            allocator.free(step.text);
            allocator.free(step.response.id);
            allocator.free(step.response.model_id);
            // Free tool call data (only allocated for tool steps)
            if (step.tool_calls.len > 0) {
                for (step.tool_calls) |tc| {
                    allocator.free(tc.tool_call_id);
                    allocator.free(tc.tool_name);
                    switch (tc.input) {
                        .string => |s| allocator.free(s),
                        else => {},
                    }
                }
                allocator.free(step.tool_calls);
            }
            // Free tool result data
            if (step.tool_results.len > 0) {
                for (step.tool_results) |tr| {
                    allocator.free(tr.tool_call_id);
                    allocator.free(tr.tool_name);
                    switch (tr.output) {
                        .string => |s| allocator.free(s),
                        else => {},
                    }
                }
                allocator.free(step.tool_results);
            }
        }
        allocator.free(self.steps);
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

    /// Request context for timeout/cancellation
    request_context: ?*const @import("../context.zig").RequestContext = null,

    /// Retry policy for automatic retries
    retry_policy: ?@import("../retry.zig").RetryPolicy = null,

    /// Error diagnostic out-parameter for rich error context on failure.
    error_diagnostic: ?*provider_types.ErrorDiagnostic = null,
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
    var messages = std.ArrayList(Message).empty;

    if (options.system) |sys| {
        messages.append(arena_allocator, .{
            .role = .system,
            .content = .{ .text = sys },
        }) catch return GenerateTextError.OutOfMemory;
    }

    if (options.prompt) |p| {
        messages.append(arena_allocator, .{
            .role = .user,
            .content = .{ .text = p },
        }) catch return GenerateTextError.OutOfMemory;
    } else if (options.messages) |msgs| {
        for (msgs) |msg| {
            messages.append(arena_allocator, msg) catch return GenerateTextError.OutOfMemory;
        }
    }

    // Track steps - use caller's allocator since steps are returned to caller
    var steps = std.ArrayList(StepResult).empty;
    errdefer steps.deinit(allocator);
    var total_usage = LanguageModelUsage{};
    var extra_prompt_msgs = std.ArrayList(provider_types.LanguageModelV3Message).empty;

    // Multi-step loop
    var step_count: u32 = 0;
    while (step_count < options.max_steps) : (step_count += 1) {
        // Check request context for cancellation/timeout
        if (options.request_context) |ctx| {
            if (ctx.isDone()) return GenerateTextError.Cancelled;
        }
        // Convert messages to provider-level prompt
        var prompt_msgs = std.ArrayList(provider_types.LanguageModelV3Message).empty;
        for (messages.items) |msg| {
            switch (msg.content) {
                .text => |text| {
                    switch (msg.role) {
                        .system => {
                            prompt_msgs.append(arena_allocator, provider_types.language_model.systemMessage(text)) catch return GenerateTextError.OutOfMemory;
                        },
                        .user => {
                            const m = provider_types.language_model.userTextMessage(arena_allocator, text) catch return GenerateTextError.OutOfMemory;
                            prompt_msgs.append(arena_allocator, m) catch return GenerateTextError.OutOfMemory;
                        },
                        .assistant => {
                            const m = provider_types.language_model.assistantTextMessage(arena_allocator, text) catch return GenerateTextError.OutOfMemory;
                            prompt_msgs.append(arena_allocator, m) catch return GenerateTextError.OutOfMemory;
                        },
                        .tool => {},
                    }
                },
                .parts => |parts| {
                    switch (msg.role) {
                        .system => {
                            for (parts) |part| {
                                switch (part) {
                                    .text => |t| {
                                        prompt_msgs.append(arena_allocator, provider_types.language_model.systemMessage(t.text)) catch return GenerateTextError.OutOfMemory;
                                    },
                                    else => {},
                                }
                            }
                        },
                        .user => {
                            var user_parts = std.ArrayList(prompt_types.UserPart).empty;
                            for (parts) |part| {
                                switch (part) {
                                    .text => |t| {
                                        user_parts.append(arena_allocator, .{ .text = .{ .text = t.text } }) catch return GenerateTextError.OutOfMemory;
                                    },
                                    .file => |f| {
                                        user_parts.append(arena_allocator, .{ .file = .{
                                            .data = .{ .base64 = f.data },
                                            .media_type = f.mime_type,
                                        } }) catch return GenerateTextError.OutOfMemory;
                                    },
                                    else => {},
                                }
                            }
                            if (user_parts.items.len > 0) {
                                prompt_msgs.append(arena_allocator, .{
                                    .role = .user,
                                    .content = .{ .user = user_parts.items },
                                }) catch return GenerateTextError.OutOfMemory;
                            }
                        },
                        .assistant => {
                            var asst_parts = std.ArrayList(prompt_types.AssistantPart).empty;
                            for (parts) |part| {
                                switch (part) {
                                    .text => |t| {
                                        asst_parts.append(arena_allocator, .{ .text = .{ .text = t.text } }) catch return GenerateTextError.OutOfMemory;
                                    },
                                    .file => |f| {
                                        asst_parts.append(arena_allocator, .{ .file = .{
                                            .data = .{ .base64 = f.data },
                                            .media_type = f.mime_type,
                                        } }) catch return GenerateTextError.OutOfMemory;
                                    },
                                    else => {},
                                }
                            }
                            if (asst_parts.items.len > 0) {
                                prompt_msgs.append(arena_allocator, .{
                                    .role = .assistant,
                                    .content = .{ .assistant = asst_parts.items },
                                }) catch return GenerateTextError.OutOfMemory;
                            }
                        },
                        .tool => {},
                    }
                },
            }
        }

        // Append accumulated tool exchange messages from previous steps
        for (extra_prompt_msgs.items) |msg| {
            prompt_msgs.append(arena_allocator, msg) catch return GenerateTextError.OutOfMemory;
        }

        // Convert AI-layer tools to provider-layer tools
        const provider_tools: ?[]const provider_types.LanguageModelV3CallOptions.Tool = if (options.tools) |tools| blk: {
            const result = arena_allocator.alloc(provider_types.LanguageModelV3CallOptions.Tool, tools.len) catch
                return GenerateTextError.OutOfMemory;
            for (tools, 0..) |td, i| {
                result[i] = .{ .function = .{
                    .name = td.name,
                    .description = td.description,
                    .input_schema = provider_types.JsonValue.fromStdJson(arena_allocator, td.parameters) catch
                        return GenerateTextError.OutOfMemory,
                } };
            }
            break :blk result;
        } else null;

        // Convert AI-layer tool_choice to provider-layer tool_choice
        const provider_tool_choice: ?provider_types.LanguageModelV3ToolChoice = if (provider_tools != null) switch (options.tool_choice) {
            .auto => .auto,
            .none => .none,
            .required => .required,
            .tool => |name| .{ .tool = .{ .tool_name = name } },
        } else null;

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
            .tools = provider_tools,
            .tool_choice = provider_tool_choice,
            .error_diagnostic = options.error_diagnostic,
        };

        // Synchronous callback to capture result
        const CallbackCtx = struct { result: ?LanguageModelV3.GenerateResult = null };
        var cb_ctx = CallbackCtx{};

        // Call model's doGenerate (use arena for provider temp allocations)
        const ctx_ptr: *anyopaque = @ptrCast(&cb_ctx);
        options.model.doGenerate(call_options, arena_allocator, struct {
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

        // Dupe result strings to base allocator so they outlive the arena
        const owned_text = allocator.dupe(u8, generated_text) catch return GenerateTextError.OutOfMemory;
        errdefer allocator.free(owned_text);

        const raw_id = if (gen_success.response) |r| r.metadata.id orelse "" else "";
        const owned_id = allocator.dupe(u8, raw_id) catch return GenerateTextError.OutOfMemory;
        errdefer allocator.free(owned_id);

        const raw_model_id = if (gen_success.response) |r| r.metadata.model_id orelse options.model.getModelId() else options.model.getModelId();
        const owned_model_id = allocator.dupe(u8, raw_model_id) catch return GenerateTextError.OutOfMemory;
        errdefer allocator.free(owned_model_id);

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

        // Extract tool calls and execute tools if applicable
        var owned_tool_calls: []const ToolCall = &[_]ToolCall{};
        var owned_tool_results: []const ToolResult = &[_]ToolResult{};

        if (finish_reason == .tool_calls) {
            var tool_calls_builder = std.ArrayList(ToolCall).empty;
            var tool_results_builder = std.ArrayList(ToolResult).empty;

            for (gen_success.content) |content_item| {
                switch (content_item) {
                    .tool_call => |tc| {
                        const owned_tc_id = allocator.dupe(u8, tc.tool_call_id) catch return GenerateTextError.OutOfMemory;
                        const owned_tc_name = allocator.dupe(u8, tc.tool_name) catch return GenerateTextError.OutOfMemory;
                        const owned_tc_input = allocator.dupe(u8, tc.input) catch return GenerateTextError.OutOfMemory;

                        tool_calls_builder.append(allocator, .{
                            .tool_call_id = owned_tc_id,
                            .tool_name = owned_tc_name,
                            .input = .{ .string = owned_tc_input },
                        }) catch return GenerateTextError.OutOfMemory;

                        // Execute tool if available
                        if (options.tools) |tools| {
                            for (tools) |tool_def| {
                                if (std.mem.eql(u8, tool_def.name, tc.tool_name)) {
                                    if (tool_def.execute) |execute_fn| {
                                        const parsed_input = std.json.parseFromSlice(
                                            std.json.Value,
                                            arena_allocator,
                                            tc.input,
                                            .{},
                                        ) catch {
                                            tool_results_builder.append(allocator, .{
                                                .tool_call_id = allocator.dupe(u8, tc.tool_call_id) catch return GenerateTextError.OutOfMemory,
                                                .tool_name = allocator.dupe(u8, tc.tool_name) catch return GenerateTextError.OutOfMemory,
                                                .output = .{ .string = allocator.dupe(u8, "Failed to parse tool input") catch return GenerateTextError.OutOfMemory },
                                            }) catch return GenerateTextError.OutOfMemory;
                                            break;
                                        };

                                        const exec_result = execute_fn(parsed_input.value, options.context) catch {
                                            tool_results_builder.append(allocator, .{
                                                .tool_call_id = allocator.dupe(u8, tc.tool_call_id) catch return GenerateTextError.OutOfMemory,
                                                .tool_name = allocator.dupe(u8, tc.tool_name) catch return GenerateTextError.OutOfMemory,
                                                .output = .{ .string = allocator.dupe(u8, "Tool execution failed") catch return GenerateTextError.OutOfMemory },
                                            }) catch return GenerateTextError.OutOfMemory;
                                            break;
                                        };

                                        const result_str = std.json.Stringify.valueAlloc(arena_allocator, exec_result, .{}) catch
                                            return GenerateTextError.OutOfMemory;

                                        tool_results_builder.append(allocator, .{
                                            .tool_call_id = allocator.dupe(u8, tc.tool_call_id) catch return GenerateTextError.OutOfMemory,
                                            .tool_name = allocator.dupe(u8, tc.tool_name) catch return GenerateTextError.OutOfMemory,
                                            .output = .{ .string = allocator.dupe(u8, result_str) catch return GenerateTextError.OutOfMemory },
                                        }) catch return GenerateTextError.OutOfMemory;
                                    }
                                    break;
                                }
                            }
                        }
                    },
                    else => {},
                }
            }

            owned_tool_calls = tool_calls_builder.toOwnedSlice(allocator) catch return GenerateTextError.OutOfMemory;
            owned_tool_results = tool_results_builder.toOwnedSlice(allocator) catch return GenerateTextError.OutOfMemory;
        }

        const step_result = StepResult{
            .content = &[_]ContentPart{},
            .text = owned_text,
            .finish_reason = finish_reason,
            .usage = .{
                .input_tokens = gen_success.usage.input_tokens.total,
                .output_tokens = gen_success.usage.output_tokens.total,
            },
            .tool_calls = owned_tool_calls,
            .tool_results = owned_tool_results,
            .response = .{
                .id = owned_id,
                .model_id = owned_model_id,
                .timestamp = std.time.timestamp(),
            },
        };

        total_usage = total_usage.add(step_result.usage);
        steps.append(allocator, step_result) catch return GenerateTextError.OutOfMemory;

        // Call step callback if provided
        if (options.on_step_finish) |callback| {
            callback(step_result, options.callback_context);
        }

        // Check if we should continue (tool calls present and not all resolved)
        if (step_result.finish_reason != .tool_calls) {
            break;
        }

        // Build provider-level messages for tool exchange in next iteration
        // Assistant message with tool call parts
        var assistant_parts = arena_allocator.alloc(prompt_types.AssistantPart, owned_tool_calls.len) catch return GenerateTextError.OutOfMemory;
        for (owned_tool_calls, 0..) |tc, i| {
            const input_json = provider_types.JsonValue.parse(arena_allocator, tc.input.string) catch
                provider_types.JsonValue{ .string = tc.input.string };
            assistant_parts[i] = .{ .tool_call = .{
                .tool_call_id = tc.tool_call_id,
                .tool_name = tc.tool_name,
                .input = input_json,
            } };
        }
        extra_prompt_msgs.append(arena_allocator, .{
            .role = .assistant,
            .content = .{ .assistant = assistant_parts },
        }) catch return GenerateTextError.OutOfMemory;

        // Tool result message
        var tool_result_parts = arena_allocator.alloc(prompt_types.ToolResultPart, owned_tool_results.len) catch return GenerateTextError.OutOfMemory;
        for (owned_tool_results, 0..) |tr, i| {
            tool_result_parts[i] = .{
                .tool_call_id = tr.tool_call_id,
                .tool_name = tr.tool_name,
                .output = .{ .text = .{ .value = switch (tr.output) {
                    .string => |s| s,
                    else => "null",
                } } },
            };
        }
        extra_prompt_msgs.append(arena_allocator, .{
            .role = .tool,
            .content = .{ .tool = tool_result_parts },
        }) catch return GenerateTextError.OutOfMemory;
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
        .steps = steps.toOwnedSlice(allocator) catch return GenerateTextError.OutOfMemory,
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

    var result = try generateText(std.testing.allocator, .{
        .model = &model,
        .prompt = "Say hello",
    });
    defer result.deinit(std.testing.allocator);

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

test "generateText multi-turn conversation" {
    const MockMultiTurnModel = struct {
        const Self = @This();

        const response_content = [_]provider_types.LanguageModelV3Content{
            .{ .text = .{ .text = "Paris is the capital of France." } },
        };

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-multiturn";
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
            call_options: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            // Verify multi-turn prompt structure:
            // system + user + assistant + user = 4 messages
            if (call_options.prompt.len < 4) {
                callback(ctx, .{ .failure = error.InvalidPrompt });
                return;
            }
            // Verify roles: system, user, assistant, user
            if (call_options.prompt[0].role != .system or
                call_options.prompt[1].role != .user or
                call_options.prompt[2].role != .assistant or
                call_options.prompt[3].role != .user)
            {
                callback(ctx, .{ .failure = error.InvalidPrompt });
                return;
            }
            callback(ctx, .{ .success = .{
                .content = &response_content,
                .finish_reason = .stop,
                .usage = provider_types.LanguageModelV3Usage.initWithTotals(25, 10),
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

    var mock = MockMultiTurnModel{};
    var model = provider_types.asLanguageModel(MockMultiTurnModel, &mock);

    var result = try generateText(std.testing.allocator, .{
        .model = &model,
        .system = "You are a geography expert.",
        .messages = &[_]Message{
            .{ .role = .user, .content = .{ .text = "What is the capital of France?" } },
            .{ .role = .assistant, .content = .{ .text = "The capital of France is Paris." } },
            .{ .role = .user, .content = .{ .text = "Tell me more about it." } },
        },
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("Paris is the capital of France.", result.text);
    try std.testing.expectEqual(@as(?u64, 25), result.usage.input_tokens);
}

test "generateText returns error on model failure" {
    const MockFailModel = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-fail";
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

    var mock = MockFailModel{};
    var model = provider_types.asLanguageModel(MockFailModel, &mock);

    const result = generateText(std.testing.allocator, .{
        .model = &model,
        .prompt = "This should fail",
    });

    try std.testing.expectError(GenerateTextError.ModelError, result);
}

test "generateText returns error on empty prompt" {
    const MockModel2 = struct {
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
            callback(ctx, .{ .success = .{
                .content = &[_]provider_types.LanguageModelV3Content{},
                .finish_reason = .stop,
                .usage = provider_types.LanguageModelV3Usage.init(),
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

    var mock = MockModel2{};
    var model = provider_types.asLanguageModel(MockModel2, &mock);

    // Neither prompt nor messages provided
    const result = generateText(std.testing.allocator, .{
        .model = &model,
    });

    try std.testing.expectError(GenerateTextError.InvalidPrompt, result);
}

test "generateText sequential requests don't leak memory" {
    const MockStressModel = struct {
        const Self = @This();

        const mock_content = [_]provider_types.LanguageModelV3Content{
            .{ .text = .{ .text = "Response" } },
        };

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-stress";
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
                .usage = provider_types.LanguageModelV3Usage.initWithTotals(5, 10),
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

    var mock = MockStressModel{};
    var model = provider_types.asLanguageModel(MockStressModel, &mock);

    // Run 50 sequential requests - testing allocator detects leaks
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        var result = try generateText(std.testing.allocator, .{
            .model = &model,
            .prompt = "Hello",
        });
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings("Response", result.text);
    }
}

test "generateText steps remain valid after return (no use-after-free)" {
    const MockModel3 = struct {
        const Self = @This();

        const mock_content = [_]provider_types.LanguageModelV3Content{
            .{ .text = .{ .text = "Step result text" } },
        };

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-steps";
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

    var mock = MockModel3{};
    var model = provider_types.asLanguageModel(MockModel3, &mock);

    var result = try generateText(std.testing.allocator, .{
        .model = &model,
        .prompt = "Test steps",
    });
    defer result.deinit(std.testing.allocator);

    // Verify steps data is accessible and valid after function return
    try std.testing.expectEqual(@as(usize, 1), result.steps.len);
    try std.testing.expectEqualStrings("Step result text", result.steps[0].text);
    try std.testing.expectEqual(FinishReason.stop, result.steps[0].finish_reason);
    try std.testing.expectEqual(@as(?u64, 10), result.steps[0].usage.input_tokens);
    try std.testing.expectEqual(@as(?u64, 20), result.steps[0].usage.output_tokens);
}

test "GenerateTextResult.getText returns text" {
    const result = GenerateTextResult{
        .text = "Hello world",
        .content = &.{},
        .tool_calls = &.{},
        .tool_results = &.{},
        .finish_reason = .stop,
        .usage = .{ .input_tokens = 10, .output_tokens = 5 },
        .total_usage = .{ .input_tokens = 10, .output_tokens = 5 },
        .response = .{ .id = "1", .model_id = "test", .timestamp = 0 },
        .steps = &.{},
    };
    try std.testing.expectEqualStrings("Hello world", try result.getText());
}

test "GenerateTextResult.isComplete" {
    const complete = GenerateTextResult{
        .text = "done",
        .content = &.{},
        .tool_calls = &.{},
        .tool_results = &.{},
        .finish_reason = .stop,
        .usage = .{},
        .total_usage = .{},
        .response = .{ .id = "", .model_id = "", .timestamp = 0 },
        .steps = &.{},
    };
    try std.testing.expect(complete.isComplete());

    const incomplete = GenerateTextResult{
        .text = "",
        .content = &.{},
        .tool_calls = &.{},
        .tool_results = &.{},
        .finish_reason = .length,
        .usage = .{},
        .total_usage = .{},
        .response = .{ .id = "", .model_id = "", .timestamp = 0 },
        .steps = &.{},
    };
    try std.testing.expect(!incomplete.isComplete());
}

test "GenerateTextResult.totalTokens" {
    const result = GenerateTextResult{
        .text = "",
        .content = &.{},
        .tool_calls = &.{},
        .tool_results = &.{},
        .finish_reason = .stop,
        .usage = .{ .input_tokens = 100, .output_tokens = 50 },
        .total_usage = .{},
        .response = .{ .id = "", .model_id = "", .timestamp = 0 },
        .steps = &.{},
    };
    try std.testing.expectEqual(@as(u64, 150), result.totalTokens());
}

test "GenerateTextResult.hasToolCalls" {
    const no_tools = GenerateTextResult{
        .text = "",
        .content = &.{},
        .tool_calls = &.{},
        .tool_results = &.{},
        .finish_reason = .stop,
        .usage = .{},
        .total_usage = .{},
        .response = .{ .id = "", .model_id = "", .timestamp = 0 },
        .steps = &.{},
    };
    try std.testing.expect(!no_tools.hasToolCalls());

    const with_tools = GenerateTextResult{
        .text = "",
        .content = &.{},
        .tool_calls = &[_]ToolCall{.{
            .tool_call_id = "1",
            .tool_name = "test",
            .input = .{ .string = "{}" },
        }},
        .tool_results = &.{},
        .finish_reason = .tool_calls,
        .usage = .{},
        .total_usage = .{},
        .response = .{ .id = "", .model_id = "", .timestamp = 0 },
        .steps = &.{},
    };
    try std.testing.expect(with_tools.hasToolCalls());
}

test "generateText executes tools in agentic loop" {
    const MockToolModel = struct {
        call_count: u32 = 0,

        const Self = @This();

        const tool_call_content = [_]provider_types.LanguageModelV3Content{
            .{ .tool_call = provider_types.language_model.LanguageModelV3ToolCall.init(
                "call-1",
                "get_weather",
                "{\"city\":\"London\"}",
            ) },
        };

        const text_content = [_]provider_types.LanguageModelV3Content{
            .{ .text = .{ .text = "The weather in London is sunny, 22C." } },
        };

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-tool";
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
            self: *Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            self.call_count += 1;
            if (self.call_count == 1) {
                // First call: return tool call
                callback(ctx, .{ .success = .{
                    .content = &tool_call_content,
                    .finish_reason = .tool_calls,
                    .usage = provider_types.LanguageModelV3Usage.initWithTotals(10, 5),
                } });
            } else {
                // Second call: return text response
                callback(ctx, .{ .success = .{
                    .content = &text_content,
                    .finish_reason = .stop,
                    .usage = provider_types.LanguageModelV3Usage.initWithTotals(15, 10),
                } });
            }
        }

        pub fn doStream(
            _: *Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callbacks: LanguageModelV3.StreamCallbacks,
        ) void {
            callbacks.on_complete(callbacks.ctx, null);
        }
    };

    const tool_execute = struct {
        fn execute(_: std.json.Value, _: ?*anyopaque) anyerror!std.json.Value {
            return .{ .string = "sunny, 22C" };
        }
    }.execute;

    var mock = MockToolModel{};
    var model = provider_types.asLanguageModel(MockToolModel, &mock);

    const tools = [_]ToolDefinition{.{
        .name = "get_weather",
        .description = "Get weather for a city",
        .parameters = .null,
        .execute = tool_execute,
    }};

    var result = try generateText(std.testing.allocator, .{
        .model = &model,
        .prompt = "What is the weather in London?",
        .tools = &tools,
        .max_steps = 3,
    });
    defer result.deinit(std.testing.allocator);

    // Model should have been called twice (tool call + final response)
    try std.testing.expectEqual(@as(u32, 2), mock.call_count);

    // Final result should be from the second (text) step
    try std.testing.expectEqualStrings("The weather in London is sunny, 22C.", result.text);
    try std.testing.expectEqual(FinishReason.stop, result.finish_reason);

    // Should have 2 steps
    try std.testing.expectEqual(@as(usize, 2), result.steps.len);

    // First step: tool call
    try std.testing.expectEqual(FinishReason.tool_calls, result.steps[0].finish_reason);
    try std.testing.expectEqual(@as(usize, 1), result.steps[0].tool_calls.len);
    try std.testing.expectEqualStrings("get_weather", result.steps[0].tool_calls[0].tool_name);
    try std.testing.expectEqualStrings("call-1", result.steps[0].tool_calls[0].tool_call_id);

    // First step: tool result
    try std.testing.expectEqual(@as(usize, 1), result.steps[0].tool_results.len);
    try std.testing.expectEqualStrings("get_weather", result.steps[0].tool_results[0].tool_name);

    // Second step: text response
    try std.testing.expectEqual(FinishReason.stop, result.steps[1].finish_reason);
    try std.testing.expectEqualStrings("The weather in London is sunny, 22C.", result.steps[1].text);

    // Total usage should be sum of both steps
    try std.testing.expectEqual(@as(?u64, 25), result.total_usage.input_tokens);
    try std.testing.expectEqual(@as(?u64, 15), result.total_usage.output_tokens);
}

test "generateText passes tools through to provider call_options" {
    const MockVerifyToolsModel = struct {
        received_tools: bool = false,
        received_tool_count: usize = 0,
        received_tool_choice: bool = false,

        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-verify-tools";
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
            self: *Self,
            call_options: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            // Verify tools were passed through
            self.received_tools = call_options.hasTools();
            self.received_tool_count = call_options.getToolCount();
            self.received_tool_choice = call_options.tool_choice != null;

            const text_content = [_]provider_types.LanguageModelV3Content{
                .{ .text = .{ .text = "ok" } },
            };
            callback(ctx, .{ .success = .{
                .content = &text_content,
                .finish_reason = .stop,
                .usage = provider_types.LanguageModelV3Usage.initWithTotals(5, 5),
            } });
        }

        pub fn doStream(
            _: *Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callbacks: LanguageModelV3.StreamCallbacks,
        ) void {
            callbacks.on_complete(callbacks.ctx, null);
        }
    };

    var mock = MockVerifyToolsModel{};
    var model = provider_types.asLanguageModel(MockVerifyToolsModel, &mock);

    const tools = [_]ToolDefinition{
        .{
            .name = "get_weather",
            .description = "Get weather",
            .parameters = .null,
        },
        .{
            .name = "search",
            .description = "Search the web",
            .parameters = .null,
        },
    };

    var result = try generateText(std.testing.allocator, .{
        .model = &model,
        .prompt = "test",
        .tools = &tools,
        .tool_choice = .required,
    });
    defer result.deinit(std.testing.allocator);

    // Verify the mock saw the tools
    try std.testing.expect(mock.received_tools);
    try std.testing.expectEqual(@as(usize, 2), mock.received_tool_count);
    try std.testing.expect(mock.received_tool_choice);
}
