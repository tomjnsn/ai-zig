const std = @import("std");
const http_client = @import("http/client.zig");
const json_value = @import("provider").json_value;
const errors = @import("provider").errors;

/// Options for posting JSON to an API
pub const PostJsonToApiOptions = struct {
    url: []const u8,
    headers: ?[]const http_client.HttpClient.Header = null,
    body: json_value.JsonValue,
    abort_signal: ?*std.Thread.ResetEvent = null,
    timeout_ms: ?u64 = null,
    /// Maximum allowed response body size in bytes. null = no limit.
    max_response_size: ?usize = null,
};

/// Options for posting raw data to an API
pub const PostToApiOptions = struct {
    url: []const u8,
    headers: ?[]const http_client.HttpClient.Header = null,
    body: []const u8,
    body_values: ?json_value.JsonValue = null,
    abort_signal: ?*std.Thread.ResetEvent = null,
    timeout_ms: ?u64 = null,
    /// Maximum allowed response body size in bytes. null = no limit.
    max_response_size: ?usize = null,
};

/// Result of an API call
pub const ApiResponse = struct {
    body: []const u8,
    headers: []const http_client.HttpClient.Header,
    status_code: u16,
    raw_value: ?json_value.JsonValue = null,
};

/// API call error with extended information
pub const ApiError = struct {
    info: errors.ApiCallError,
};

/// Callbacks for API responses
pub const ApiCallbacks = struct {
    on_success: *const fn (ctx: ?*anyopaque, response: ApiResponse) void,
    on_error: *const fn (ctx: ?*anyopaque, err: ApiError) void,
    ctx: ?*anyopaque = null,
};

/// Post JSON data to an API endpoint
pub fn postJsonToApi(
    client: http_client.HttpClient,
    options: PostJsonToApiOptions,
    allocator: std.mem.Allocator,
    callbacks: ApiCallbacks,
) void {
    // Serialize the JSON body
    const body = options.body.stringify(allocator) catch {
        callbacks.on_error(callbacks.ctx, .{
            .info = errors.ApiCallError.init(.{
                .message = "Failed to serialize JSON body",
                .url = options.url,
            }),
        });
        return;
    };

    // Build headers list
    var headers_list = std.ArrayList(http_client.HttpClient.Header).empty;
    defer headers_list.deinit(allocator);

    // Add Content-Type header
    headers_list.append(allocator, .{
        .name = "Content-Type",
        .value = "application/json",
    }) catch {
        allocator.free(body);
        callbacks.on_error(callbacks.ctx, .{
            .info = errors.ApiCallError.init(.{
                .message = "Failed to allocate headers",
                .url = options.url,
            }),
        });
        return;
    };

    // Add custom headers
    if (options.headers) |custom_headers| {
        for (custom_headers) |h| {
            headers_list.append(allocator, h) catch {
                allocator.free(body);
                callbacks.on_error(callbacks.ctx, .{
                    .info = errors.ApiCallError.init(.{
                        .message = "Failed to allocate headers",
                        .url = options.url,
                    }),
                });
                return;
            };
        }
    }

    // Create context for callbacks
    const CallbackContext = struct {
        original_callbacks: ApiCallbacks,
        url: []const u8,
        body_values: json_value.JsonValue,
        body_string: []const u8,
        allocator: std.mem.Allocator,
        max_response_size: ?usize,
    };

    const ctx = allocator.create(CallbackContext) catch {
        allocator.free(body);
        callbacks.on_error(callbacks.ctx, .{
            .info = errors.ApiCallError.init(.{
                .message = "Failed to allocate callback context",
                .url = options.url,
            }),
        });
        return;
    };
    ctx.* = .{
        .original_callbacks = callbacks,
        .url = options.url,
        .body_values = options.body,
        .body_string = body,
        .allocator = allocator,
        .max_response_size = options.max_response_size,
    };

    // Make the request
    client.request(
        .{
            .method = .POST,
            .url = options.url,
            .headers = headers_list.items,
            .body = body,
            .timeout_ms = options.timeout_ms,
            .max_response_size = options.max_response_size,
        },
        allocator,
        struct {
            fn onResponse(context: ?*anyopaque, response: http_client.HttpClient.Response) void {
                const c: *CallbackContext = @ptrCast(@alignCast(context));
                defer {
                    c.allocator.free(c.body_string);
                    c.allocator.destroy(c);
                }

                // Check response size limit
                if (c.max_response_size) |max_size| {
                    if (response.body.len > max_size) {
                        c.original_callbacks.on_error(c.original_callbacks.ctx, .{
                            .info = errors.ApiCallError.init(.{
                                .message = "Response body exceeds maximum allowed size",
                                .url = c.url,
                                .status_code = response.status_code,
                            }),
                        });
                        return;
                    }
                }

                if (response.isSuccess()) {
                    c.original_callbacks.on_success(c.original_callbacks.ctx, .{
                        .body = response.body,
                        .headers = response.headers,
                        .status_code = response.status_code,
                    });
                } else {
                    c.original_callbacks.on_error(c.original_callbacks.ctx, .{
                        .info = errors.ApiCallError.init(.{
                            .message = "API call failed",
                            .url = c.url,
                            .status_code = response.status_code,
                            .response_body = response.body,
                        }),
                    });
                }
            }
        }.onResponse,
        struct {
            fn onError(context: ?*anyopaque, err: http_client.HttpClient.HttpError) void {
                const c: *CallbackContext = @ptrCast(@alignCast(context));
                defer {
                    c.allocator.free(c.body_string);
                    c.allocator.destroy(c);
                }
                c.original_callbacks.on_error(c.original_callbacks.ctx, .{
                    .info = errors.ApiCallError.init(.{
                        .message = err.message,
                        .url = c.url,
                        .status_code = err.status_code,
                        .is_retryable = err.isRetryable(),
                    }),
                });
            }
        }.onError,
        ctx,
    );
}

