const std = @import("std");
const provider_types = @import("provider");
const generate_text = @import("../generate-text/generate-text.zig");

const LanguageModelV3 = provider_types.LanguageModelV3;
const LanguageModelUsage = generate_text.LanguageModelUsage;
const ResponseMetadata = generate_text.ResponseMetadata;
const CallSettings = generate_text.CallSettings;
const Message = generate_text.Message;

/// Schema type for object generation
pub const Schema = struct {
    /// JSON Schema definition
    json_schema: std.json.Value,

    /// Optional name for the schema
    name: ?[]const u8 = null,

    /// Optional description
    description: ?[]const u8 = null,
};

/// Output mode for object generation
pub const OutputMode = enum {
    /// Use JSON mode (model outputs JSON)
    json,

    /// Use tool/function calling
    tool,

    /// Auto-select based on model capabilities
    auto,
};

/// Result of generateObject
pub const GenerateObjectResult = struct {
    /// The parsed object as JSON value
    object: std.json.Value,

    /// Raw text output from the model
    raw_text: []const u8,

    /// Token usage
    usage: LanguageModelUsage,

    /// Response metadata
    response: ResponseMetadata,

    /// Warnings from the model
    warnings: ?[]const []const u8 = null,

    /// Internal: holds the parsed JSON for cleanup
    _parsed: ?std.json.Parsed(std.json.Value) = null,

    /// Clean up resources
    pub fn deinit(self: *GenerateObjectResult) void {
        if (self._parsed) |p| {
            p.deinit();
        }
    }
};

/// Options for generateObject
pub const GenerateObjectOptions = struct {
    /// The language model to use
    model: *LanguageModelV3,

    /// Schema defining the expected object structure
    schema: Schema,

    /// System prompt
    system: ?[]const u8 = null,

    /// Simple text prompt (use this OR messages, not both)
    prompt: ?[]const u8 = null,

    /// Conversation messages (use this OR prompt, not both)
    messages: ?[]const Message = null,

    /// Output mode
    mode: OutputMode = .auto,

    /// Call settings
    settings: CallSettings = .{},

    /// Maximum retries on failure
    max_retries: u32 = 2,

    /// Schema name for tool mode
    schema_name: ?[]const u8 = null,

    /// Schema description for tool mode
    schema_description: ?[]const u8 = null,

    /// Request context for timeout/cancellation
    request_context: ?*const @import("../context.zig").RequestContext = null,

    /// Retry policy for automatic retries
    retry_policy: ?@import("../retry.zig").RetryPolicy = null,
};

/// Error types for object generation
pub const GenerateObjectError = error{
    ModelError,
    NetworkError,
    InvalidPrompt,
    InvalidSchema,
    ParseError,
    ValidationError,
    Cancelled,
    OutOfMemory,
};

