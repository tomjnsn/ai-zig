const std = @import("std");
const json_value = @import("provider").json_value;
const errors = @import("provider").errors;

/// Result of parsing JSON
pub const ParseResult = union(enum) {
    success: json_value.JsonValue,
    failure: ParseError,
};

/// JSON parse error
pub const ParseError = struct {
    message: []const u8,
    position: ?usize = null,
};

/// Parse a JSON string into a JsonValue.
/// Returns a ParseResult indicating success or failure.
pub fn safeParseJson(
    text: []const u8,
    allocator: std.mem.Allocator,
) ParseResult {
    // Handle empty input
    if (text.len == 0 or std.mem.trim(u8, text, " \t\n\r").len == 0) {
        return .{ .failure = .{ .message = "Empty JSON string" } };
    }

    // Parse using std.json
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch |err| {
        const message: []const u8 = switch (err) {
            error.InvalidCharacter => "Unexpected character in JSON",
            error.InvalidNumber => "Invalid number in JSON",
            error.Overflow => "Number overflow in JSON",
            error.InvalidEnumTag => "Invalid enum tag",
            error.DuplicateField => "Duplicate field in JSON object",
            error.UnknownField => "Unknown field in JSON",
            error.MissingField => "Missing required field in JSON",
            error.LengthMismatch => "Array length mismatch",
            error.SyntaxError => "JSON syntax error",
            error.UnexpectedEndOfInput => "Unexpected end of JSON input",
            else => "Failed to parse JSON",
        };
        return .{ .failure = .{ .message = message } };
    };
    defer parsed.deinit();

    // Convert to our JsonValue type
    const result = json_value.JsonValue.fromStdJson(allocator, parsed.value) catch {
        return .{ .failure = .{ .message = "Failed to convert parsed JSON" } };
    };

    return .{ .success = result };
}

/// Parse JSON and throw on error
pub fn parseJson(
    text: []const u8,
    allocator: std.mem.Allocator,
) !json_value.JsonValue {
    const result = safeParseJson(text, allocator);
    switch (result) {
        .success => |value| return value,
        .failure => |err| {
            std.log.err("JSON parse error: {s}", .{err.message});
            return error.JsonParseError;
        },
    }
}

/// Check if a string is valid JSON without fully parsing it
pub fn isParsableJson(allocator: std.mem.Allocator, text: []const u8) bool {
    // Quick validation using std.json scanner
    var scanner = std.json.Scanner.initCompleteInput(allocator, text);
    defer scanner.deinit();

    while (true) {
        const token = scanner.next() catch return false;
        if (token == .end_of_document) break;
    }
    return true;
}

/// Safe JSON parse with type extraction helpers
pub const TypedParseResult = struct {
    value: json_value.JsonValue,
    raw: []const u8,

    /// Get a string field from the parsed JSON object
    pub fn getString(self: TypedParseResult, key: []const u8) ?[]const u8 {
        if (self.value.get(key)) |v| {
            return v.asString();
        }
        return null;
    }

    /// Get an integer field from the parsed JSON object
    pub fn getInt(self: TypedParseResult, key: []const u8) ?i64 {
        if (self.value.get(key)) |v| {
            return v.asInteger();
        }
        return null;
    }

    /// Get a boolean field from the parsed JSON object
    pub fn getBool(self: TypedParseResult, key: []const u8) ?bool {
        if (self.value.get(key)) |v| {
            return v.asBool();
        }
        return null;
    }

    /// Get an array field from the parsed JSON object
    pub fn getArray(self: TypedParseResult, key: []const u8) ?[]const json_value.JsonValue {
        if (self.value.get(key)) |v| {
            return v.asArray();
        }
        return null;
    }

    /// Get a nested object field from the parsed JSON object
    pub fn getObject(self: TypedParseResult, key: []const u8) ?json_value.JsonObject {
        if (self.value.get(key)) |v| {
            return v.asObject();
        }
        return null;
    }
};

/// Parse JSON and return a typed result with helpers
pub fn parseJsonTyped(
    text: []const u8,
    allocator: std.mem.Allocator,
) !TypedParseResult {
    const result = safeParseJson(text, allocator);
    switch (result) {
        .success => |value| return .{
            .value = value,
            .raw = text,
        },
        .failure => return error.JsonParseError,
    }
}

/// Extract a specific field from JSON without full parsing.
/// Returns a newly allocated string that the caller must free.
pub fn extractJsonField(
    text: []const u8,
    field_name: []const u8,
    allocator: std.mem.Allocator,
) ?[]const u8 {
    // Simple approach: parse fully and extract
    const result = safeParseJson(text, allocator);
    switch (result) {
        .success => |value| {
            defer {
                var v = value;
                v.deinit(allocator);
            }
            if (value.get(field_name)) |field_value| {
                switch (field_value) {
                    .string => |s| return allocator.dupe(u8, s) catch null,
                    else => {
                        // Try to stringify the value
                        return field_value.stringify(allocator) catch null;
                    },
                }
            }
            return null;
        },
        .failure => return null,
    }
}

test "safeParseJson valid JSON" {
    const allocator = std.testing.allocator;

    const result = safeParseJson(
        \\{"name": "test", "count": 42}
    , allocator);

    switch (result) {
        .success => |value| {
            defer {
                var v = value;
                v.deinit(allocator);
            }
            try std.testing.expectEqualStrings("test", value.get("name").?.asString().?);
            try std.testing.expectEqual(@as(i64, 42), value.get("count").?.asInteger().?);
        },
        .failure => unreachable,
    }
}

test "safeParseJson invalid JSON" {
    const allocator = std.testing.allocator;

    const result = safeParseJson("{invalid}", allocator);

    switch (result) {
        .success => unreachable,
        .failure => |err| {
            try std.testing.expect(err.message.len > 0);
        },
    }
}

