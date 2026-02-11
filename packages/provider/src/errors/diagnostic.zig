const std = @import("std");

/// Stack-allocated diagnostic for rich error context alongside Zig error unions.
///
/// Follows the idiomatic Zig "Diagnostics out-parameter" pattern (same approach
/// as `std.json.Scanner.Diagnostics`). Callers opt in by passing a pointer via
/// the `error_diagnostic` field on Options structs.
///
/// No allocator required. No `deinit()` needed. Bounded buffers truncate
/// oversized messages gracefully.
///
/// ## Usage
/// ```zig
/// var diag: ErrorDiagnostic = .{};
/// const result = generateText(allocator, .{
///     .model = model,
///     .prompt = "Hello",
///     .error_diagnostic = &diag,
/// }) catch |err| {
///     if (diag.status_code) |code| {
///         std.log.err("HTTP {d}: {s}", .{ code, diag.message() orelse "unknown" });
///     }
///     return err;
/// };
/// ```
pub const ErrorDiagnostic = struct {
    /// HTTP status code from the API response (e.g., 401, 429, 500).
    status_code: ?u16 = null,

    /// Whether the error is retryable (based on status code or error kind).
    is_retryable: bool = false,

    /// Classification of the error.
    kind: Kind = .none,

    /// Provider name (e.g., "openai", "anthropic"). Static string, not owned.
    provider: ?[]const u8 = null,

    /// Internal message buffer.
    _message: [message_capacity]u8 = undefined,
    _message_len: u16 = 0,

    /// Internal response body buffer.
    _response_body: [response_body_capacity]u8 = undefined,
    _response_body_len: u16 = 0,

    pub const message_capacity = 1024;
    pub const response_body_capacity = 2048;

    pub const Kind = enum {
        none,
        api_call,
        authentication,
        rate_limit,
        server_error,
        invalid_request,
        not_found,
        network,
        timeout,
        invalid_response,
    };

    /// Returns the error message, or null if none was set.
    pub fn message(self: *const ErrorDiagnostic) ?[]const u8 {
        if (self._message_len == 0) return null;
        return self._message[0..self._message_len];
    }

    /// Returns the response body excerpt, or null if none was set.
    pub fn responseBody(self: *const ErrorDiagnostic) ?[]const u8 {
        if (self._response_body_len == 0) return null;
        return self._response_body[0..self._response_body_len];
    }

    /// Set the error message, truncating to buffer capacity.
    pub fn setMessage(self: *ErrorDiagnostic, msg: []const u8) void {
        const len: u16 = @intCast(@min(msg.len, message_capacity));
        @memcpy(self._message[0..len], msg[0..len]);
        self._message_len = len;
    }

    /// Set the response body excerpt, truncating to buffer capacity.
    pub fn setResponseBody(self: *ErrorDiagnostic, body: []const u8) void {
        const len: u16 = @intCast(@min(body.len, response_body_capacity));
        @memcpy(self._response_body[0..len], body[0..len]);
        self._response_body_len = len;
    }

    /// Classify the error kind from the HTTP status code and set retryability.
    pub fn classifyStatus(self: *ErrorDiagnostic) void {
        if (self.status_code) |code| {
            self.kind = switch (code) {
                400 => .invalid_request,
                401, 403 => .authentication,
                404 => .not_found,
                408 => .timeout,
                429 => .rate_limit,
                500...599 => .server_error,
                else => .api_call,
            };
            self.is_retryable = (code == 408 or code == 429 or code >= 500);
        }
    }

    /// Populate from a non-2xx HTTP response. Attempts to extract an error
    /// message from common JSON error formats in the response body.
    pub fn populateFromResponse(self: *ErrorDiagnostic, status_code: u16, body: []const u8) void {
        self.status_code = status_code;
        self.setResponseBody(body);
        self.classifyStatus();

        // Try to extract a message from JSON error response body.
        // Sets the message directly (before parsed JSON is freed).
        if (!self.extractAndSetJsonErrorMessage(body)) {
            self.setMessage(statusToMessage(status_code));
        }
    }

    /// Try to extract an error message from a JSON response body and set it.
    /// Supports common formats:
    ///   {"error": {"message": "..."}}  (OpenAI, Anthropic)
    ///   {"error": "..."}               (simple)
    ///   {"message": "..."}             (some providers)
    /// Returns true if a message was found and set.
    fn extractAndSetJsonErrorMessage(self: *ErrorDiagnostic, body: []const u8) bool {
        var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, body, .{}) catch return false;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return false;

        // {"error": {"message": "..."}}
        if (root.object.get("error")) |err_val| {
            if (err_val == .object) {
                if (err_val.object.get("message")) |msg| {
                    if (msg == .string) {
                        self.setMessage(msg.string);
                        return true;
                    }
                }
            }
            // {"error": "string message"}
            if (err_val == .string) {
                self.setMessage(err_val.string);
                return true;
            }
        }
        // {"message": "..."}
        if (root.object.get("message")) |msg| {
            if (msg == .string) {
                self.setMessage(msg.string);
                return true;
            }
        }
        return false;
    }

    fn statusToMessage(code: u16) []const u8 {
        return switch (code) {
            400 => "Bad Request",
            401 => "Unauthorized",
            403 => "Forbidden",
            404 => "Not Found",
            408 => "Request Timeout",
            429 => "Too Many Requests",
            500 => "Internal Server Error",
            502 => "Bad Gateway",
            503 => "Service Unavailable",
            504 => "Gateway Timeout",
            else => "API Error",
        };
    }

    /// Format a human-readable error summary.
    pub fn format(self: *const ErrorDiagnostic, writer: anytype) !void {
        if (self.provider) |p| {
            try writer.print("[{s}] ", .{p});
        }
        try writer.print("{s}", .{@tagName(self.kind)});
        if (self.status_code) |code| {
            try writer.print(" (HTTP {d})", .{code});
        }
        if (self.message()) |msg| {
            try writer.print(": {s}", .{msg});
        }
        if (self.is_retryable) {
            try writer.writeAll(" [retryable]");
        }
    }
};

