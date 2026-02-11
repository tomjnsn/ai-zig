const std = @import("std");
const ai_sdk_error = @import("ai-sdk-error.zig");

pub const AiSdkError = ai_sdk_error.AiSdkError;
pub const AiSdkErrorInfo = ai_sdk_error.AiSdkErrorInfo;
pub const JsonParseContext = ai_sdk_error.JsonParseContext;

/// JSON Parse Error - thrown when JSON parsing fails
pub const JsonParseError = struct {
    info: AiSdkErrorInfo,

    const Self = @This();

    pub const Options = struct {
        text: []const u8,
        cause: ?*const AiSdkErrorInfo = null,
        message: ?[]const u8 = null,
    };

    /// Create a new JSON parse error
    pub fn init(options: Options) Self {
        const msg = options.message orelse "JSON parsing failed";

        return Self{
            .info = .{
                .kind = .json_parse,
                .message = msg,
                .cause = options.cause,
                .context = .{ .json_parse = .{
                    .text = options.text,
                } },
            },
        };
    }

    /// Get the text that failed to parse
    pub fn text(self: Self) []const u8 {
        if (self.info.context) |ctx| {
            if (ctx == .json_parse) {
                return ctx.json_parse.text;
            }
        }
        return "";
    }

    /// Get the error message
    pub fn message(self: Self) []const u8 {
        return self.info.message;
    }

    /// Convert to AiSdkError
    pub fn toError(self: Self) AiSdkError {
        _ = self;
        return error.JsonParseError;
    }

    /// Format the error with context
    pub fn format(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        const writer = list.writer(allocator);

        try writer.print("JSON parsing failed: {s}\n", .{self.message()});

        const txt = self.text();
        if (txt.len > 0) {
            const max_len = @min(txt.len, 200);
            try writer.print("Text: {s}", .{txt[0..max_len]});
            if (txt.len > 200) {
                try writer.writeAll("...");
            }
            try writer.writeByte('\n');
        }

        return list.toOwnedSlice(allocator);
    }
};

test "JsonParseError creation" {
    const err = JsonParseError.init(.{
        .text = "{invalid json}",
    });

    try std.testing.expectEqualStrings("{invalid json}", err.text());
    try std.testing.expectEqualStrings("JSON parsing failed", err.message());
}
