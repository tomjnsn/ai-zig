const std = @import("std");

/// Mistral API error data
pub const MistralErrorData = struct {
    /// Object type (always "error")
    object: []const u8 = "error",

    /// Error message
    message: []const u8,

    /// Error type
    type: []const u8,

    /// Parameter that caused the error (nullable)
    param: ?[]const u8 = null,

    /// Error code (nullable)
    code: ?[]const u8 = null,
};

/// Parse Mistral error from JSON
/// Caller must free the returned strings using freeMistralError
pub fn parseMistralError(allocator: std.mem.Allocator, json_str: []const u8) !MistralErrorData {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    // Duplicate strings since parsed data will be freed
    const object_str = if (obj.get("object")) |v| try allocator.dupe(u8, v.string) else try allocator.dupe(u8, "error");
    errdefer allocator.free(object_str);
    const message_str = if (obj.get("message")) |v| try allocator.dupe(u8, v.string) else try allocator.dupe(u8, "Unknown error");
    errdefer allocator.free(message_str);
    const type_str = if (obj.get("type")) |v| try allocator.dupe(u8, v.string) else try allocator.dupe(u8, "unknown");
    errdefer allocator.free(type_str);
    const param_str: ?[]const u8 = if (obj.get("param")) |v| if (v == .string) try allocator.dupe(u8, v.string) else null else null;
    errdefer if (param_str) |p| allocator.free(p);
    const code_str: ?[]const u8 = if (obj.get("code")) |v| if (v == .string) try allocator.dupe(u8, v.string) else null else null;

    return MistralErrorData{
        .object = object_str,
        .message = message_str,
        .type = type_str,
        .param = param_str,
        .code = code_str,
    };
}

/// Free MistralErrorData strings allocated by parseMistralError
pub fn freeMistralError(allocator: std.mem.Allocator, err: MistralErrorData) void {
    allocator.free(err.object);
    allocator.free(err.message);
    allocator.free(err.type);
    if (err.param) |p| allocator.free(p);
    if (err.code) |c| allocator.free(c);
}

/// Format Mistral error as string
pub fn formatMistralError(allocator: std.mem.Allocator, err: MistralErrorData) ![]const u8 {
    if (err.code) |code| {
        return std.fmt.allocPrint(allocator, "Mistral API error [{s}]: {s}", .{ code, err.message });
    }
    return std.fmt.allocPrint(allocator, "Mistral API error: {s}", .{err.message});
}

test "parseMistralError" {
    const allocator = std.testing.allocator;
    const json =
        \\{"object":"error","message":"Invalid API key","type":"authentication_error","param":null,"code":"invalid_api_key"}
    ;
    const err = try parseMistralError(allocator, json);
    defer freeMistralError(allocator, err);
    try std.testing.expectEqualStrings("error", err.object);
    try std.testing.expectEqualStrings("Invalid API key", err.message);
    try std.testing.expectEqualStrings("authentication_error", err.type);
}
