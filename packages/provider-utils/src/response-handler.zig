const std = @import("std");
const http_client = @import("http/client.zig");
const json_value = @import("provider").json_value;
const errors = @import("provider").errors;
const parse_json = @import("parse-json.zig");

/// Response handler function type
/// Takes response information and returns a processed result
pub fn ResponseHandler(comptime T: type) type {
    return struct {
        handler_fn: *const fn (
            response: HandlerInput,
            allocator: std.mem.Allocator,
        ) HandlerResult(T),
    };
}

/// Input to response handlers
pub const HandlerInput = struct {
    url: []const u8,
    request_body_values: ?json_value.JsonValue,
    status_code: u16,
    headers: []const http_client.HttpClient.Header,
    body: []const u8,
};

/// Result from a response handler
pub fn HandlerResult(comptime T: type) type {
    return union(enum) {
        success: SuccessResult(T),
        failure: errors.ApiCallError,
    };
}

/// Successful handler result
pub fn SuccessResult(comptime T: type) type {
    return struct {
        value: T,
        raw_value: ?json_value.JsonValue = null,
        response_headers: ?[]const http_client.HttpClient.Header = null,
    };
}

/// Create a JSON error response handler
pub fn createJsonErrorResponseHandler(
    comptime ErrorSchema: type,
    comptime errorToMessage: fn (ErrorSchema) []const u8,
    comptime isRetryable: ?fn (u16, ?ErrorSchema) bool,
) ResponseHandler(errors.ApiCallError) {
    return .{
        .handler_fn = struct {
            fn handle(
                input: HandlerInput,
                allocator: std.mem.Allocator,
            ) HandlerResult(errors.ApiCallError) {
                // Handle empty response body
                if (input.body.len == 0 or std.mem.trim(u8, input.body, " \t\n\r").len == 0) {
                    const retryable = if (isRetryable) |r| r(input.status_code, null) else false;
                    return .{
                        .success = .{
                            .value = errors.ApiCallError.init(.{
                                .message = "Empty error response",
                                .url = input.url,
                                .status_code = input.status_code,
                                .response_body = input.body,
                                .is_retryable = retryable,
                            }),
                        },
                    };
                }

                // Try to parse as JSON
                const parse_result = parse_json.safeParseJson(input.body, allocator);

                switch (parse_result) {
                    .success => |parsed| {
                        // Try to extract error message
                        // This is simplified - in real implementation you'd validate against ErrorSchema
                        _ = parsed;
                        const message = errorToMessage(undefined);
                        const retryable = if (isRetryable) |r| r(input.status_code, null) else false;

                        return .{
                            .success = .{
                                .value = errors.ApiCallError.init(.{
                                    .message = message,
                                    .url = input.url,
                                    .status_code = input.status_code,
                                    .response_body = input.body,
                                    .is_retryable = retryable,
                                }),
                            },
                        };
                    },
                    .failure => {
                        const retryable = if (isRetryable) |r| r(input.status_code, null) else false;
                        return .{
                            .success = .{
                                .value = errors.ApiCallError.init(.{
                                    .message = "Failed to parse error response",
                                    .url = input.url,
                                    .status_code = input.status_code,
                                    .response_body = input.body,
                                    .is_retryable = retryable,
                                }),
                            },
                        };
                    },
                }
            }
        }.handle,
    };
}

/// Create a JSON response handler
pub fn createJsonResponseHandler(
    comptime T: type,
) ResponseHandler(T) {
    return .{
        .handler_fn = struct {
            fn handle(
                input: HandlerInput,
                allocator: std.mem.Allocator,
            ) HandlerResult(T) {
                const parse_result = parse_json.safeParseJson(input.body, allocator);

                switch (parse_result) {
                    .success => |parsed| {
                        // In a full implementation, you'd validate and convert to T
                        _ = parsed;
                        return .{
                            .failure = errors.ApiCallError.init(.{
                                .message = "JSON response handler not fully implemented",
                                .url = input.url,
                                .status_code = input.status_code,
                            }),
                        };
                    },
                    .failure => |err| {
                        return .{
                            .failure = errors.ApiCallError.init(.{
                                .message = err.message,
                                .url = input.url,
                                .status_code = input.status_code,
                                .response_body = input.body,
                            }),
                        };
                    },
                }
            }
        }.handle,
    };
}

/// Create a binary response handler
pub fn createBinaryResponseHandler() ResponseHandler([]const u8) {
    return .{
        .handler_fn = struct {
            fn handle(
                input: HandlerInput,
                allocator: std.mem.Allocator,
            ) HandlerResult([]const u8) {
                _ = allocator;
                if (input.body.len == 0) {
                    return .{
                        .failure = errors.ApiCallError.init(.{
                            .message = "Response body is empty",
                            .url = input.url,
                            .status_code = input.status_code,
                        }),
                    };
                }

                return .{
                    .success = .{
                        .value = input.body,
                        .response_headers = input.headers,
                    },
                };
            }
        }.handle,
    };
}

/// Create a status code error response handler
pub fn createStatusCodeErrorResponseHandler() ResponseHandler(errors.ApiCallError) {
    return .{
        .handler_fn = struct {
            fn handle(
                input: HandlerInput,
                allocator: std.mem.Allocator,
            ) HandlerResult(errors.ApiCallError) {
                _ = allocator;
                return .{
                    .success = .{
                        .value = errors.ApiCallError.init(.{
                            .message = "HTTP error",
                            .url = input.url,
                            .status_code = input.status_code,
                            .response_body = input.body,
                        }),
                    },
                };
            }
        }.handle,
    };
}

