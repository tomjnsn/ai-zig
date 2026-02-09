const std = @import("std");
const testing = std.testing;
const ai = @import("ai");

// Integration tests for tool functionality

test "Tool creation" {
    // Use arena to avoid manual recursive deinit of nested json
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a simple parameter schema
    var params = std.json.ObjectMap.init(allocator);

    try params.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);
    var location = std.json.ObjectMap.init(allocator);
    try location.put("type", std.json.Value{ .string = "string" });
    try location.put("description", std.json.Value{ .string = "The city and state" });
    try properties.put("location", std.json.Value{ .object = location });
    try params.put("properties", std.json.Value{ .object = properties });

    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "location" });
    try params.put("required", std.json.Value{ .array = required });

    const tool = ai.Tool.create(.{
        .name = "get_weather",
        .description = "Get the current weather for a location",
        .parameters = std.json.Value{ .object = params },
    });

    try testing.expectEqualStrings("get_weather", tool.name);
    try testing.expectEqualStrings("Get the current weather for a location", tool.description.?);
}

test "ApprovalRequirement variants" {
    // Test always approval
    const always = ai.ApprovalRequirement.always;
    try testing.expect(always == .always);

    // Test never approval
    const never = ai.ApprovalRequirement.never;
    try testing.expect(never == .never);
}

test "ToolExecutionContext initialization" {
    const context = ai.ToolExecutionContext{
        .messages = null,
        .abort_signal = null,
        .user_context = null,
    };

    try testing.expect(context.messages == null);
    try testing.expect(context.abort_signal == null);
    try testing.expect(context.user_context == null);
}

test "ToolExecutionResult success" {
    const result = ai.ToolExecutionResult{
        .success = std.json.Value{ .string = "sunny" },
    };

    switch (result) {
        .success => |v| {
            try testing.expectEqualStrings("sunny", v.string);
        },
        .@"error" => {
            try testing.expect(false);
        },
    }
}

test "ToolExecutionResult error" {
    const result = ai.ToolExecutionResult{
        .@"error" = .{
            .message = "Location not found",
            .code = "NOT_FOUND",
        },
    };

    switch (result) {
        .success => {
            try testing.expect(false);
        },
        .@"error" => |e| {
            try testing.expectEqualStrings("Location not found", e.message);
            try testing.expectEqualStrings("NOT_FOUND", e.code.?);
        },
    }
}
