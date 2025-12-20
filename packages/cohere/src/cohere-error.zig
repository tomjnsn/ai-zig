const std = @import("std");

/// Cohere API error data
pub const CohereErrorData = struct {
    /// Error message
    message: []const u8,
};

/// Parse Cohere error from JSON
pub fn parseCohereError(allocator: std.mem.Allocator, json_str: []const u8) !CohereErrorData {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    const message = if (obj.get("message")) |v| v.string else "Unknown error";
    return CohereErrorData{
        .message = try allocator.dupe(u8, message),
    };
}

/// Format Cohere error as string
pub fn formatCohereError(allocator: std.mem.Allocator, err: CohereErrorData) ![]const u8 {
    return std.fmt.allocPrint(allocator, "Cohere API error: {s}", .{err.message});
}

test "parseCohereError" {
    const allocator = std.testing.allocator;
    const json =
        \\{"message":"Invalid API key"}
    ;
    const err = try parseCohereError(allocator, json);
    defer allocator.free(err.message);
    try std.testing.expectEqualStrings("Invalid API key", err.message);
}
