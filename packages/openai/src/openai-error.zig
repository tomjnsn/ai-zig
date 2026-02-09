const std = @import("std");
const json_value = @import("provider").json_value;

/// OpenAI API error data structure
pub const OpenAIErrorData = struct {
    /// The error object
    @"error": ErrorObject,

    pub const ErrorObject = struct {
        /// Error message
        message: []const u8,

        /// Error type (e.g., "invalid_request_error")
        type: ?[]const u8 = null,

        /// Parameter that caused the error
        param: ?[]const u8 = null,

        /// Error code (can be string or number)
        code: ?ErrorCode = null,
    };

    pub const ErrorCode = union(enum) {
        string: []const u8,
        number: i64,

        pub fn toString(self: ErrorCode, allocator: std.mem.Allocator) ![]u8 {
            return switch (self) {
                .string => |s| try allocator.dupe(u8, s),
                .number => |n| try std.fmt.allocPrint(allocator, "{d}", .{n}),
            };
        }
    };

    const Self = @This();

    /// Get the error message
    pub fn getMessage(self: Self) []const u8 {
        return self.@"error".message;
    }

    /// Get the error type
    pub fn getType(self: Self) ?[]const u8 {
        return self.@"error".type;
    }

    /// Get the error code as a string
    pub fn getCodeString(self: Self, allocator: std.mem.Allocator) !?[]u8 {
        if (self.@"error".code) |code| {
            return try code.toString(allocator);
        }
        return null;
    }

    /// Check if this is a rate limit error
    pub fn isRateLimitError(self: Self) bool {
        if (self.@"error".type) |t| {
            return std.mem.eql(u8, t, "rate_limit_error");
        }
        return false;
    }

    /// Check if this is an invalid request error
    pub fn isInvalidRequestError(self: Self) bool {
        if (self.@"error".type) |t| {
            return std.mem.eql(u8, t, "invalid_request_error");
        }
        return false;
    }

    /// Check if this error is retryable
    pub fn isRetryable(self: Self) bool {
        // Rate limit errors are typically retryable
        if (self.isRateLimitError()) return true;

        // Server errors (5xx) are typically retryable
        if (self.@"error".code) |code| {
            switch (code) {
                .number => |n| {
                    if (n >= 500 and n < 600) return true;
                },
                .string => |s| {
                    if (std.mem.eql(u8, s, "server_error")) return true;
                    if (std.mem.eql(u8, s, "service_unavailable")) return true;
                },
            }
        }

        return false;
    }

    /// Parse from JSON value
    pub fn fromJson(value: json_value.JsonValue, allocator: std.mem.Allocator) !Self {
        const error_obj = value.get("error") orelse return error.InvalidErrorFormat;

        const message = error_obj.get("message") orelse return error.InvalidErrorFormat;
        const message_str = message.asString() orelse return error.InvalidErrorFormat;

        var result = Self{
            .@"error" = .{
                .message = try allocator.dupe(u8, message_str),
            },
        };

        if (error_obj.get("type")) |type_val| {
            if (type_val.asString()) |t| {
                result.@"error".type = try allocator.dupe(u8, t);
            }
        }

        if (error_obj.get("param")) |param_val| {
            if (param_val.asString()) |p| {
                result.@"error".param = try allocator.dupe(u8, p);
            }
        }

        if (error_obj.get("code")) |code_val| {
            switch (code_val) {
                .string => |s| result.@"error".code = .{ .string = try allocator.dupe(u8, s) },
                .integer => |n| result.@"error".code = .{ .number = n },
                else => {},
            }
        }

        return result;
    }

    /// Free allocated memory
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.@"error".message);
        if (self.@"error".type) |t| allocator.free(t);
        if (self.@"error".param) |p| allocator.free(p);
        if (self.@"error".code) |code| {
            switch (code) {
                .string => |s| allocator.free(s),
                .number => {},
            }
        }
    }
};

/// OpenAI API error set
pub const OpenAIError = error{
    InvalidErrorFormat,
    RateLimitExceeded,
    InvalidRequest,
    AuthenticationError,
    PermissionDenied,
    NotFound,
    ServerError,
    ServiceUnavailable,
    UnknownError,
};

/// Handle an OpenAI error response
pub fn handleErrorResponse(
    status_code: u16,
    body: ?json_value.JsonValue,
    allocator: std.mem.Allocator,
) OpenAIError {
    // Body is available for future use (e.g., enriching error messages with
    // parsed OpenAIErrorData), but currently we only map status codes.
    _ = body;
    _ = allocator;

    // Map status codes to errors
    return switch (status_code) {
        401 => OpenAIError.AuthenticationError,
        403 => OpenAIError.PermissionDenied,
        404 => OpenAIError.NotFound,
        429 => OpenAIError.RateLimitExceeded,
        500...599 => OpenAIError.ServerError,
        else => OpenAIError.UnknownError,
    };
}

test "OpenAIErrorData getMessage" {
    const error_data = OpenAIErrorData{
        .@"error" = .{
            .message = "Test error message",
            .type = "invalid_request_error",
        },
    };

    try std.testing.expectEqualStrings("Test error message", error_data.getMessage());
    try std.testing.expect(error_data.isInvalidRequestError());
    try std.testing.expect(!error_data.isRateLimitError());
}

test "OpenAIErrorData isRetryable" {
    const rate_limit_error = OpenAIErrorData{
        .@"error" = .{
            .message = "Rate limit exceeded",
            .type = "rate_limit_error",
        },
    };
    try std.testing.expect(rate_limit_error.isRetryable());

    const server_error = OpenAIErrorData{
        .@"error" = .{
            .message = "Server error",
            .code = .{ .number = 500 },
        },
    };
    try std.testing.expect(server_error.isRetryable());

    const invalid_request = OpenAIErrorData{
        .@"error" = .{
            .message = "Invalid request",
            .type = "invalid_request_error",
        },
    };
    try std.testing.expect(!invalid_request.isRetryable());
}
