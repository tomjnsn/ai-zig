const std = @import("std");
const client_mod = @import("client.zig");

/// HTTP client implementation using Zig 0.15's standard library `std.http.Client`.
///
/// Supports both one-shot (non-streaming) and streaming requests over HTTP/HTTPS
/// with automatic TLS certificate handling.
pub const StdHttpClient = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize a new HTTP client
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// Deinitialize the HTTP client
    pub fn deinit(self: *Self) void {
        _ = self;
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

    /// Map our Method enum to std.http.Method
    fn mapMethod(method: client_mod.HttpClient.Method) std.http.Method {
        return switch (method) {
            .GET => .GET,
            .POST => .POST,
            .PUT => .PUT,
            .DELETE => .DELETE,
            .PATCH => .PATCH,
            .HEAD => .HEAD,
            .OPTIONS => .OPTIONS,
        };
    }

    /// Build extra_headers array from our Header slice.
    /// Returns a slice of std.http.Header pointing into the original data.
    fn buildExtraHeaders(
        headers: []const client_mod.HttpClient.Header,
        buf: []std.http.Header,
    ) []const std.http.Header {
        var count: usize = 0;
        for (headers) |h| {
            // Skip standard headers that std.http.Client handles via .headers
            if (std.ascii.eqlIgnoreCase(h.name, "host")) continue;
            if (std.ascii.eqlIgnoreCase(h.name, "user-agent")) continue;
            if (std.ascii.eqlIgnoreCase(h.name, "connection")) continue;
            if (std.ascii.eqlIgnoreCase(h.name, "accept-encoding")) continue;
            if (std.ascii.eqlIgnoreCase(h.name, "content-type")) continue;
            if (std.ascii.eqlIgnoreCase(h.name, "authorization")) continue;
            if (count >= buf.len) break;
            buf[count] = .{ .name = h.name, .value = h.value };
            count += 1;
        }
        return buf[0..count];
    }

    /// Extract content-type header override if present
    fn getContentType(headers: []const client_mod.HttpClient.Header) std.http.Client.Request.Headers.Value {
        for (headers) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, "content-type")) {
                return .{ .override = h.value };
            }
        }
        return .default;
    }

    /// Extract authorization header override if present
    fn getAuthorization(headers: []const client_mod.HttpClient.Header) std.http.Client.Request.Headers.Value {
        for (headers) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, "authorization")) {
                return .{ .override = h.value };
            }
        }
        return .default;
    }

    /// Collect response headers from the raw head bytes into caller-allocated buffer
    fn collectHeaders(
        head: std.http.Client.Response.Head,
        header_buf: []client_mod.HttpClient.Header,
    ) []const client_mod.HttpClient.Header {
        var count: usize = 0;
        var it = head.iterateHeaders();
        while (it.next()) |h| {
            if (count >= header_buf.len) break;
            header_buf[count] = .{ .name = h.name, .value = h.value };
            count += 1;
        }
        return header_buf[0..count];
    }

    fn doRequest(
        impl: *anyopaque,
        req: client_mod.HttpClient.Request,
        allocator: std.mem.Allocator,
        on_response: *const fn (ctx: ?*anyopaque, response: client_mod.HttpClient.Response) void,
        on_error: *const fn (ctx: ?*anyopaque, err: client_mod.HttpClient.HttpError) void,
        ctx: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Create std.http.Client using the client's own allocator (not the arena)
        var http_client: std.http.Client = .{ .allocator = self.allocator };
        defer http_client.deinit();

        // Build extra headers (exclude standard ones handled by std.http.Client)
        var extra_header_buf: [client_mod.HttpClient.max_header_count]std.http.Header = undefined;
        const extra_headers = buildExtraHeaders(req.headers, &extra_header_buf);

        // Create response body writer
        var response_body: std.Io.Writer.Allocating = .init(allocator);
        defer response_body.deinit();

        // Perform the fetch
        const result = http_client.fetch(.{
            .location = .{ .url = req.url },
            .method = mapMethod(req.method),
            .payload = req.body,
            .extra_headers = extra_headers,
            .headers = .{
                .content_type = getContentType(req.headers),
                .authorization = getAuthorization(req.headers),
            },
            .response_writer = &response_body.writer,
        }) catch |err| {
            on_error(ctx, .{
                .kind = mapFetchError(err),
                .message = @errorName(err),
            });
            return;
        };

        const status_code = @intFromEnum(result.status);
        const body = response_body.written();

        on_response(ctx, .{
            .status_code = status_code,
            .headers = &.{},
            .body = body,
        });
    }

    fn doRequestStreaming(
        impl: *anyopaque,
        req: client_mod.HttpClient.Request,
        allocator: std.mem.Allocator,
        callbacks: client_mod.HttpClient.StreamCallbacks,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = allocator;

        // Create std.http.Client
        var http_client: std.http.Client = .{ .allocator = self.allocator };
        defer http_client.deinit();

        // Parse URI
        const uri = std.Uri.parse(req.url) catch {
            callbacks.on_error(callbacks.ctx, .{
                .kind = .invalid_response,
                .message = "Failed to parse URL",
            });
            return;
        };

        // Build extra headers
        var extra_header_buf: [client_mod.HttpClient.max_header_count]std.http.Header = undefined;
        const extra_headers = buildExtraHeaders(req.headers, &extra_header_buf);

        // Open request
        var http_req = http_client.request(mapMethod(req.method), uri, .{
            .extra_headers = extra_headers,
            .headers = .{
                .content_type = getContentType(req.headers),
                .authorization = getAuthorization(req.headers),
            },
            .keep_alive = false,
        }) catch {
            callbacks.on_error(callbacks.ctx, .{
                .kind = .connection_failed,
                .message = "Failed to open connection",
            });
            return;
        };
        defer http_req.deinit();

        // Send body if present
        if (req.body) |body| {
            http_req.transfer_encoding = .{ .content_length = body.len };
            var bw = http_req.sendBodyUnflushed(&.{}) catch {
                callbacks.on_error(callbacks.ctx, .{
                    .kind = .connection_failed,
                    .message = "Failed to send request head",
                });
                return;
            };
            bw.writer.writeAll(body) catch {
                callbacks.on_error(callbacks.ctx, .{
                    .kind = .connection_failed,
                    .message = "Failed to write request body",
                });
                return;
            };
            bw.end() catch {
                callbacks.on_error(callbacks.ctx, .{
                    .kind = .connection_failed,
                    .message = "Failed to end request body",
                });
                return;
            };
            http_req.connection.?.flush() catch {
                callbacks.on_error(callbacks.ctx, .{
                    .kind = .connection_failed,
                    .message = "Failed to flush connection",
                });
                return;
            };
        } else {
            http_req.sendBodiless() catch {
                callbacks.on_error(callbacks.ctx, .{
                    .kind = .connection_failed,
                    .message = "Failed to send bodiless request",
                });
                return;
            };
        }

        // Receive response head
        var redirect_buf: [0]u8 = .{};
        var response = http_req.receiveHead(&redirect_buf) catch {
            callbacks.on_error(callbacks.ctx, .{
                .kind = .connection_failed,
                .message = "Failed to receive response headers",
            });
            return;
        };

        const status_code = @intFromEnum(response.head.status);

        // Report headers
        if (callbacks.on_headers) |on_headers| {
            var header_buf: [client_mod.HttpClient.max_header_count]client_mod.HttpClient.Header = undefined;
            const resp_headers = collectHeaders(response.head, &header_buf);
            on_headers(callbacks.ctx, status_code, resp_headers);
        }

        // Read response body in chunks
        var transfer_buf: [8192]u8 = undefined;
        var chunk_reader = response.reader(&transfer_buf);

        var read_buf: [8192]u8 = undefined;
        while (true) {
            var write_target = std.Io.Writer.fixed(&read_buf);
            const n = chunk_reader.stream(&write_target, .unlimited) catch |err| switch (err) {
                error.EndOfStream => break,
                error.ReadFailed => {
                    callbacks.on_error(callbacks.ctx, .{
                        .kind = .connection_failed,
                        .message = "Failed to read response body",
                    });
                    return;
                },
                error.WriteFailed => {
                    // Buffer full - deliver what we have and reset
                    callbacks.on_chunk(callbacks.ctx, &read_buf);
                    continue;
                },
            };
            if (n == 0) continue;
            callbacks.on_chunk(callbacks.ctx, read_buf[0..n]);
        }

        // Deliver any remaining buffered data from the reader
        const remaining = chunk_reader.buffered();
        if (remaining.len > 0) {
            callbacks.on_chunk(callbacks.ctx, remaining);
        }

        callbacks.on_complete(callbacks.ctx);
    }

    /// Map fetch errors to our error kinds
    fn mapFetchError(err: std.http.Client.FetchError) client_mod.HttpClient.HttpError.ErrorKind {
        return switch (err) {
            error.ConnectionRefused,
            error.ConnectionTimedOut,
            error.NetworkUnreachable,
            error.ConnectionResetByPeer,
            => .connection_failed,

            error.TlsInitializationFailed,
            error.CertificateBundleLoadFailure,
            => .ssl_error,

            error.HttpRedirectLocationOversize,
            error.TooManyHttpRedirects,
            error.RedirectRequiresResend,
            => .too_many_redirects,

            error.StreamTooLong => .response_too_large,

            error.WriteFailed, error.ReadFailed => .connection_failed,

            error.UnsupportedCompressionMethod => .invalid_response,

            else => .unknown,
        };
    }
};

/// Create a StdHttpClient instance
pub fn createStdHttpClient(allocator: std.mem.Allocator) StdHttpClient {
    return StdHttpClient.init(allocator);
}

test "StdHttpClient initialization" {
    const allocator = std.testing.allocator;

    var client = StdHttpClient.init(allocator);
    defer client.deinit();

    const interface = client.asInterface();
    _ = interface;
}
