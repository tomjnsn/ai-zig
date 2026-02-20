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

    /// Internal: allocator used to dupe owned strings
    _allocator: ?std.mem.Allocator = null,

    /// Clean up resources
    pub fn deinit(self: *GenerateObjectResult) void {
        if (self._allocator) |alloc| {
            alloc.free(self.raw_text);
            alloc.free(self.response.id);
            alloc.free(self.response.model_id);
        }
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

    /// Error diagnostic out-parameter for rich error context on failure.
    error_diagnostic: ?*provider_types.ErrorDiagnostic = null,
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

    // Serialize schema to JSON string (std.json.Stringify.valueAlloc exists in Zig 0.15+)
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
        .error_diagnostic = options.error_diagnostic,
    };

    // Call model.doGenerate
    const CallbackCtx = struct { result: ?LanguageModelV3.GenerateResult = null };
    var cb_ctx = CallbackCtx{};
    const ctx_ptr: *anyopaque = @ptrCast(&cb_ctx);

    options.model.doGenerate(
        call_options,
        arena_allocator,
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

    // Dupe raw_text to base allocator so it outlives the arena
    raw_text = allocator.dupe(u8, raw_text) catch return GenerateObjectError.OutOfMemory;
    errdefer allocator.free(raw_text);

    // Parse JSON from model output
    const parsed = parseJsonOutput(allocator, raw_text) catch return GenerateObjectError.ParseError;

    // Validate against schema
    if (!validateAgainstSchema(parsed.value, options.schema.json_schema)) {
        var p = parsed;
        p.deinit();
        return GenerateObjectError.ValidationError;
    }

    // Map usage
    const usage = LanguageModelUsage{
        .input_tokens = gen_success.usage.input_tokens.total,
        .output_tokens = gen_success.usage.output_tokens.total,
    };

    // Dupe response strings to base allocator so they outlive the arena
    const raw_id = if (gen_success.response) |r| r.metadata.id orelse "" else "";
    const owned_id = allocator.dupe(u8, raw_id) catch return GenerateObjectError.OutOfMemory;
    errdefer allocator.free(owned_id);

    const model_id = options.model.getModelId();
    const raw_model_id = if (gen_success.response) |r| r.metadata.model_id orelse model_id else model_id;
    const owned_model_id = allocator.dupe(u8, raw_model_id) catch return GenerateObjectError.OutOfMemory;
    errdefer allocator.free(owned_model_id);

    return GenerateObjectResult{
        .object = parsed.value,
        ._parsed = parsed,
        ._allocator = allocator,
        .raw_text = raw_text,
        .usage = usage,
        .response = blk: {
            if (gen_success.response) |r| {
                break :blk ResponseMetadata{
                    .id = owned_id,
                    .model_id = owned_model_id,
                    .timestamp = r.metadata.timestamp orelse 0,
                };
            } else {
                break :blk ResponseMetadata{
                    .id = owned_id,
                    .model_id = owned_model_id,
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

/// Validate a JSON value against a JSON Schema.
/// Supports: type, required, properties (recursive), items, enum.
pub fn validateAgainstSchema(
    value: std.json.Value,
    schema: std.json.Value,
) bool {
    // Schema must be an object to contain constraints
    const schema_obj = switch (schema) {
        .object => |o| o,
        else => return true,
    };

    // Check "type" constraint
    if (schema_obj.get("type")) |type_val| {
        switch (type_val) {
            .string => |type_str| {
                if (!checkJsonType(value, type_str)) return false;
            },
            else => {},
        }
    }

    switch (value) {
        .object => |obj| {
            // Check "required" fields
            if (schema_obj.get("required")) |required_val| {
                switch (required_val) {
                    .array => |required_arr| {
                        for (required_arr.items) |req| {
                            switch (req) {
                                .string => |req_name| {
                                    if (!obj.contains(req_name)) return false;
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            }
            // Validate "properties" recursively
            if (schema_obj.get("properties")) |properties_val| {
                switch (properties_val) {
                    .object => |properties| {
                        var iter = properties.iterator();
                        while (iter.next()) |entry| {
                            if (obj.get(entry.key_ptr.*)) |prop_value| {
                                if (!validateAgainstSchema(prop_value, entry.value_ptr.*)) return false;
                            }
                        }
                    },
                    else => {},
                }
            }
        },
        .array => |arr| {
            // Validate "items" schema for each array element
            if (schema_obj.get("items")) |items_schema| {
                for (arr.items) |item| {
                    if (!validateAgainstSchema(item, items_schema)) return false;
                }
            }
        },
        else => {},
    }

    // Check "enum" constraint
    if (schema_obj.get("enum")) |enum_val| {
        switch (enum_val) {
            .array => |enum_arr| {
                var found = false;
                for (enum_arr.items) |allowed| {
                    if (jsonValuesEqual(value, allowed)) {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            },
            else => {},
        }
    }

    return true;
}

/// Check if a JSON value matches an expected JSON Schema type string.
fn checkJsonType(value: std.json.Value, expected: []const u8) bool {
    if (std.mem.eql(u8, expected, "object")) return value == .object;
    if (std.mem.eql(u8, expected, "array")) return value == .array;
    if (std.mem.eql(u8, expected, "string")) return value == .string;
    if (std.mem.eql(u8, expected, "number")) return value == .float or value == .integer or value == .number_string;
    if (std.mem.eql(u8, expected, "integer")) return value == .integer;
    if (std.mem.eql(u8, expected, "boolean")) return value == .bool;
    if (std.mem.eql(u8, expected, "null")) return value == .null;
    return true; // Unknown type, pass
}

/// Simple equality check for JSON values (used for enum validation).
fn jsonValuesEqual(a: std.json.Value, b: std.json.Value) bool {
    const tag_a = std.meta.activeTag(a);
    const tag_b = std.meta.activeTag(b);
    if (tag_a != tag_b) return false;

    return switch (a) {
        .null => true,
        .bool => |va| va == b.bool,
        .integer => |va| va == b.integer,
        .float => |va| va == b.float,
        .string => |va| std.mem.eql(u8, va, b.string),
        else => false,
    };
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

test "validateAgainstSchema type check passes" {
    const schema = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"type":"string"}
    , .{});
    defer schema.deinit();
    try std.testing.expect(validateAgainstSchema(.{ .string = "hello" }, schema.value));
}

test "validateAgainstSchema type check fails" {
    const schema = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"type":"string"}
    , .{});
    defer schema.deinit();
    try std.testing.expect(!validateAgainstSchema(.{ .integer = 42 }, schema.value));
}

test "validateAgainstSchema required fields pass" {
    const schema = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"type":"object","required":["name"]}
    , .{});
    defer schema.deinit();
    const obj = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"name":"Alice"}
    , .{});
    defer obj.deinit();
    try std.testing.expect(validateAgainstSchema(obj.value, schema.value));
}

test "validateAgainstSchema required field missing fails" {
    const schema = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"type":"object","required":["name","age"]}
    , .{});
    defer schema.deinit();
    const obj = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"name":"Alice"}
    , .{});
    defer obj.deinit();
    try std.testing.expect(!validateAgainstSchema(obj.value, schema.value));
}

test "validateAgainstSchema nested property type validation" {
    const schema = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"type":"object","properties":{"age":{"type":"integer"}}}
    , .{});
    defer schema.deinit();

    const valid = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"age":30}
    , .{});
    defer valid.deinit();
    try std.testing.expect(validateAgainstSchema(valid.value, schema.value));

    const invalid = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"age":"thirty"}
    , .{});
    defer invalid.deinit();
    try std.testing.expect(!validateAgainstSchema(invalid.value, schema.value));
}

