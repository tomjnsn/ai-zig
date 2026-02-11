const std = @import("std");
const ai_sdk_error = @import("ai-sdk-error.zig");
const json_value = @import("../json-value/index.zig");
const security = @import("../security.zig");

pub const AiSdkError = ai_sdk_error.AiSdkError;
pub const AiSdkErrorInfo = ai_sdk_error.AiSdkErrorInfo;
pub const ApiCallContext = ai_sdk_error.ApiCallContext;

/// API Call Error - thrown when an API request fails
pub const ApiCallError = struct {
    info: AiSdkErrorInfo,

    const Self = @This();

    pub const Options = struct {
        message: []const u8,
        url: []const u8,
        request_body_values: ?json_value.JsonValue = null,
        status_code: ?u16 = null,
        response_headers: ?std.StringHashMap([]const u8) = null,
        response_body: ?[]const u8 = null,
        cause: ?*const AiSdkErrorInfo = null,
        is_retryable: ?bool = null,
        data: ?json_value.JsonValue = null,
    };

    /// Create a new API call error
    pub fn init(options: Options) Self {
        const is_retryable = options.is_retryable orelse ai_sdk_error.isRetryableStatusCode(options.status_code);

        return Self{
            .info = .{
                .kind = .api_call,
                .message = options.message,
                .cause = options.cause,
                .context = .{ .api_call = .{
                    .url = options.url,
                    .request_body_values = options.request_body_values,
                    .status_code = options.status_code,
                    .response_headers = options.response_headers,
                    .response_body = options.response_body,
                    .is_retryable = is_retryable,
                    .data = options.data,
                } },
            },
        };
    }

    /// Get the URL that was called
    pub fn url(self: Self) []const u8 {
        if (self.info.context) |ctx| {
            if (ctx == .api_call) {
                return ctx.api_call.url;
            }
        }
        return "";
    }

    /// Get the HTTP status code
    pub fn statusCode(self: Self) ?u16 {
        if (self.info.context) |ctx| {
            if (ctx == .api_call) {
                return ctx.api_call.status_code;
            }
        }
        return null;
    }

    /// Get the response body
    pub fn responseBody(self: Self) ?[]const u8 {
        if (self.info.context) |ctx| {
            if (ctx == .api_call) {
                return ctx.api_call.response_body;
            }
        }
        return null;
    }

    /// Check if the error is retryable
    pub fn isRetryable(self: Self) bool {
        if (self.info.context) |ctx| {
            if (ctx == .api_call) {
                return ctx.api_call.is_retryable;
            }
        }
        return false;
    }

    /// Get the error message
    pub fn message(self: Self) []const u8 {
        return self.info.message;
    }

    /// Convert to AiSdkError
    pub fn toError(self: Self) AiSdkError {
        _ = self;
        return error.ApiCallError;
    }

    /// Format for display
    pub fn format(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        const writer = list.writer(allocator);

        try writer.print("API call failed: {s}\n", .{self.info.message});
        try writer.print("URL: {s}\n", .{self.url()});

        if (self.statusCode()) |code| {
            try writer.print("Status: {d}\n", .{code});
        }

        if (self.responseBody()) |body| {
            const redacted = try security.redactApiKey(body, allocator);
            defer if (redacted.ptr != body.ptr) allocator.free(redacted);
            const max_len = @min(redacted.len, 500);
            try writer.print("Response: {s}", .{redacted[0..max_len]});
            if (redacted.len > 500) {
                try writer.writeAll("...");
            }
            try writer.writeByte('\n');
        }

        try writer.print("Retryable: {}\n", .{self.isRetryable()});

        return list.toOwnedSlice(allocator);
    }
};

test "ApiCallError creation and properties" {
    const err = ApiCallError.init(.{
        .message = "Request failed",
        .url = "https://api.example.com/v1/chat",
        .status_code = 429,
        .response_body = "Rate limit exceeded",
    });

    try std.testing.expectEqualStrings("Request failed", err.message());
    try std.testing.expectEqualStrings("https://api.example.com/v1/chat", err.url());
    try std.testing.expectEqual(@as(?u16, 429), err.statusCode());
    try std.testing.expect(err.isRetryable());
}

test "ApiCallError not retryable for 400" {
    const err = ApiCallError.init(.{
        .message = "Bad request",
        .url = "https://api.example.com/v1/chat",
        .status_code = 400,
    });

    try std.testing.expect(!err.isRetryable());
}

test "ApiCallError custom retryable override" {
    const err = ApiCallError.init(.{
        .message = "Custom error",
        .url = "https://api.example.com",
        .status_code = 400,
        .is_retryable = true, // Override default
    });

    try std.testing.expect(err.isRetryable());
}

test "format redacts API keys in response body" {
    const allocator = std.testing.allocator;
    const err = ApiCallError.init(.{
        .message = "Auth failed",
        .url = "https://api.example.com/v1/chat",
        .status_code = 401,
        .response_body = "Invalid key: sk-secret123abc",
    });

    const formatted = try err.format(allocator);
    defer allocator.free(formatted);

    // Should contain the error info
    try std.testing.expect(std.mem.indexOf(u8, formatted, "Auth failed") != null);
    // Should NOT contain the raw API key
    try std.testing.expect(std.mem.indexOf(u8, formatted, "sk-secret123abc") == null);
    // Should contain redaction marker
    try std.testing.expect(std.mem.indexOf(u8, formatted, "[REDACTED]") != null);
}