test "safeParseJson empty string" {
    const allocator = std.testing.allocator;

    const result = safeParseJson("", allocator);

    switch (result) {
        .success => unreachable,
        .failure => |err| {
            try std.testing.expectEqualStrings("Empty JSON string", err.message);
        },
    }
}

test "isParsableJson" {
    const allocator = std.testing.allocator;
    try std.testing.expect(isParsableJson(allocator, "{}"));
    try std.testing.expect(isParsableJson(allocator, "{\"key\": \"value\"}"));
    try std.testing.expect(isParsableJson(allocator, "[1, 2, 3]"));
    try std.testing.expect(isParsableJson(allocator, "null"));
    try std.testing.expect(!isParsableJson(allocator, "{invalid}"));
    try std.testing.expect(!isParsableJson(allocator, ""));
}

test "parseJson success" {
    const allocator = std.testing.allocator;

    const value = try parseJson("{\"status\": \"ok\"}", allocator);
    defer {
        var v = value;
        v.deinit(allocator);
    }

    try std.testing.expectEqualStrings("ok", value.get("status").?.asString().?);
}

test "parseJson failure" {
    const allocator = std.testing.allocator;
    const result = parseJson("{invalid json}", allocator);
    try std.testing.expectError(error.JsonParseError, result);
}

test "safeParseJson with whitespace" {
    const allocator = std.testing.allocator;

    const result = safeParseJson("   \n\t  ", allocator);
    switch (result) {
        .success => unreachable,
        .failure => |err| {
            try std.testing.expectEqualStrings("Empty JSON string", err.message);
        },
    }
}

test "safeParseJson complex object" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "user": {
        \\    "name": "Alice",
        \\    "age": 30,
        \\    "active": true
        \\  },
        \\  "items": [1, 2, 3],
        \\  "count": 42
        \\}
    ;

    const result = safeParseJson(json, allocator);
    switch (result) {
        .success => |value| {
            defer {
                var v = value;
                v.deinit(allocator);
            }
            try std.testing.expectEqual(@as(i64, 42), value.get("count").?.asInteger().?);
        },
        .failure => unreachable,
    }
}

test "safeParseJson array" {
    const allocator = std.testing.allocator;

    const result = safeParseJson("[1, 2, 3, 4, 5]", allocator);
    switch (result) {
        .success => |value| {
            defer {
                var v = value;
                v.deinit(allocator);
            }
            const arr = value.asArray().?;
            try std.testing.expectEqual(@as(usize, 5), arr.len);
        },
        .failure => unreachable,
    }
}

test "safeParseJson primitives" {
    const allocator = std.testing.allocator;

    // Test null
    const null_result = safeParseJson("null", allocator);
    switch (null_result) {
        .success => |value| {
            defer {
                var v = value;
                v.deinit(allocator);
            }
            try std.testing.expect(value.isNull());
        },
        .failure => unreachable,
    }

    // Test boolean
    const bool_result = safeParseJson("true", allocator);
    switch (bool_result) {
        .success => |value| {
            defer {
                var v = value;
                v.deinit(allocator);
            }
            try std.testing.expectEqual(true, value.asBool().?);
        },
        .failure => unreachable,
    }

    // Test number
    const num_result = safeParseJson("123.45", allocator);
    switch (num_result) {
        .success => |value| {
            defer {
                var v = value;
                v.deinit(allocator);
            }
            try std.testing.expect(value.asFloat() != null or value.asInteger() != null);
        },
        .failure => unreachable,
    }
}

test "parseJsonTyped helpers" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "name": "test",
        \\  "count": 42,
        \\  "active": true,
        \\  "tags": ["a", "b", "c"]
        \\}
    ;

    const result = try parseJsonTyped(json, allocator);
    defer {
        var v = result.value;
        v.deinit(allocator);
    }

    try std.testing.expectEqualStrings("test", result.getString("name").?);
    try std.testing.expectEqual(@as(i64, 42), result.getInt("count").?);
    try std.testing.expectEqual(true, result.getBool("active").?);
    try std.testing.expect(result.getArray("tags") != null);
    try std.testing.expect(result.getString("nonexistent") == null);
}

test "extractJsonField string" {
    const allocator = std.testing.allocator;

    const json = "{\"message\": \"hello world\"}";
    const result = extractJsonField(json, "message", allocator);
    defer if (result) |r| allocator.free(r);

    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("hello world", result.?);
}

test "extractJsonField missing" {
    const allocator = std.testing.allocator;

    const json = "{\"other\": \"value\"}";
    const result = extractJsonField(json, "missing", allocator);

    try std.testing.expect(result == null);
}

test "extractJsonField invalid json" {
    const allocator = std.testing.allocator;

    const result = extractJsonField("{invalid}", "field", allocator);
    try std.testing.expect(result == null);
}

test "isParsableJson edge cases" {
    const allocator = std.testing.allocator;
    // Valid JSON types
    try std.testing.expect(isParsableJson(allocator, "true"));
    try std.testing.expect(isParsableJson(allocator, "false"));
    try std.testing.expect(isParsableJson(allocator, "123"));
    try std.testing.expect(isParsableJson(allocator, "-456.789"));
    try std.testing.expect(isParsableJson(allocator, "\"string\""));
    try std.testing.expect(isParsableJson(allocator, "[]"));

    // Invalid JSON
    try std.testing.expect(!isParsableJson(allocator, "undefined"));
    try std.testing.expect(!isParsableJson(allocator, "{"));
    try std.testing.expect(!isParsableJson(allocator, "}"));
    try std.testing.expect(!isParsableJson(allocator, "[,]"));
    try std.testing.expect(!isParsableJson(allocator, "{,}"));
}
