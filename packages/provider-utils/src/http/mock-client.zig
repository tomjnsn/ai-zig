const std = @import("std");
const client_mod = @import("client.zig");

/// Mock HTTP client for testing provider implementations.
/// Allows configuring expected responses without making actual network requests.
///
/// ## Usage Example
///
/// ```zig
/// const allocator = std.testing.allocator;
///
/// // Create mock client
/// var mock = MockHttpClient.init(allocator);
/// defer mock.deinit();
///
/// // Configure response
/// mock.setResponse(.{
///     .status_code = 200,
///     .body = "{\"id\": \"123\", \"choices\": [...]}",
/// });
///
/// // Pass to provider via settings
/// var provider = createOpenAI(allocator, .{
///     .http_client = mock.asInterface(),
/// });
///
/// // After making requests, verify what was sent
/// const req = mock.lastRequest().?;
/// try std.testing.expectEqualStrings("https://api.openai.com/v1/chat/completions", req.url);
/// ```
pub const MockHttpClient = struct {
    allocator: std.mem.Allocator,

    /// Configured response to return for requests
    response: ?MockResponse = null,

    /// Configured error to return for requests
    error_response: ?client_mod.HttpClient.HttpError = null,

    /// Recorded requests for verification
    recorded_requests: std.ArrayList(RecordedRequest),

    /// Streaming chunks to send (for streaming requests)
    streaming_chunks: ?[]const []const u8 = null,

    const Self = @This();

    /// A configured mock response
    pub const MockResponse = struct {
        status_code: u16 = 200,
        headers: []const client_mod.HttpClient.Header = &.{},
        body: []const u8 = "{}",
    };

    /// A recorded request for verification
    pub const RecordedRequest = struct {
        method: client_mod.HttpClient.Method,
        url: []const u8,
        headers: []const client_mod.HttpClient.Header,
        body: ?[]const u8,
    };

    /// Initialize a new mock HTTP client
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .recorded_requests = std.ArrayList(RecordedRequest){},
        };
    }

    /// Deinitialize the mock HTTP client
    pub fn deinit(self: *Self) void {
        self.recorded_requests.deinit(self.allocator);
    }

    /// Configure the mock to return a successful response
    pub fn setResponse(self: *Self, response: MockResponse) void {
        self.response = response;
        self.error_response = null;
    }

    /// Configure the mock to return an error
    pub fn setError(self: *Self, err: client_mod.HttpClient.HttpError) void {
        self.error_response = err;
        self.response = null;
    }

    /// Configure streaming chunks to send
    pub fn setStreamingChunks(self: *Self, chunks: []const []const u8) void {
        self.streaming_chunks = chunks;
    }

    /// Get the number of recorded requests
    pub fn requestCount(self: *const Self) usize {
        return self.recorded_requests.items.len;
    }

    /// Get a recorded request by index
    pub fn getRequest(self: *const Self, index: usize) ?RecordedRequest {
        if (index >= self.recorded_requests.items.len) return null;
        return self.recorded_requests.items[index];
    }

    /// Get the last recorded request
    pub fn lastRequest(self: *const Self) ?RecordedRequest {
        if (self.recorded_requests.items.len == 0) return null;
        return self.recorded_requests.items[self.recorded_requests.items.len - 1];
    }

    /// Clear recorded requests
    pub fn clearRequests(self: *Self) void {
        self.recorded_requests.clearRetainingCapacity();
    }

    /// Get the HttpClient interface for this implementation
    pub fn asInterface(self: *Self) client_mod.HttpClient {
        return .{
            .vtable = &vtable,
            .impl = self,
        };
    }

    const vtable = client_mod.HttpClient.VTable{
        .request = doRequest,
        .requestStreaming = doRequestStreaming,
        .cancel = null,
    };

    fn doRequest(
        impl: *anyopaque,
        req: client_mod.HttpClient.Request,
        allocator: std.mem.Allocator,
        on_response: *const fn (ctx: ?*anyopaque, response: client_mod.HttpClient.Response) void,
        on_error: *const fn (ctx: ?*anyopaque, err: client_mod.HttpClient.HttpError) void,
        ctx: ?*anyopaque,
    ) void {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(impl));

        // Record the request
        self.recorded_requests.append(self.allocator, .{
            .method = req.method,
            .url = req.url,
            .headers = req.headers,
            .body = req.body,
        }) catch {};

        // Return configured error if set
        if (self.error_response) |err| {
            on_error(ctx, err);
            return;
        }

        // Return configured response
        if (self.response) |resp| {
            on_response(ctx, .{
                .status_code = resp.status_code,
                .headers = resp.headers,
                .body = resp.body,
            });
        } else {
            // Default response if none configured
            on_response(ctx, .{
                .status_code = 200,
                .headers = &.{},
                .body = "{}",
            });
        }
    }

    fn doRequestStreaming(
        impl: *anyopaque,
        req: client_mod.HttpClient.Request,
        allocator: std.mem.Allocator,
        callbacks: client_mod.HttpClient.StreamCallbacks,
    ) void {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(impl));

        // Record the request
        self.recorded_requests.append(self.allocator, .{
            .method = req.method,
            .url = req.url,
            .headers = req.headers,
            .body = req.body,
        }) catch {};

        // Return configured error if set
        if (self.error_response) |err| {
            callbacks.on_error(callbacks.ctx, err);
            return;
        }

        // Send headers first
        const status_code: u16 = if (self.response) |r| r.status_code else 200;
        const headers: []const client_mod.HttpClient.Header = if (self.response) |r| r.headers else &.{};

        if (callbacks.on_headers) |on_headers| {
            on_headers(callbacks.ctx, status_code, headers);
        }

        // Send streaming chunks if configured
        if (self.streaming_chunks) |chunks| {
            for (chunks) |chunk| {
                callbacks.on_chunk(callbacks.ctx, chunk);
            }
        } else if (self.response) |resp| {
            // Send body as single chunk if no streaming chunks configured
            callbacks.on_chunk(callbacks.ctx, resp.body);
        }

        // Complete the stream
        callbacks.on_complete(callbacks.ctx);
    }
};