test "createStatusCodeErrorResponseHandler" {
    const handler = createStatusCodeErrorResponseHandler();
    const allocator = std.testing.allocator;

    const result = handler.handler_fn(.{
        .url = "https://api.openai.com/v1/chat/completions",
        .request_body_values = null,
        .status_code = 429,
        .headers = &.{},
        .body = "{\"error\": \"rate limited\"}",
    }, allocator);

    switch (result) {
        .success => |s| {
            try std.testing.expectEqualStrings("HTTP error", s.value.message());
            try std.testing.expectEqualStrings("https://api.openai.com/v1/chat/completions", s.value.url());
            try std.testing.expectEqual(@as(?u16, 429), s.value.statusCode());
            try std.testing.expectEqualStrings("{\"error\": \"rate limited\"}", s.value.responseBody().?);
        },
        .failure => unreachable,
    }
}

test "createStatusCodeErrorResponseHandler 500" {
    const handler = createStatusCodeErrorResponseHandler();
    const allocator = std.testing.allocator;

    const result = handler.handler_fn(.{
        .url = "https://api.example.com/test",
        .request_body_values = null,
        .status_code = 500,
        .headers = &.{},
        .body = "Internal Server Error",
    }, allocator);

    switch (result) {
        .success => |s| {
            try std.testing.expectEqual(@as(?u16, 500), s.value.statusCode());
            try std.testing.expectEqualStrings("Internal Server Error", s.value.responseBody().?);
        },
        .failure => unreachable,
    }
}

test "createJsonErrorResponseHandler empty body" {
    const handler = createJsonErrorResponseHandler(
        void,
        struct {
            fn toMessage(_: void) []const u8 {
                return "error";
            }
        }.toMessage,
        null,
    );

    const result = handler.handler_fn(.{
        .url = "https://api.example.com/test",
        .request_body_values = null,
        .status_code = 500,
        .headers = &.{},
        .body = "",
    }, std.testing.allocator);

    switch (result) {
        .success => |s| {
            try std.testing.expectEqualStrings("Empty error response", s.value.message());
            try std.testing.expectEqual(@as(?u16, 500), s.value.statusCode());
        },
        .failure => unreachable,
    }
}

test "createJsonErrorResponseHandler malformed JSON" {
    const handler = createJsonErrorResponseHandler(
        void,
        struct {
            fn toMessage(_: void) []const u8 {
                return "error";
            }
        }.toMessage,
        null,
    );

    const result = handler.handler_fn(.{
        .url = "https://api.example.com/test",
        .request_body_values = null,
        .status_code = 400,
        .headers = &.{},
        .body = "{not valid json}",
    }, std.testing.allocator);

    switch (result) {
        .success => |s| {
            try std.testing.expectEqualStrings("Failed to parse error response", s.value.message());
            try std.testing.expectEqual(@as(?u16, 400), s.value.statusCode());
        },
        .failure => unreachable,
    }
}

test "createJsonErrorResponseHandler whitespace body" {
    const handler = createJsonErrorResponseHandler(
        void,
        struct {
            fn toMessage(_: void) []const u8 {
                return "error";
            }
        }.toMessage,
        null,
    );

    const result = handler.handler_fn(.{
        .url = "https://api.example.com/test",
        .request_body_values = null,
        .status_code = 502,
        .headers = &.{},
        .body = "   \n\t  ",
    }, std.testing.allocator);

    switch (result) {
        .success => |s| {
            try std.testing.expectEqualStrings("Empty error response", s.value.message());
            try std.testing.expectEqual(@as(?u16, 502), s.value.statusCode());
        },
        .failure => unreachable,
    }
}

test "createBinaryResponseHandler with headers" {
    const handler = createBinaryResponseHandler();

    const response_headers = [_]http_client.HttpClient.Header{
        .{ .name = "Content-Type", .value = "audio/mpeg" },
        .{ .name = "Content-Length", .value = "1024" },
    };

    const result = handler.handler_fn(.{
        .url = "https://api.example.com/audio",
        .request_body_values = null,
        .status_code = 200,
        .headers = &response_headers,
        .body = "fake audio bytes",
    }, std.testing.allocator);

    switch (result) {
        .success => |s| {
            try std.testing.expectEqualStrings("fake audio bytes", s.value);
            try std.testing.expect(s.response_headers != null);
            try std.testing.expectEqual(@as(usize, 2), s.response_headers.?.len);
        },
        .failure => unreachable,
    }
}

test "createBinaryResponseHandler" {
    const handler = createBinaryResponseHandler();

    const result = handler.handler_fn(.{
        .url = "https://api.example.com",
        .request_body_values = null,
        .status_code = 200,
        .headers = &.{},
        .body = "binary data",
    }, std.testing.allocator);

    switch (result) {
        .success => |s| {
            try std.testing.expectEqualStrings("binary data", s.value);
        },
        .failure => unreachable,
    }
}

test "createBinaryResponseHandler empty body" {
    const handler = createBinaryResponseHandler();

    const result = handler.handler_fn(.{
        .url = "https://api.example.com",
        .request_body_values = null,
        .status_code = 200,
        .headers = &.{},
        .body = "",
    }, std.testing.allocator);

    switch (result) {
        .success => unreachable,
        .failure => |err| {
            try std.testing.expectEqualStrings("Response body is empty", err.message());
        },
    }
}
