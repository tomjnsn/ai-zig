const std = @import("std");

/// HTTP client interface for making API requests.
/// This interface allows for different HTTP client implementations to be used,
/// enabling dependency injection for testing (via MockHttpClient) or custom
/// HTTP backends.
///
/// ## Implementing a Custom HttpClient
///
/// 1. Create a struct with your implementation state
/// 2. Define a static vtable pointing to your implementation functions
/// 3. Implement an `asInterface()` method that returns `HttpClient`
///
/// ## Memory Safety
///
/// The `impl` pointer is type-erased (`*anyopaque`). Implementations must:
/// - Store a pointer to themselves in `impl` via `asInterface()`
/// - Cast back using `@ptrCast(@alignCast(impl))` in vtable functions
/// - Ensure the concrete struct outlives the returned interface
///
/// See `MockHttpClient` and `StdHttpClient` for reference implementations.
pub const HttpClient = struct {
    vtable: *const VTable,
    impl: *anyopaque,

    pub const VTable = struct {
        /// Make a non-streaming HTTP request
        request: *const fn (
            impl: *anyopaque,
            req: Request,
            allocator: std.mem.Allocator,
            on_response: *const fn (ctx: ?*anyopaque, response: Response) void,
            on_error: *const fn (ctx: ?*anyopaque, err: HttpError) void,
            ctx: ?*anyopaque,
        ) void,

        /// Make a streaming HTTP request
        requestStreaming: *const fn (
            impl: *anyopaque,
            req: Request,
            allocator: std.mem.Allocator,
            callbacks: StreamCallbacks,
        ) void,

        /// Cancel an ongoing request
        cancel: ?*const fn (impl: *anyopaque) void,
    };

    /// HTTP request configuration
    pub const Request = struct {
        method: Method,
        url: []const u8,
        headers: []const Header,
        body: ?[]const u8 = null,
        timeout_ms: ?u64 = null,
        /// Maximum allowed response body size in bytes. null = no limit.
        max_response_size: ?usize = null,
    };

    /// HTTP methods
    pub const Method = enum {
        GET,
        POST,
        PUT,
        DELETE,
        PATCH,
        HEAD,
        OPTIONS,

        pub fn toString(self: Method) []const u8 {
            return switch (self) {
                .GET => "GET",
                .POST => "POST",
                .PUT => "PUT",
                .DELETE => "DELETE",
                .PATCH => "PATCH",
                .HEAD => "HEAD",
                .OPTIONS => "OPTIONS",
            };
        }
    };

    /// HTTP header
    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };

    /// HTTP response
    pub const Response = struct {
        status_code: u16,
        headers: []const Header,
        body: []const u8,

        /// Check if the response indicates success (2xx status)
        pub fn isSuccess(self: Response) bool {
            return self.status_code >= 200 and self.status_code < 300;
        }

        /// Check if the response is a client error (4xx status)
        pub fn isClientError(self: Response) bool {
            return self.status_code >= 400 and self.status_code < 500;
        }

        /// Check if the response is a server error (5xx status)
        pub fn isServerError(self: Response) bool {
            return self.status_code >= 500;
        }

        /// Get a header value by name (case-insensitive)
        pub fn getHeader(self: Response, name: []const u8) ?[]const u8 {
            for (self.headers) |header| {
                if (std.ascii.eqlIgnoreCase(header.name, name)) {
                    return header.value;
                }
            }
            return null;
        }
    };

    /// HTTP error information
    pub const HttpError = struct {
        kind: ErrorKind,
        message: []const u8,
        status_code: ?u16 = null,
        response_body: ?[]const u8 = null,

        pub const ErrorKind = enum {
            connection_failed,
            timeout,
            ssl_error,
            invalid_response,
            server_error,
            aborted,
            dns_error,
            too_many_redirects,
            response_too_large,
            unknown,
        };

        /// Check if the error is retryable
        pub fn isRetryable(self: HttpError) bool {
            return switch (self.kind) {
                .timeout, .connection_failed, .server_error => true,
                else => {
                    if (self.status_code) |code| {
                        return code == 408 or code == 429 or code >= 500;
                    }
                    return false;
                },
            };
        }
    };

    /// Callbacks for streaming responses
    pub const StreamCallbacks = struct {
        /// Called when response headers are received
        on_headers: ?*const fn (ctx: ?*anyopaque, status_code: u16, headers: []const Header) void = null,
        /// Called for each chunk of data received
        on_chunk: *const fn (ctx: ?*anyopaque, chunk: []const u8) void,
        /// Called when the stream completes successfully
        on_complete: *const fn (ctx: ?*anyopaque) void,
        /// Called when an error occurs
        on_error: *const fn (ctx: ?*anyopaque, err: HttpError) void,
        /// User context passed to all callbacks
        ctx: ?*anyopaque = null,
    };

    /// Make a non-streaming HTTP request
    pub fn request(
        self: HttpClient,
        req: Request,
        allocator: std.mem.Allocator,
        on_response: *const fn (ctx: ?*anyopaque, response: Response) void,
        on_error: *const fn (ctx: ?*anyopaque, err: HttpError) void,
        ctx: ?*anyopaque,
    ) void {
        self.vtable.request(self.impl, req, allocator, on_response, on_error, ctx);
    }

    /// Make a streaming HTTP request
    pub fn requestStreaming(
        self: HttpClient,
        req: Request,
        allocator: std.mem.Allocator,
        callbacks: StreamCallbacks,
    ) void {
        self.vtable.requestStreaming(self.impl, req, allocator, callbacks);
    }

    /// Cancel an ongoing request (if supported)
    pub fn cancel(self: HttpClient) void {
        if (self.vtable.cancel) |cancel_fn| {
            cancel_fn(self.impl);
        }
    }

    /// Convenience method for making a POST request
    pub fn post(
        self: HttpClient,
        url: []const u8,
        headers: std.StringHashMap([]const u8),
        body: []const u8,
        allocator: std.mem.Allocator,
        on_response: anytype,
        on_error: anytype,
        ctx: anytype,
    ) void {
        // Convert headers to slice
        var header_list: [64]Header = undefined;
        var header_count: usize = 0;
        var iter = headers.iterator();
        while (iter.next()) |entry| {
            if (header_count >= 64) break;
            header_list[header_count] = .{
                .name = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            };
            header_count += 1;
        }

        const req = Request{
            .method = .POST,
            .url = url,
            .headers = header_list[0..header_count],
            .body = body,
        };

        // Call the underlying request method with adapted callbacks
        self.request(req, allocator, struct {
            fn onResponse(c: ?*anyopaque, response: Response) void {
                _ = c;
                _ = response;
                // TODO: Adapt response format
            }
        }.onResponse, struct {
            fn onError(c: ?*anyopaque, err: HttpError) void {
                _ = c;
                _ = err;
            }
        }.onError, null);

        _ = on_response;
        _ = on_error;
        _ = ctx;
    }
};