/// Create a MockHttpClient instance
pub fn createMockHttpClient(allocator: std.mem.Allocator) MockHttpClient {
    return MockHttpClient.init(allocator);
}

// Tests

test "MockHttpClient initialization" {
    const allocator = std.testing.allocator;

    var client = MockHttpClient.init(allocator);
    defer client.deinit();

    try std.testing.expectEqual(@as(usize, 0), client.requestCount());
}

test "MockHttpClient records requests" {
    const allocator = std.testing.allocator;

    var client = MockHttpClient.init(allocator);
    defer client.deinit();

    var response_received = false;
    const interface = client.asInterface();

    interface.request(
        .{
            .method = .POST,
            .url = "https://api.example.com/v1/chat",
            .headers = &.{},
            .body = "{\"message\": \"hello\"}",
        },
        allocator,
        struct {
            fn onResponse(ctx: ?*anyopaque, _: client_mod.HttpClient.Response) void {
                const received: *bool = @ptrCast(@alignCast(ctx.?));
                received.* = true;
            }
        }.onResponse,
        struct {
            fn onError(_: ?*anyopaque, _: client_mod.HttpClient.HttpError) void {}
        }.onError,
        &response_received,
    );

    try std.testing.expect(response_received);
    try std.testing.expectEqual(@as(usize, 1), client.requestCount());

    const req = client.lastRequest().?;
    try std.testing.expectEqual(client_mod.HttpClient.Method.POST, req.method);
    try std.testing.expectEqualStrings("https://api.example.com/v1/chat", req.url);
}

test "MockHttpClient returns configured response" {
    const allocator = std.testing.allocator;

    var client = MockHttpClient.init(allocator);
    defer client.deinit();

    client.setResponse(.{
        .status_code = 201,
        .body = "{\"id\": \"123\"}",
    });

    var received_status: u16 = 0;
    var received_body: []const u8 = "";
    const interface = client.asInterface();

    const Context = struct {
        status: *u16,
        body: *[]const u8,
    };

    var ctx = Context{ .status = &received_status, .body = &received_body };

    interface.request(
        .{
            .method = .GET,
            .url = "https://api.example.com/test",
            .headers = &.{},
        },
        allocator,
        struct {
            fn onResponse(c: ?*anyopaque, response: client_mod.HttpClient.Response) void {
                const context: *Context = @ptrCast(@alignCast(c.?));
                context.status.* = response.status_code;
                context.body.* = response.body;
            }
        }.onResponse,
        struct {
            fn onError(_: ?*anyopaque, _: client_mod.HttpClient.HttpError) void {}
        }.onError,
        &ctx,
    );

    try std.testing.expectEqual(@as(u16, 201), received_status);
    try std.testing.expectEqualStrings("{\"id\": \"123\"}", received_body);
}

