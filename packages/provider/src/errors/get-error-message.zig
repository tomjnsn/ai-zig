const std = @import("std");
const ai_sdk_error = @import("ai-sdk-error.zig");

/// Get error message from an error
pub fn getErrorMessage(err: anyerror) []const u8 {
    return @errorName(err);
}

/// Get error message from an AiSdkErrorInfo
pub fn getErrorInfoMessage(info: ai_sdk_error.AiSdkErrorInfo) []const u8 {
    return info.message;
}

/// Get error message from optional, returning "unknown error" if null
pub fn getErrorMessageOrUnknown(err: ?anyerror) []const u8 {
    if (err) |e| {
        return getErrorMessage(e);
    }
    return "unknown error";
}

/// Format an error with its cause chain
pub fn formatErrorChain(info: ai_sdk_error.AiSdkErrorInfo, allocator: std.mem.Allocator) ![]const u8 {
    var list = std.ArrayList(u8).empty;
    errdefer list.deinit(allocator);
    const writer = list.writer(allocator);

    try writer.print("{s}: {s}", .{ info.name(), info.message });

    var current_cause = info.cause;
    var depth: usize = 0;
    const max_depth = 10; // Prevent infinite loops

    while (current_cause) |cause| : (depth += 1) {
        if (depth >= max_depth) {
            try writer.writeAll("\n  ... (cause chain truncated)");
            break;
        }
        try writer.print("\n  Caused by: {s}", .{cause.message});
        current_cause = cause.cause;
    }

    return list.toOwnedSlice(allocator);
}

test "getErrorMessage" {
    const err = error.OutOfMemory;
    try std.testing.expectEqualStrings("OutOfMemory", getErrorMessage(err));
}

test "getErrorMessageOrUnknown" {
    try std.testing.expectEqualStrings("unknown error", getErrorMessageOrUnknown(null));
    try std.testing.expectEqualStrings("OutOfMemory", getErrorMessageOrUnknown(error.OutOfMemory));
}

test "formatErrorChain" {
    const allocator = std.testing.allocator;

    const cause = ai_sdk_error.AiSdkErrorInfo{
        .kind = .json_parse,
        .message = "Unexpected token",
    };

    const info = ai_sdk_error.AiSdkErrorInfo{
        .kind = .api_call,
        .message = "Failed to parse response",
        .cause = &cause,
    };

    const formatted = try formatErrorChain(info, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "AI_APICallError") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "Caused by") != null);
}
