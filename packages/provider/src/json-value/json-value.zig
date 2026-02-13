const std = @import("std");

/// A JSON value can be a string, number, boolean, object, array, or null.
/// JSON values can be serialized and deserialized using std.json.
pub const JsonValue = union(enum) {
    null,
    bool: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    array: JsonArray,
    object: JsonObject,

    const Self = @This();

    /// Parse a JSON string into a JsonValue using the provided allocator.
    pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Self {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
        defer parsed.deinit();
        return fromStdJson(allocator, parsed.value);
    }

    /// Convert from std.json.Value to our JsonValue type.
    pub fn fromStdJson(allocator: std.mem.Allocator, value: std.json.Value) !Self {
        return switch (value) {
            .null => .null,
            .bool => |b| .{ .bool = b },
            .integer => |i| .{ .integer = i },
            .float => |f| .{ .float = f },
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
            .array => |arr| blk: {
                const result = try allocator.alloc(JsonValue, arr.items.len);
                var initialized: usize = 0;
                errdefer {
                    for (result[0..initialized]) |*item| {
                        item.deinit(allocator);
                    }
                    allocator.free(result);
                }
                for (arr.items, 0..) |item, i| {
                    result[i] = try fromStdJson(allocator, item);
                    initialized = i + 1;
                }
                break :blk .{ .array = result };
            },
            .object => |obj| blk: {
                var result = JsonObject.init(allocator);
                errdefer {
                    var it = result.iterator();
                    while (it.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        var v = entry.value_ptr.*;
                        v.deinit(allocator);
                    }
                    result.deinit();
                }
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    const key = try allocator.dupe(u8, entry.key_ptr.*);
                    errdefer allocator.free(key);
                    const val = try fromStdJson(allocator, entry.value_ptr.*);
                    errdefer {
                        var v = val;
                        v.deinit(allocator);
                    }
                    try result.put(key, val);
                }
                break :blk .{ .object = result };
            },
            .number_string => |s| blk: {
                // Try parsing as integer first, then float
                if (std.fmt.parseInt(i64, s, 10)) |i| {
                    break :blk .{ .integer = i };
                } else |_| {
                    if (std.fmt.parseFloat(f64, s)) |f| {
                        break :blk .{ .float = f };
                    } else |_| {
                        break :blk .{ .string = try allocator.dupe(u8, s) };
                    }
                }
            },
        };
    }

    /// Custom deserialization for std.json.parseFromSlice compatibility.
    /// This allows JsonValue to be used in structs parsed by std.json.parseFromSlice.
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!Self {
        const std_value = try std.json.Value.jsonParse(allocator, source, options);
        return fromStdJson(allocator, std_value) catch return error.OutOfMemory;
    }

    /// Custom serialization for std.json.Stringify compatibility.
    /// This allows JsonValue to be used in structs serialized by std.json.Stringify.
    pub fn jsonStringify(self: Self, jws: anytype) !void {
        switch (self) {
            .null => try jws.write(null),
            .bool => |b| try jws.write(b),
            .integer => |i| try jws.write(i),
            .float => |f| try jws.write(f),
            .string => |s| try jws.write(s),
            .array => |arr| {
                try jws.beginArray();
                for (arr) |item| {
                    try item.jsonStringify(jws);
                }
                try jws.endArray();
            },
            .object => |obj| {
                try jws.beginObject();
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    try jws.objectField(entry.key_ptr.*);
                    try entry.value_ptr.jsonStringify(jws);
                }
                try jws.endObject();
            },
        }
    }

    /// Convert to std.json.Value for serialization.
    pub fn toStdJson(self: Self, allocator: std.mem.Allocator) !std.json.Value {
        return switch (self) {
            .null => .null,
            .bool => |b| .{ .bool = b },
            .integer => |i| .{ .integer = i },
            .float => |f| .{ .float = f },
            .string => |s| .{ .string = s },
            .array => |arr| blk: {
                var result = std.json.Array.init(allocator);
                for (arr) |item| {
                    try result.append(try item.toStdJson(allocator));
                }
                break :blk .{ .array = result };
            },
            .object => |obj| blk: {
                var result = std.json.ObjectMap.init(allocator);
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    try result.put(entry.key_ptr.*, try entry.value_ptr.toStdJson(allocator));
                }
                break :blk .{ .object = result };
            },
        };
    }

    /// Stringify the JSON value.
    pub fn stringify(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        try self.stringifyTo(list.writer(allocator));
        return list.toOwnedSlice(allocator);
    }

    /// Write a JSON-escaped string (with surrounding quotes) to a writer.
    fn writeJsonString(writer: anytype, s: []const u8) !void {
        try writer.writeByte('"');
        for (s) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => {
                    if (c < 0x20) {
                        try writer.print("\\u{x:0>4}", .{c});
                    } else {
                        try writer.writeByte(c);
                    }
                },
            }
        }
        try writer.writeByte('"');
    }

    /// Write the JSON value to a writer.
    pub fn stringifyTo(self: Self, writer: anytype) !void {
        switch (self) {
            .null => try writer.writeAll("null"),
            .bool => |b| try writer.writeAll(if (b) "true" else "false"),
            .integer => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .string => |s| try writeJsonString(writer, s),
            .array => |arr| {
                try writer.writeByte('[');
                for (arr, 0..) |item, i| {
                    if (i > 0) try writer.writeByte(',');
                    try item.stringifyTo(writer);
                }
                try writer.writeByte(']');
            },
            .object => |obj| {
                try writer.writeByte('{');
                var first = true;
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    if (!first) try writer.writeByte(',');
                    first = false;
                    try writeJsonString(writer, entry.key_ptr.*);
                    try writer.writeByte(':');
                    try entry.value_ptr.stringifyTo(writer);
                }
                try writer.writeByte('}');
            },
        }
    }

    /// Get a value from an object by key.
    pub fn get(self: Self, key: []const u8) ?JsonValue {
        return switch (self) {
            .object => |obj| obj.get(key),
            else => null,
        };
    }

    /// Get a value from an array by index.
    pub fn at(self: Self, index: usize) ?JsonValue {
        return switch (self) {
            .array => |arr| if (index < arr.len) arr[index] else null,
            else => null,
        };
    }

    /// Check if this is a null value.
    pub fn isNull(self: Self) bool {
        return self == .null;
    }

    /// Try to get the value as a string.
    pub fn asString(self: Self) ?[]const u8 {
        return switch (self) {
            .string => |s| s,
            else => null,
        };
    }

    /// Try to get the value as a boolean.
    pub fn asBool(self: Self) ?bool {
        return switch (self) {
            .bool => |b| b,
            else => null,
        };
    }

    /// Try to get the value as an integer.
    pub fn asInteger(self: Self) ?i64 {
        return switch (self) {
            .integer => |i| i,
            else => null,
        };
    }

    /// Try to get the value as a float.
    pub fn asFloat(self: Self) ?f64 {
        return switch (self) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            else => null,
        };
    }

    /// Try to get the value as an array.
    pub fn asArray(self: Self) ?JsonArray {
        return switch (self) {
            .array => |arr| arr,
            else => null,
        };
    }

    /// Try to get the value as an object.
    pub fn asObject(self: Self) ?JsonObject {
        return switch (self) {
            .object => |obj| obj,
            else => null,
        };
    }

    /// Free all memory associated with this value.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .array => |arr| {
                for (arr) |*item| {
                    var mutable_item = item.*;
                    mutable_item.deinit(allocator);
                }
                allocator.free(arr);
            },
            .object => |*obj| {
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    var mutable_value = entry.value_ptr.*;
                    mutable_value.deinit(allocator);
                }
                obj.deinit();
            },
            else => {},
        }
    }

    /// Deep clone a JsonValue.
    pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
        return switch (self) {
            .null => .null,
            .bool => |b| .{ .bool = b },
            .integer => |i| .{ .integer = i },
            .float => |f| .{ .float = f },
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
            .array => |arr| blk: {
                const result = try allocator.alloc(JsonValue, arr.len);
                var initialized: usize = 0;
                errdefer {
                    for (result[0..initialized]) |*item| {
                        item.deinit(allocator);
                    }
                    allocator.free(result);
                }
                for (arr, 0..) |item, i| {
                    result[i] = try item.clone(allocator);
                    initialized = i + 1;
                }
                break :blk .{ .array = result };
            },
            .object => |obj| blk: {
                var result = JsonObject.init(allocator);
                errdefer {
                    var it = result.iterator();
                    while (it.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        var v = entry.value_ptr.*;
                        v.deinit(allocator);
                    }
                    result.deinit();
                }
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    const key = try allocator.dupe(u8, entry.key_ptr.*);
                    errdefer allocator.free(key);
                    const val = try entry.value_ptr.clone(allocator);
                    errdefer {
                        var v = val;
                        v.deinit(allocator);
                    }
                    try result.put(key, val);
                }
                break :blk .{ .object = result };
            },
        };
    }
};