/// Builder for constructing HTTP requests
pub const RequestBuilder = struct {
    request: HttpClient.Request,
    headers_list: std.ArrayListUnmanaged(HttpClient.Header),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .request = .{
                .method = .GET,
                .url = "",
                .headers = &.{},
            },
            .headers_list = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.headers_list.deinit(self.allocator);
    }

    pub fn method(self: *Self, m: HttpClient.Method) *Self {
        self.request.method = m;
        return self;
    }

    pub fn url(self: *Self, u: []const u8) *Self {
        self.request.url = u;
        return self;
    }

    pub fn header(self: *Self, name: []const u8, value: []const u8) !*Self {
        try self.headers_list.append(self.allocator, .{ .name = name, .value = value });
        self.request.headers = self.headers_list.items;
        return self;
    }

    pub fn body(self: *Self, b: []const u8) *Self {
        self.request.body = b;
        return self;
    }

    pub fn timeout(self: *Self, ms: u64) *Self {
        self.request.timeout_ms = ms;
        return self;
    }

    pub fn build(self: *Self) HttpClient.Request {
        self.request.headers = self.headers_list.items;
        return self.request;
    }
};

test "RequestBuilder" {
    const allocator = std.testing.allocator;

    var builder = RequestBuilder.init(allocator);
    defer builder.deinit();

    _ = try (try builder.method(.POST)
        .url("https://api.example.com/v1/chat")
        .header("Content-Type", "application/json"))
        .header("Authorization", "Bearer token123");
    _ = builder.body("{\"message\": \"hello\"}")
        .timeout(30000);

    const req = builder.build();

    try std.testing.expectEqual(HttpClient.Method.POST, req.method);
    try std.testing.expectEqualStrings("https://api.example.com/v1/chat", req.url);
    try std.testing.expectEqual(@as(usize, 2), req.headers.len);
    try std.testing.expectEqual(@as(?u64, 30000), req.timeout_ms);
}

test "Response helpers" {
    const response = HttpClient.Response{
        .status_code = 200,
        .headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "X-Request-Id", .value = "abc123" },
        },
        .body = "{}",
    };

    try std.testing.expect(response.isSuccess());
    try std.testing.expect(!response.isClientError());
    try std.testing.expect(!response.isServerError());
    try std.testing.expectEqualStrings("application/json", response.getHeader("content-type").?);
    try std.testing.expectEqualStrings("abc123", response.getHeader("X-Request-Id").?);
    try std.testing.expect(response.getHeader("X-Missing") == null);
}