/// Post raw data to an API endpoint
pub fn postToApi(
    client: http_client.HttpClient,
    options: PostToApiOptions,
    allocator: std.mem.Allocator,
    callbacks: ApiCallbacks,
) void {
    // Build headers list
    var headers_list = std.ArrayList(http_client.HttpClient.Header).empty;
    defer headers_list.deinit(allocator);

    // Add custom headers
    if (options.headers) |custom_headers| {
        for (custom_headers) |h| {
            headers_list.append(allocator, h) catch {
                callbacks.on_error(callbacks.ctx, .{
                    .info = errors.ApiCallError.init(.{
                        .message = "Failed to append header to request",
                        .url = options.url,
                    }),
                });
                return;
            };
        }
    }

    // Create context for callbacks
    const CallbackContext = struct {
        original_callbacks: ApiCallbacks,
        url: []const u8,
        allocator: std.mem.Allocator,
        max_response_size: ?usize,
    };

    const ctx = allocator.create(CallbackContext) catch {
        callbacks.on_error(callbacks.ctx, .{
            .info = errors.ApiCallError.init(.{
                .message = "Failed to allocate callback context",
                .url = options.url,
            }),
        });
        return;
    };
    ctx.* = .{
        .original_callbacks = callbacks,
        .url = options.url,
        .allocator = allocator,
        .max_response_size = options.max_response_size,
    };

    // Make the request
    client.request(
        .{
            .method = .POST,
            .url = options.url,
            .headers = headers_list.items,
            .body = options.body,
            .timeout_ms = options.timeout_ms,
            .max_response_size = options.max_response_size,
        },
        allocator,
        struct {
            fn onResponse(context: ?*anyopaque, response: http_client.HttpClient.Response) void {
                const c: *CallbackContext = @ptrCast(@alignCast(context));
                defer c.allocator.destroy(c);

                // Check response size limit
                if (c.max_response_size) |max_size| {
                    if (response.body.len > max_size) {
                        c.original_callbacks.on_error(c.original_callbacks.ctx, .{
                            .info = errors.ApiCallError.init(.{
                                .message = "Response body exceeds maximum allowed size",
                                .url = c.url,
                                .status_code = response.status_code,
                            }),
                        });
                        return;
                    }
                }

                if (response.isSuccess()) {
                    c.original_callbacks.on_success(c.original_callbacks.ctx, .{
                        .body = response.body,
                        .headers = response.headers,
                        .status_code = response.status_code,
                    });
                } else {
                    c.original_callbacks.on_error(c.original_callbacks.ctx, .{
                        .info = errors.ApiCallError.init(.{
                            .message = "API call failed",
                            .url = c.url,
                            .status_code = response.status_code,
                            .response_body = response.body,
                        }),
                    });
                }
            }
        }.onResponse,
        struct {
            fn onError(context: ?*anyopaque, err: http_client.HttpClient.HttpError) void {
                const c: *CallbackContext = @ptrCast(@alignCast(context));
                defer c.allocator.destroy(c);
                c.original_callbacks.on_error(c.original_callbacks.ctx, .{
                    .info = errors.ApiCallError.init(.{
                        .message = err.message,
                        .url = c.url,
                        .status_code = err.status_code,
                        .is_retryable = err.isRetryable(),
                    }),
                });
            }
        }.onError,
        ctx,
    );
}

/// Streaming API callbacks
pub const StreamingApiCallbacks = struct {
    on_headers: ?*const fn (ctx: ?*anyopaque, status_code: u16, headers: []const http_client.HttpClient.Header) void = null,
    on_chunk: *const fn (ctx: ?*anyopaque, chunk: []const u8) void,
    on_complete: *const fn (ctx: ?*anyopaque) void,
    on_error: *const fn (ctx: ?*anyopaque, err: ApiError) void,
    ctx: ?*anyopaque = null,
};