// --- Tests ---

test "ErrorDiagnostic default state" {
    const diag: ErrorDiagnostic = .{};
    try std.testing.expect(diag.status_code == null);
    try std.testing.expect(!diag.is_retryable);
    try std.testing.expect(diag.kind == .none);
    try std.testing.expect(diag.provider == null);
    try std.testing.expect(diag.message() == null);
    try std.testing.expect(diag.responseBody() == null);
}

test "ErrorDiagnostic setMessage and message" {
    var diag: ErrorDiagnostic = .{};
    diag.setMessage("Rate limit exceeded");
    try std.testing.expectEqualStrings("Rate limit exceeded", diag.message().?);
}

test "ErrorDiagnostic setMessage truncates long messages" {
    var diag: ErrorDiagnostic = .{};
    const long_msg = "x" ** (ErrorDiagnostic.message_capacity + 100);
    diag.setMessage(long_msg);
    try std.testing.expectEqual(@as(u16, ErrorDiagnostic.message_capacity), diag._message_len);
    try std.testing.expectEqual(@as(usize, ErrorDiagnostic.message_capacity), diag.message().?.len);
}

test "ErrorDiagnostic setResponseBody and responseBody" {
    var diag: ErrorDiagnostic = .{};
    const body = "{\"error\":{\"message\":\"test\"}}";
    diag.setResponseBody(body);
    try std.testing.expectEqualStrings(body, diag.responseBody().?);
}

test "ErrorDiagnostic setResponseBody truncates" {
    var diag: ErrorDiagnostic = .{};
    const long_body = "y" ** (ErrorDiagnostic.response_body_capacity + 100);
    diag.setResponseBody(long_body);
    try std.testing.expectEqual(@as(u16, ErrorDiagnostic.response_body_capacity), diag._response_body_len);
}

test "ErrorDiagnostic classifyStatus" {
    var diag: ErrorDiagnostic = .{};

    diag.status_code = 401;
    diag.classifyStatus();
    try std.testing.expect(diag.kind == .authentication);
    try std.testing.expect(!diag.is_retryable);

    diag.status_code = 429;
    diag.classifyStatus();
    try std.testing.expect(diag.kind == .rate_limit);
    try std.testing.expect(diag.is_retryable);

    diag.status_code = 500;
    diag.classifyStatus();
    try std.testing.expect(diag.kind == .server_error);
    try std.testing.expect(diag.is_retryable);

    diag.status_code = 400;
    diag.classifyStatus();
    try std.testing.expect(diag.kind == .invalid_request);
    try std.testing.expect(!diag.is_retryable);

    diag.status_code = 404;
    diag.classifyStatus();
    try std.testing.expect(diag.kind == .not_found);
    try std.testing.expect(!diag.is_retryable);
}

test "ErrorDiagnostic populateFromResponse with JSON error" {
    var diag: ErrorDiagnostic = .{};
    diag.populateFromResponse(429, "{\"error\":{\"message\":\"Rate limit exceeded\"}}");
    try std.testing.expectEqual(@as(?u16, 429), diag.status_code);
    try std.testing.expect(diag.kind == .rate_limit);
    try std.testing.expect(diag.is_retryable);
    try std.testing.expectEqualStrings("Rate limit exceeded", diag.message().?);
}

test "ErrorDiagnostic populateFromResponse with non-JSON body" {
    var diag: ErrorDiagnostic = .{};
    diag.populateFromResponse(500, "Internal Server Error");
    try std.testing.expectEqual(@as(?u16, 500), diag.status_code);
    try std.testing.expect(diag.kind == .server_error);
    try std.testing.expect(diag.is_retryable);
    // Falls back to status text
    try std.testing.expectEqualStrings("Internal Server Error", diag.message().?);
}

test "ErrorDiagnostic populateFromResponse with flat error string" {
    var diag: ErrorDiagnostic = .{};
    diag.populateFromResponse(400, "{\"error\":\"Bad input\"}");
    try std.testing.expectEqualStrings("Bad input", diag.message().?);
}

test "ErrorDiagnostic populateFromResponse with message at root" {
    var diag: ErrorDiagnostic = .{};
    diag.populateFromResponse(403, "{\"message\":\"Forbidden resource\"}");
    try std.testing.expectEqualStrings("Forbidden resource", diag.message().?);
}

test "ErrorDiagnostic format" {
    var diag: ErrorDiagnostic = .{};
    diag.provider = "openai";
    diag.populateFromResponse(429, "{\"error\":{\"message\":\"Rate limit exceeded\"}}");

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try diag.format(fbs.writer());
    const result = fbs.getWritten();
    try std.testing.expectEqualStrings("[openai] rate_limit (HTTP 429): Rate limit exceeded [retryable]", result);
}

test "ErrorDiagnostic format without provider" {
    var diag: ErrorDiagnostic = .{};
    diag.status_code = 401;
    diag.classifyStatus();
    diag.setMessage("Invalid API key");

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try diag.format(fbs.writer());
    const result = fbs.getWritten();
    try std.testing.expectEqualStrings("authentication (HTTP 401): Invalid API key", result);
}