test "Response status code helpers" {
    const success_response = HttpClient.Response{
        .status_code = 201,
        .headers = &.{},
        .body = "",
    };
    try std.testing.expect(success_response.isSuccess());
    try std.testing.expect(!success_response.isClientError());
    try std.testing.expect(!success_response.isServerError());

    const client_error_response = HttpClient.Response{
        .status_code = 404,
        .headers = &.{},
        .body = "",
    };
    try std.testing.expect(!client_error_response.isSuccess());
    try std.testing.expect(client_error_response.isClientError());
    try std.testing.expect(!client_error_response.isServerError());

    const server_error_response = HttpClient.Response{
        .status_code = 500,
        .headers = &.{},
        .body = "",
    };
    try std.testing.expect(!server_error_response.isSuccess());
    try std.testing.expect(!server_error_response.isClientError());
    try std.testing.expect(server_error_response.isServerError());

    const redirect_response = HttpClient.Response{
        .status_code = 301,
        .headers = &.{},
        .body = "",
    };
    try std.testing.expect(!redirect_response.isSuccess());
    try std.testing.expect(!redirect_response.isClientError());
    try std.testing.expect(!redirect_response.isServerError());
}

test "Method toString" {
    try std.testing.expectEqualStrings("GET", HttpClient.Method.GET.toString());
    try std.testing.expectEqualStrings("POST", HttpClient.Method.POST.toString());
    try std.testing.expectEqualStrings("PUT", HttpClient.Method.PUT.toString());
    try std.testing.expectEqualStrings("DELETE", HttpClient.Method.DELETE.toString());
    try std.testing.expectEqualStrings("PATCH", HttpClient.Method.PATCH.toString());
    try std.testing.expectEqualStrings("HEAD", HttpClient.Method.HEAD.toString());
    try std.testing.expectEqualStrings("OPTIONS", HttpClient.Method.OPTIONS.toString());
}

test "HttpError isRetryable" {
    const timeout_error = HttpClient.HttpError{
        .kind = .timeout,
        .message = "Request timed out",
    };
    try std.testing.expect(timeout_error.isRetryable());

    const connection_error = HttpClient.HttpError{
        .kind = .connection_failed,
        .message = "Connection failed",
    };
    try std.testing.expect(connection_error.isRetryable());

    const server_error = HttpClient.HttpError{
        .kind = .server_error,
        .message = "Server error",
    };
    try std.testing.expect(server_error.isRetryable());

    const ssl_error = HttpClient.HttpError{
        .kind = .ssl_error,
        .message = "SSL error",
    };
    try std.testing.expect(!ssl_error.isRetryable());

    const invalid_response_error = HttpClient.HttpError{
        .kind = .invalid_response,
        .message = "Invalid response",
    };
    try std.testing.expect(!invalid_response_error.isRetryable());

    // Test status code based retryability
    const rate_limit_error = HttpClient.HttpError{
        .kind = .unknown,
        .message = "Rate limited",
        .status_code = 429,
    };
    try std.testing.expect(rate_limit_error.isRetryable());

    const request_timeout_error = HttpClient.HttpError{
        .kind = .unknown,
        .message = "Request timeout",
        .status_code = 408,
    };
    try std.testing.expect(request_timeout_error.isRetryable());

    const internal_server_error = HttpClient.HttpError{
        .kind = .unknown,
        .message = "Internal server error",
        .status_code = 500,
    };
    try std.testing.expect(internal_server_error.isRetryable());

    const not_found_error = HttpClient.HttpError{
        .kind = .unknown,
        .message = "Not found",
        .status_code = 404,
    };
    try std.testing.expect(!not_found_error.isRetryable());
}

test "RequestBuilder chain" {
    const allocator = std.testing.allocator;

    var builder = RequestBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder
        .method(.GET)
        .url("https://example.com")
        .header("Accept", "application/json");

    _ = builder.timeout(5000);

    const req = builder.build();

    try std.testing.expectEqual(HttpClient.Method.GET, req.method);
    try std.testing.expectEqualStrings("https://example.com", req.url);
    try std.testing.expectEqual(@as(usize, 1), req.headers.len);
    try std.testing.expectEqual(@as(?u64, 5000), req.timeout_ms);
}

test "RequestBuilder multiple headers" {
    const allocator = std.testing.allocator;

    var builder = RequestBuilder.init(allocator);
    defer builder.deinit();

    _ = try (try (try builder
        .method(.POST)
        .url("https://api.example.com/v1/chat")
        .header("Content-Type", "application/json"))
        .header("Authorization", "Bearer token"))
        .header("X-Custom-Header", "value");

    const req = builder.build();

    try std.testing.expectEqual(@as(usize, 3), req.headers.len);
}

test "Response getHeader case insensitive" {
    const response = HttpClient.Response{
        .status_code = 200,
        .headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
        },
        .body = "",
    };

    try std.testing.expectEqualStrings("application/json", response.getHeader("content-type").?);
    try std.testing.expectEqualStrings("application/json", response.getHeader("CONTENT-TYPE").?);
    try std.testing.expectEqualStrings("application/json", response.getHeader("CoNtEnT-TyPe").?);
}

test "Request with no headers" {
    const allocator = std.testing.allocator;

    var builder = RequestBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.method(.GET).url("https://example.com");

    const req = builder.build();

    try std.testing.expectEqual(@as(usize, 0), req.headers.len);
    try std.testing.expect(req.body == null);
    try std.testing.expect(req.timeout_ms == null);
}
