const std = @import("std");

/// Enhanced error details for API responses, providing richer information
/// for debugging and retry logic. Wraps status codes, provider info,
/// request IDs, and retry-after hints.
pub const ApiErrorDetails = struct {
    /// HTTP status code
    status_code: u16,

    /// Human-readable error message
    message: []const u8,

    /// Provider name (e.g., "openai", "anthropic")
    provider: []const u8,

    /// Provider-specific error code (e.g., "rate_limit_exceeded")
    code: ?[]const u8 = null,

    /// Request ID from the provider (for support tickets)
    request_id: ?[]const u8 = null,

    /// Retry-After header value in seconds (parsed from response)
    retry_after_seconds: ?u32 = null,

    /// Check if this error is retryable based on status code
    pub fn isRetryable(self: *const ApiErrorDetails) bool {
        return self.status_code == 408 or // request timeout
            self.status_code == 409 or // conflict
            self.status_code == 429 or // too many requests
            self.status_code >= 500; // server error
    }

    /// Get the suggested retry delay in milliseconds.
    /// Uses retry_after_seconds if available, otherwise returns a default
    /// based on the status code.
    pub fn suggestedRetryDelayMs(self: *const ApiErrorDetails) u64 {
        // Use retry-after header if available
        if (self.retry_after_seconds) |seconds| {
            return @as(u64, seconds) * 1000;
        }

        // Default delays based on status code
        if (self.status_code == 429) return 5000; // rate limit: 5s
        if (self.status_code >= 500) return 1000; // server error: 1s
        if (self.status_code == 408) return 2000; // timeout: 2s

        return 0; // non-retryable, no delay
    }

    /// Format error details for display
    pub fn format(self: *const ApiErrorDetails, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.array_list.Managed(u8).init(allocator);
        errdefer list.deinit();
        const writer = list.writer();

        try writer.print("[{s}] {d}: {s}", .{ self.provider, self.status_code, self.message });

        if (self.code) |code| {
            try writer.print(" (code: {s})", .{code});
        }

        if (self.request_id) |req_id| {
            try writer.print(" [request_id: {s}]", .{req_id});
        }

        if (self.retry_after_seconds) |seconds| {
            try writer.print(" [retry_after: {d}s]", .{seconds});
        }

        return list.toOwnedSlice();
    }

    /// Parse a Retry-After header value (seconds or HTTP-date).
    /// Only supports seconds format currently.
    pub fn parseRetryAfter(value: []const u8) ?u32 {
        // Try parsing as integer seconds
        return std.fmt.parseInt(u32, std.mem.trim(u8, value, " "), 10) catch null;
    }

    /// Create from response headers, extracting retry-after and request-id
    pub fn fromResponse(
        status_code: u16,
        message: []const u8,
        provider: []const u8,
        headers: ?std.StringHashMap([]const u8),
    ) ApiErrorDetails {
        var details = ApiErrorDetails{
            .status_code = status_code,
            .message = message,
            .provider = provider,
        };

        if (headers) |hdrs| {
            // Try common request-id headers
            if (hdrs.get("x-request-id")) |req_id| {
                details.request_id = req_id;
            } else if (hdrs.get("request-id")) |req_id| {
                details.request_id = req_id;
            }

            // Parse retry-after header
            if (hdrs.get("retry-after")) |retry_val| {
                details.retry_after_seconds = parseRetryAfter(retry_val);
            }
        }

        return details;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "isRetryable returns true for 429" {
    const details = ApiErrorDetails{
        .status_code = 429,
        .message = "Rate limit exceeded",
        .provider = "openai",
    };
    try std.testing.expect(details.isRetryable());
}

test "isRetryable returns true for 5xx" {
    const details_500 = ApiErrorDetails{
        .status_code = 500,
        .message = "Internal server error",
        .provider = "anthropic",
    };
    try std.testing.expect(details_500.isRetryable());

    const details_503 = ApiErrorDetails{
        .status_code = 503,
        .message = "Service unavailable",
        .provider = "anthropic",
    };
    try std.testing.expect(details_503.isRetryable());
}

test "isRetryable returns true for 408 and 409" {
    const details_408 = ApiErrorDetails{
        .status_code = 408,
        .message = "Request timeout",
        .provider = "google",
    };
    try std.testing.expect(details_408.isRetryable());

    const details_409 = ApiErrorDetails{
        .status_code = 409,
        .message = "Conflict",
        .provider = "google",
    };
    try std.testing.expect(details_409.isRetryable());
}

test "isRetryable returns false for 4xx (non-retryable)" {
    const details_400 = ApiErrorDetails{
        .status_code = 400,
        .message = "Bad request",
        .provider = "openai",
    };
    try std.testing.expect(!details_400.isRetryable());

    const details_401 = ApiErrorDetails{
        .status_code = 401,
        .message = "Unauthorized",
        .provider = "openai",
    };
    try std.testing.expect(!details_401.isRetryable());

    const details_404 = ApiErrorDetails{
        .status_code = 404,
        .message = "Not found",
        .provider = "openai",
    };
    try std.testing.expect(!details_404.isRetryable());
}

test "suggestedRetryDelayMs uses retry_after header" {
    const details = ApiErrorDetails{
        .status_code = 429,
        .message = "Rate limited",
        .provider = "openai",
        .retry_after_seconds = 30,
    };
    try std.testing.expectEqual(@as(u64, 30000), details.suggestedRetryDelayMs());
}

test "suggestedRetryDelayMs returns default for 429 without header" {
    const details = ApiErrorDetails{
        .status_code = 429,
        .message = "Rate limited",
        .provider = "openai",
    };
    try std.testing.expectEqual(@as(u64, 5000), details.suggestedRetryDelayMs());
}

test "suggestedRetryDelayMs returns default for 5xx" {
    const details = ApiErrorDetails{
        .status_code = 500,
        .message = "Server error",
        .provider = "anthropic",
    };
    try std.testing.expectEqual(@as(u64, 1000), details.suggestedRetryDelayMs());
}

test "suggestedRetryDelayMs returns 0 for non-retryable" {
    const details = ApiErrorDetails{
        .status_code = 400,
        .message = "Bad request",
        .provider = "openai",
    };
    try std.testing.expectEqual(@as(u64, 0), details.suggestedRetryDelayMs());
}

test "parseRetryAfter parses integer seconds" {
    try std.testing.expectEqual(@as(?u32, 30), ApiErrorDetails.parseRetryAfter("30"));
    try std.testing.expectEqual(@as(?u32, 1), ApiErrorDetails.parseRetryAfter("1"));
    try std.testing.expectEqual(@as(?u32, 120), ApiErrorDetails.parseRetryAfter(" 120 "));
}

test "parseRetryAfter returns null for invalid values" {
    try std.testing.expectEqual(@as(?u32, null), ApiErrorDetails.parseRetryAfter("not-a-number"));
    try std.testing.expectEqual(@as(?u32, null), ApiErrorDetails.parseRetryAfter(""));
}

test "format produces readable output" {
    const allocator = std.testing.allocator;
    const details = ApiErrorDetails{
        .status_code = 429,
        .message = "Rate limit exceeded",
        .provider = "openai",
        .code = "rate_limit_exceeded",
        .request_id = "req-abc123",
        .retry_after_seconds = 30,
    };

    const formatted = try details.format(allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "[openai]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "429") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "Rate limit exceeded") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "rate_limit_exceeded") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "req-abc123") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "30s") != null);
}

test "format minimal output" {
    const allocator = std.testing.allocator;
    const details = ApiErrorDetails{
        .status_code = 400,
        .message = "Bad request",
        .provider = "anthropic",
    };

    const formatted = try details.format(allocator);
    defer allocator.free(formatted);

    try std.testing.expectEqualStrings("[anthropic] 400: Bad request", formatted);
}

test "fromResponse extracts headers" {
    var headers = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer headers.deinit();
    try headers.put("x-request-id", "req-xyz789");
    try headers.put("retry-after", "60");

    const details = ApiErrorDetails.fromResponse(
        429,
        "Too many requests",
        "openai",
        headers,
    );

    try std.testing.expectEqual(@as(u16, 429), details.status_code);
    try std.testing.expectEqualStrings("Too many requests", details.message);
    try std.testing.expectEqualStrings("openai", details.provider);
    try std.testing.expectEqualStrings("req-xyz789", details.request_id.?);
    try std.testing.expectEqual(@as(?u32, 60), details.retry_after_seconds);
}

test "fromResponse works without headers" {
    const details = ApiErrorDetails.fromResponse(
        500,
        "Internal error",
        "google",
        null,
    );

    try std.testing.expectEqual(@as(u16, 500), details.status_code);
    try std.testing.expect(details.request_id == null);
    try std.testing.expect(details.retry_after_seconds == null);
}