/// A JSON object is a map from strings to JSON values.
pub const JsonObject = std.StringHashMap(JsonValue);

/// A JSON array is a slice of JSON values.
pub const JsonArray = []const JsonValue;

/// Helper to create a JsonValue from a Zig value.
pub fn jsonValue(value: anytype) JsonValue {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .null => .null,
        .bool => .{ .bool = value },
        .int, .comptime_int => .{ .integer = @intCast(value) },
        .float, .comptime_float => .{ .float = @floatCast(value) },
        .pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                return .{ .string = value };
            }
            @compileError("Unsupported pointer type for jsonValue");
        },
        else => @compileError("Unsupported type for jsonValue: " ++ @typeName(T)),
    };
}

test "JsonValue parse and stringify" {
    const allocator = std.testing.allocator;

    const json_str =
        \\{"name":"test","count":42,"active":true,"tags":["a","b"]}
    ;

    var value = try JsonValue.parse(allocator, json_str);
    defer value.deinit(allocator);

    try std.testing.expectEqualStrings("test", value.get("name").?.asString().?);
    try std.testing.expectEqual(@as(i64, 42), value.get("count").?.asInteger().?);
    try std.testing.expectEqual(true, value.get("active").?.asBool().?);

    const tags = value.get("tags").?.asArray().?;
    try std.testing.expectEqual(@as(usize, 2), tags.len);
}

test "JsonValue stringifyTo escapes object keys" {
    const allocator = std.testing.allocator;
    var obj = JsonObject.init(allocator);
    defer obj.deinit();

    try obj.put("normal", .{ .integer = 1 });
    try obj.put("has\"quote", .{ .integer = 2 });
    try obj.put("has\\backslash", .{ .integer = 3 });

    const value = JsonValue{ .object = obj };
    const result = try value.stringify(allocator);
    defer allocator.free(result);

    // Keys with special chars must be escaped
    try std.testing.expect(std.mem.indexOf(u8, result, "has\\\"quote") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "has\\\\backslash") != null);
}

test "JsonValue null and primitives" {
    try std.testing.expect(JsonValue.null == .null);
    try std.testing.expectEqual(true, (JsonValue{ .bool = true }).asBool().?);
    try std.testing.expectEqual(@as(i64, 123), (JsonValue{ .integer = 123 }).asInteger().?);
}