/// Generate a structured object using a language model
pub fn generateObject(
    allocator: std.mem.Allocator,
    options: GenerateObjectOptions,
) GenerateObjectError!GenerateObjectResult {
    // Check request context for cancellation/timeout
    if (options.request_context) |ctx| {
        if (ctx.isDone()) return GenerateObjectError.Cancelled;
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Validate options
    if (options.prompt == null and options.messages == null) {
        return GenerateObjectError.InvalidPrompt;
    }
    if (options.prompt != null and options.messages != null) {
        return GenerateObjectError.InvalidPrompt;
    }

    // Build system prompt with schema instructions
    var system_parts = std.ArrayList(u8).empty;
    const writer = system_parts.writer(arena_allocator);

    if (options.system) |sys| {
        writer.writeAll(sys) catch return GenerateObjectError.OutOfMemory;
        writer.writeAll("\n\n") catch return GenerateObjectError.OutOfMemory;
    }

    writer.writeAll("You must respond with a valid JSON object matching the following schema:\n") catch return GenerateObjectError.OutOfMemory;

    // Serialize schema using valueAlloc
    const schema_json = std.json.Stringify.valueAlloc(arena_allocator, options.schema.json_schema, .{}) catch return GenerateObjectError.OutOfMemory;
    writer.writeAll(schema_json) catch return GenerateObjectError.OutOfMemory;

    // Build prompt messages for the model
    var prompt_msgs = std.ArrayList(provider_types.LanguageModelV3Message).empty;

    // Add system message with schema instructions
    prompt_msgs.append(arena_allocator, provider_types.language_model.systemMessage(system_parts.items)) catch return GenerateObjectError.OutOfMemory;

    // Add user message
    if (options.prompt) |prompt| {
        const msg = provider_types.language_model.userTextMessage(arena_allocator, prompt) catch return GenerateObjectError.OutOfMemory;
        prompt_msgs.append(arena_allocator, msg) catch return GenerateObjectError.OutOfMemory;
    }

    // Build call options
    const call_options = provider_types.LanguageModelV3CallOptions{
        .prompt = prompt_msgs.items,
        .max_output_tokens = options.settings.max_output_tokens,
        .temperature = if (options.settings.temperature) |t| @as(f32, @floatCast(t)) else null,
        .top_p = if (options.settings.top_p) |t| @as(f32, @floatCast(t)) else null,
        .seed = if (options.settings.seed) |s| @as(i64, @intCast(s)) else null,
    };

    // Call model.doGenerate
    const CallbackCtx = struct { result: ?LanguageModelV3.GenerateResult = null };
    var cb_ctx = CallbackCtx{};
    const ctx_ptr: *anyopaque = @ptrCast(&cb_ctx);

    options.model.doGenerate(
        call_options,
        allocator,
        struct {
            fn onResult(ptr: ?*anyopaque, result: LanguageModelV3.GenerateResult) void {
                const ctx: *CallbackCtx = @ptrCast(@alignCast(ptr.?));
                ctx.result = result;
            }
        }.onResult,
        ctx_ptr,
    );

    const gen_success = switch (cb_ctx.result orelse return GenerateObjectError.ModelError) {
        .success => |s| s,
        .failure => return GenerateObjectError.ModelError,
    };

    // Extract text from content
    var raw_text: []const u8 = "";
    for (gen_success.content) |content| {
        switch (content) {
            .text => |t| {
                raw_text = t.text;
                break;
            },
            else => {},
        }
    }

    // Parse JSON from model output
    const parsed = parseJsonOutput(allocator, raw_text) catch return GenerateObjectError.ParseError;

    // Map usage
    const usage = LanguageModelUsage{
        .input_tokens = gen_success.usage.input_tokens.total,
        .output_tokens = gen_success.usage.output_tokens.total,
    };

    return GenerateObjectResult{
        .object = parsed.value,
        ._parsed = parsed,
        .raw_text = raw_text,
        .usage = usage,
        .response = blk: {
            const model_id = options.model.getModelId();
            if (gen_success.response) |r| {
                break :blk ResponseMetadata{
                    .id = r.metadata.id orelse "",
                    .model_id = r.metadata.model_id orelse model_id,
                    .timestamp = r.metadata.timestamp orelse 0,
                };
            } else {
                break :blk ResponseMetadata{
                    .id = "",
                    .model_id = model_id,
                    .timestamp = 0,
                };
            }
        },
        .warnings = null,
    };
}

/// Parse JSON from model output
pub fn parseJsonOutput(
    allocator: std.mem.Allocator,
    text: []const u8,
) !std.json.Parsed(std.json.Value) {
    // Try to find JSON in the output
    var json_start: ?usize = null;
    var json_end: ?usize = null;

    // Look for JSON object
    for (text, 0..) |char, i| {
        if (char == '{' and json_start == null) {
            json_start = i;
        }
        if (char == '}') {
            json_end = i + 1;
        }
    }

    if (json_start == null or json_end == null) {
        // Try to find JSON array
        for (text, 0..) |char, i| {
            if (char == '[' and json_start == null) {
                json_start = i;
            }
            if (char == ']') {
                json_end = i + 1;
            }
        }
    }

    if (json_start) |start| {
        if (json_end) |end| {
            if (end > start) {
                const json_text = text[start..end];
                return std.json.parseFromSlice(std.json.Value, allocator, json_text, .{}) catch {
                    return error.InvalidJson;
                };
            }
        }
    }

    return error.NoJsonFound;
}

/// Validate parsed object against schema (basic validation)
pub fn validateAgainstSchema(
    object: std.json.Value,
    schema: std.json.Value,
) bool {
    _ = object;
    _ = schema;
    // TODO: Implement JSON Schema validation
    return true;
}

test "GenerateObjectOptions default values" {
    const model: LanguageModelV3 = undefined;
    const options = GenerateObjectOptions{
        .model = @constCast(&model),
        .prompt = "Generate a user",
        .schema = .{
            .json_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.testing.allocator) },
        },
    };
    try std.testing.expect(options.mode == .auto);
    try std.testing.expect(options.max_retries == 2);
}

test "parseJsonOutput simple object" {
    const allocator = std.testing.allocator;
    const text = "Here is the JSON: {\"name\": \"test\"}";

    const parsed = try parseJsonOutput(allocator, text);
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .object);
}

test "generateObject returns valid JSON object from mock model" {
    const MockModel = struct {
        const Self = @This();

        const mock_content = [_]provider_types.LanguageModelV3Content{
            .{ .text = .{ .text = "{\"name\":\"Alice\",\"age\":30}" } },
        };

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-json";
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
                .usage = provider_types.LanguageModelV3Usage.initWithTotals(15, 25),
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

    var result = try generateObject(std.testing.allocator, .{
        .model = &model,
        .prompt = "Generate a person",
        .schema = .{
            .json_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.testing.allocator) },
        },
    });
    defer result.deinit();

    // Should have parsed JSON object from model
    try std.testing.expectEqualStrings("{\"name\":\"Alice\",\"age\":30}", result.raw_text);
    try std.testing.expect(result.object == .object);
}