test "MockHttpClient returns configured error" {
    const allocator = std.testing.allocator;

    var client = MockHttpClient.init(allocator);
    defer client.deinit();

    client.setError(.{
        .kind = .timeout,
        .message = "Request timed out",
    });

    var error_received = false;
    var error_kind: client_mod.HttpClient.HttpError.ErrorKind = .unknown;
    const interface = client.asInterface();

    const Context = struct {
        received: *bool,
        kind: *client_mod.HttpClient.HttpError.ErrorKind,
    };

    var ctx = Context{ .received = &error_received, .kind = &error_kind };

    interface.request(
        .{
            .method = .GET,
            .url = "https://api.example.com/test",
            .headers = &.{},
        },
        allocator,
        struct {
            fn onResponse(_: ?*anyopaque, _: client_mod.HttpClient.Response) void {}
        }.onResponse,
        struct {
            fn onError(c: ?*anyopaque, err: client_mod.HttpClient.HttpError) void {
                const context: *Context = @ptrCast(@alignCast(c.?));
                context.received.* = true;
                context.kind.* = err.kind;
            }
        }.onError,
        &ctx,
    );

    try std.testing.expect(error_received);
    try std.testing.expectEqual(client_mod.HttpClient.HttpError.ErrorKind.timeout, error_kind);
}

test "MockHttpClient streaming sends chunks" {
    const allocator = std.testing.allocator;

    var client = MockHttpClient.init(allocator);
    defer client.deinit();

    const chunks = [_][]const u8{ "chunk1", "chunk2", "chunk3" };
    client.setStreamingChunks(&chunks);

    var received_chunks = std.ArrayList([]const u8){};
    defer received_chunks.deinit(allocator);
    var completed = false;

    const Context = struct {
        chunks: *std.ArrayList([]const u8),
        completed: *bool,
        alloc: std.mem.Allocator,
    };

    var ctx = Context{ .chunks = &received_chunks, .completed = &completed, .alloc = allocator };

    const interface = client.asInterface();
    interface.requestStreaming(
        .{
            .method = .POST,
            .url = "https://api.example.com/stream",
            .headers = &.{},
        },
        allocator,
        .{
            .on_chunk = struct {
                fn onChunk(c: ?*anyopaque, chunk: []const u8) void {
                    const context: *Context = @ptrCast(@alignCast(c.?));
                    context.chunks.append(context.alloc, chunk) catch {};
                }
            }.onChunk,
            .on_complete = struct {
                fn onComplete(c: ?*anyopaque) void {
                    const context: *Context = @ptrCast(@alignCast(c.?));
                    context.completed.* = true;
                }
            }.onComplete,
            .on_error = struct {
                fn onError(_: ?*anyopaque, _: client_mod.HttpClient.HttpError) void {}
            }.onError,
            .ctx = &ctx,
        },
    );

    try std.testing.expect(completed);
    try std.testing.expectEqual(@as(usize, 3), received_chunks.items.len);
    try std.testing.expectEqualStrings("chunk1", received_chunks.items[0]);
    try std.testing.expectEqualStrings("chunk2", received_chunks.items[1]);
    try std.testing.expectEqualStrings("chunk3", received_chunks.items[2]);
}

test "MockHttpClient clearRequests" {
    const allocator = std.testing.allocator;

    var client = MockHttpClient.init(allocator);
    defer client.deinit();

    const interface = client.asInterface();

    // Make some requests
    interface.request(
        .{ .method = .GET, .url = "https://example.com/1", .headers = &.{} },
        allocator,
        struct {
            fn onResponse(_: ?*anyopaque, _: client_mod.HttpClient.Response) void {}
        }.onResponse,
        struct {
            fn onError(_: ?*anyopaque, _: client_mod.HttpClient.HttpError) void {}
        }.onError,
        null,
    );

    interface.request(
        .{ .method = .GET, .url = "https://example.com/2", .headers = &.{} },
        allocator,
        struct {
            fn onResponse(_: ?*anyopaque, _: client_mod.HttpClient.Response) void {}
        }.onResponse,
        struct {
            fn onError(_: ?*anyopaque, _: client_mod.HttpClient.HttpError) void {}
        }.onError,
        null,
    );

    try std.testing.expectEqual(@as(usize, 2), client.requestCount());

    client.clearRequests();

    try std.testing.expectEqual(@as(usize, 0), client.requestCount());
}