test "validateAgainstSchema empty schema passes anything" {
    // Empty schema should pass any value
    const schema = std.json.Value{ .object = std.json.ObjectMap.init(std.testing.allocator) };
    try std.testing.expect(validateAgainstSchema(.{ .string = "hello" }, schema));
    try std.testing.expect(validateAgainstSchema(.{ .integer = 42 }, schema));
    try std.testing.expect(validateAgainstSchema(.null, schema));
}

test "validateAgainstSchema number type accepts integer and float" {
    const schema = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"type":"number"}
    , .{});
    defer schema.deinit();
    try std.testing.expect(validateAgainstSchema(.{ .integer = 42 }, schema.value));
    try std.testing.expect(validateAgainstSchema(.{ .float = 3.14 }, schema.value));
    try std.testing.expect(!validateAgainstSchema(.{ .string = "42" }, schema.value));
}

test "generateObject rejects schema-invalid output" {
    const MockBadModel = struct {
        const Self = @This();

        // Returns valid JSON object that is missing the required "name" field
        const mock_content = [_]provider_types.LanguageModelV3Content{
            .{ .text = .{ .text = "{\"wrong\":\"field\"}" } },
        };

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-bad-json";
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
                .usage = provider_types.LanguageModelV3Usage.initWithTotals(10, 5),
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

    var mock = MockBadModel{};
    var model = provider_types.asLanguageModel(MockBadModel, &mock);

    // Schema requires "name" field, but model returns {"wrong":"field"}
    const schema = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"type":"object","required":["name"]}
    , .{});
    defer schema.deinit();

    const result = generateObject(std.testing.allocator, .{
        .model = &model,
        .prompt = "Generate a person",
        .schema = .{ .json_schema = schema.value },
    });
    try std.testing.expectError(GenerateObjectError.ValidationError, result);
}
