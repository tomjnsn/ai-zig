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

    // Serialize schema
    var schema_buf = std.array_list.Managed(u8).init(arena_allocator);
    std.json.stringify(options.schema.json_schema, .{}, schema_buf.writer()) catch return GenerateObjectError.OutOfMemory;
    writer.writeAll(schema_buf.items) catch return GenerateObjectError.OutOfMemory;

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
) !std.json.Value {
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
                const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_text, .{}) catch {
                    return error.InvalidJson;
                };
                return parsed.value;
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

    const result = try parseJsonOutput(allocator, text);
    defer result.deinit(allocator); // Clean up parsed value

    try std.testing.expect(result == .object);
}