/// Post JSON data to an API endpoint with streaming response
pub fn postJsonToApiStreaming(
    client: http_client.HttpClient,
    options: PostJsonToApiOptions,
    allocator: std.mem.Allocator,
    callbacks: StreamingApiCallbacks,
) void {
    // Serialize the JSON body
    const body = options.body.stringify(allocator) catch {
        callbacks.on_error(callbacks.ctx, .{
            .info = errors.ApiCallError.init(.{
                .message = "Failed to serialize JSON body",
                .url = options.url,
            }),
        });
        return;
    };

    // Build headers list
    var headers_list = std.ArrayList(http_client.HttpClient.Header).empty;
    defer headers_list.deinit(allocator);

    // Add Content-Type header
    headers_list.append(allocator, .{
        .name = "Content-Type",
        .value = "application/json",
    }) catch {
        allocator.free(body);
        callbacks.on_error(callbacks.ctx, .{
            .info = errors.ApiCallError.init(.{
                .message = "Failed to allocate headers",
                .url = options.url,
            }),
        });
        return;
    };

    // Add custom headers
    if (options.headers) |custom_headers| {
        for (custom_headers) |h| {
            headers_list.append(allocator, h) catch {
                allocator.free(body);
                callbacks.on_error(callbacks.ctx, .{
                    .info = errors.ApiCallError.init(.{
                        .message = "Failed to allocate headers",
                        .url = options.url,
                    }),
                });
                return;
            };
        }
    }

    // Create context for callbacks
    const CallbackContext = struct {
        original_callbacks: StreamingApiCallbacks,
        url: []const u8,
        body_string: []const u8,
        allocator: std.mem.Allocator,
    };

    const ctx = allocator.create(CallbackContext) catch {
        allocator.free(body);
        callbacks.on_error(callbacks.ctx, .{
            .info = errors.ApiCallError.init(.{
                .message = "Failed to allocate callback context",
                .url = options.url,
            }),
        });
        return;
    };
    ctx.* = .{
        .original_callbacks = callbacks,
        .url = options.url,
        .body_string = body,
        .allocator = allocator,
    };

    // Make the streaming request
    client.requestStreaming(
        .{
            .method = .POST,
            .url = options.url,
            .headers = headers_list.items,
            .body = body,
            .timeout_ms = options.timeout_ms,
        },
        allocator,
        .{
            .on_headers = if (callbacks.on_headers != null)
                struct {
                    fn onHeaders(context: ?*anyopaque, status: u16, hdrs: []const http_client.HttpClient.Header) void {
                        const c: *CallbackContext = @ptrCast(@alignCast(context));
                        if (c.original_callbacks.on_headers) |on_hdrs| {
                            on_hdrs(c.original_callbacks.ctx, status, hdrs);
                        }
                    }
                }.onHeaders
            else
                null,
            .on_chunk = struct {
                fn onChunk(context: ?*anyopaque, chunk: []const u8) void {
                    const c: *CallbackContext = @ptrCast(@alignCast(context));
                    c.original_callbacks.on_chunk(c.original_callbacks.ctx, chunk);
                }
            }.onChunk,
            .on_complete = struct {
                fn onComplete(context: ?*anyopaque) void {
                    const c: *CallbackContext = @ptrCast(@alignCast(context));
                    defer {
                        c.allocator.free(c.body_string);
                        c.allocator.destroy(c);
                    }
                    c.original_callbacks.on_complete(c.original_callbacks.ctx);
                }
            }.onComplete,
            .on_error = struct {
                fn onError(context: ?*anyopaque, err: http_client.HttpClient.HttpError) void {
                    const c: *CallbackContext = @ptrCast(@alignCast(context));
                    defer {
                        c.allocator.free(c.body_string);
                        c.allocator.destroy(c);
                    }
                    c.original_callbacks.on_error(c.original_callbacks.ctx, .{
                        .info = errors.ApiCallError.init(.{
                            .message = err.message,
                            .url = c.url,
                            .status_code = err.status_code,
                            .is_retryable = err.isRetryable(),
                        }),
                    });
                }
            }.onError,
            .ctx = ctx,
        },
    );
}

// ============================================================================
// Tests
// ============================================================================

const mock_client_mod = @import("http/mock-client.zig");

test "rejects response exceeding max size" {
    const allocator = std.testing.allocator;

    var mock = mock_client_mod.MockHttpClient.init(allocator);
    defer mock.deinit();

    // Create a response body larger than the limit
    const large_body = "x" ** 1024; // 1KB body
    mock.setResponse(.{
        .status_code = 200,
        .body = large_body,
    });

    var error_received = false;
    var error_message: []const u8 = "";

    const TestCtx = struct {
        error_received: *bool,
        error_message: *[]const u8,
    };

    var test_ctx = TestCtx{
        .error_received = &error_received,
        .error_message = &error_message,
    };

    postToApi(
        mock.asInterface(),
        .{
            .url = "https://api.example.com/test",
            .body = "{}",
            .max_response_size = 512, // Limit to 512 bytes
        },
        allocator,
        .{
            .on_success = struct {
                fn handler(_: ?*anyopaque, _: ApiResponse) void {}
            }.handler,
            .on_error = struct {
                fn handler(ctx: ?*anyopaque, err: ApiError) void {
                    const c: *TestCtx = @ptrCast(@alignCast(ctx));
                    c.error_received.* = true;
                    c.error_message.* = err.info.message();
                }
            }.handler,
            .ctx = &test_ctx,
        },
    );

    try std.testing.expect(error_received);
    try std.testing.expect(std.mem.indexOf(u8, error_message, "exceeds maximum") != null);
}
