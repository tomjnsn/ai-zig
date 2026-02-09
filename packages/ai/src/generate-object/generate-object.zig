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

    /// Clean up resources
    pub fn deinit(self: *GenerateObjectResult, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Arena allocator handles cleanup
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
    var system_parts = std.array_list.Managed(u8).init(arena_allocator);
    const writer = system_parts.writer();

    if (options.system) |sys| {
        writer.writeAll(sys) catch return GenerateObjectError.OutOfMemory;
        writer.writeAll("\n\n") catch return GenerateObjectError.OutOfMemory;
    }

    writer.writeAll("You must respond with a valid JSON object matching the following schema:\n") catch return GenerateObjectError.OutOfMemory;

    // Serialize schema using valueAlloc
    const schema_json = std.json.Stringify.valueAlloc(arena_allocator, options.schema.json_schema, .{}) catch return GenerateObjectError.OutOfMemory;
    writer.writeAll(schema_json) catch return GenerateObjectError.OutOfMemory;

    // TODO: Call model with prepared prompt
    // For now, return a placeholder result

    return GenerateObjectResult{
        .object = std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
        .raw_text = "{}",
        .usage = .{},
        .response = .{
            .id = "placeholder",
            .model_id = "placeholder",
            .timestamp = std.time.timestamp(),
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

    const result = try generateObject(std.testing.allocator, .{
        .model = &model,
        .prompt = "Generate a person",
        .schema = .{
            .json_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.testing.allocator) },
        },
    });

    // Should have parsed JSON object (currently returns empty object - test should FAIL
    // because raw_text should come from model, not be hardcoded "{}"))
    try std.testing.expectEqualStrings("{\"name\":\"Alice\",\"age\":30}", result.raw_text);
    try std.testing.expect(result.object == .object);
}
