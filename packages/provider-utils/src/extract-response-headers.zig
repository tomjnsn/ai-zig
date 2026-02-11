const std = @import("std");
const http_client = @import("http/client.zig");

/// Extract headers from a response into a hash map.
/// Returns a map of header name to value pairs.
pub fn extractResponseHeaders(
    allocator: std.mem.Allocator,
    headers: []const http_client.HttpClient.Header,
) !std.StringHashMap([]const u8) {
    var result = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var it = result.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        result.deinit();
    }

    for (headers) |header| {
        // Duplicate the value to ensure it's owned by the allocator
        const value = try allocator.dupe(u8, header.value);
        errdefer allocator.free(value);

        // Check if key already exists
        if (result.getPtr(header.name)) |existing_value| {
            // Free the old value and replace it
            allocator.free(existing_value.*);
            existing_value.* = value;
        } else {
            // New key, duplicate the name
            const name = try allocator.dupe(u8, header.name);
            errdefer allocator.free(name);
            try result.put(name, value);
        }
    }

    return result;
}

/// Extract headers from a response into a slice of Header structs.
/// This is useful when you want to preserve the original format.
pub fn extractResponseHeadersSlice(
    allocator: std.mem.Allocator,
    headers: []const http_client.HttpClient.Header,
) ![]http_client.HttpClient.Header {
    const result = try allocator.alloc(http_client.HttpClient.Header, headers.len);
    var initialized: usize = 0;
    errdefer {
        for (result[0..initialized]) |header| {
            allocator.free(header.name);
            allocator.free(header.value);
        }
        allocator.free(result);
    }

    for (headers, 0..) |header, i| {
        const name = try allocator.dupe(u8, header.name);
        errdefer allocator.free(name);
        const value = try allocator.dupe(u8, header.value);
        result[i] = .{ .name = name, .value = value };
        initialized = i + 1;
    }

    return result;
}

/// Get a specific header value by name (case-insensitive).
pub fn getHeaderValue(
    headers: []const http_client.HttpClient.Header,
    name: []const u8,
) ?[]const u8 {
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) {
            return header.value;
        }
    }
    return null;
}

/// Get the Content-Type header value
pub fn getContentType(
    headers: []const http_client.HttpClient.Header,
) ?[]const u8 {
    return getHeaderValue(headers, "Content-Type");
}

/// Get the Content-Length header value as an integer
pub fn getContentLength(
    headers: []const http_client.HttpClient.Header,
) ?u64 {
    if (getHeaderValue(headers, "Content-Length")) |value| {
        return std.fmt.parseInt(u64, value, 10) catch null;
    }
    return null;
}

/// Check if the response has a specific content type
pub fn hasContentType(
    headers: []const http_client.HttpClient.Header,
    content_type: []const u8,
) bool {
    if (getContentType(headers)) |ct| {
        // Check if content type starts with the expected type
        // This handles cases like "application/json; charset=utf-8"
        return std.mem.startsWith(u8, ct, content_type);
    }
    return false;
}

/// Check if the response is JSON
pub fn isJsonResponse(
    headers: []const http_client.HttpClient.Header,
) bool {
    return hasContentType(headers, "application/json");
}

/// Check if the response is a server-sent events stream
pub fn isEventStreamResponse(
    headers: []const http_client.HttpClient.Header,
) bool {
    return hasContentType(headers, "text/event-stream");
}

/// Extract common response metadata
pub const ResponseMetadata = struct {
    content_type: ?[]const u8,
    content_length: ?u64,
    request_id: ?[]const u8,
    rate_limit_remaining: ?u32,
    rate_limit_reset: ?i64,
};

pub fn extractResponseMetadata(
    headers: []const http_client.HttpClient.Header,
) ResponseMetadata {
    return .{
        .content_type = getContentType(headers),
        .content_length = getContentLength(headers),
        .request_id = getHeaderValue(headers, "X-Request-Id") orelse
            getHeaderValue(headers, "x-request-id"),
        .rate_limit_remaining = if (getHeaderValue(headers, "X-RateLimit-Remaining")) |v|
            std.fmt.parseInt(u32, v, 10) catch null
        else
            null,
        .rate_limit_reset = if (getHeaderValue(headers, "X-RateLimit-Reset")) |v|
            std.fmt.parseInt(i64, v, 10) catch null
        else
            null,
    };
}

test "extractResponseHeaders" {
    const allocator = std.testing.allocator;

    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "X-Request-Id", .value = "abc123" },
    };

    var extracted = try extractResponseHeaders(allocator, &headers);
    defer {
        var iter = extracted.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        extracted.deinit();
    }

    try std.testing.expectEqualStrings("application/json", extracted.get("Content-Type").?);
    try std.testing.expectEqualStrings("abc123", extracted.get("X-Request-Id").?);
}

test "getHeaderValue case insensitive" {
    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    try std.testing.expectEqualStrings(
        "application/json",
        getHeaderValue(&headers, "content-type").?,
    );
    try std.testing.expectEqualStrings(
        "application/json",
        getHeaderValue(&headers, "CONTENT-TYPE").?,
    );
}

test "isJsonResponse" {
    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Content-Type", .value = "application/json; charset=utf-8" },
    };

    try std.testing.expect(isJsonResponse(&headers));
    try std.testing.expect(!isEventStreamResponse(&headers));
}

test "isEventStreamResponse" {
    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Content-Type", .value = "text/event-stream" },
    };

    try std.testing.expect(isEventStreamResponse(&headers));
    try std.testing.expect(!isJsonResponse(&headers));
}

test "extractResponseHeadersSlice" {
    const allocator = std.testing.allocator;

    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "X-Custom", .value = "test" },
    };

    const extracted = try extractResponseHeadersSlice(allocator, &headers);
    defer {
        for (extracted) |header| {
            allocator.free(header.name);
            allocator.free(header.value);
        }
        allocator.free(extracted);
    }

    try std.testing.expectEqual(@as(usize, 2), extracted.len);
}

test "getContentLength" {
    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Content-Length", .value = "12345" },
    };

    const length = getContentLength(&headers);
    try std.testing.expect(length != null);
    try std.testing.expectEqual(@as(u64, 12345), length.?);
}

test "getContentLength invalid" {
    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Content-Length", .value = "invalid" },
    };

    const length = getContentLength(&headers);
    try std.testing.expect(length == null);
}

test "getContentLength missing" {
    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    const length = getContentLength(&headers);
    try std.testing.expect(length == null);
}

test "hasContentType with charset" {
    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Content-Type", .value = "application/json; charset=utf-8" },
    };

    try std.testing.expect(hasContentType(&headers, "application/json"));
    try std.testing.expect(!hasContentType(&headers, "text/plain"));
}

test "extractResponseMetadata complete" {
    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Content-Length", .value = "100" },
        .{ .name = "X-Request-Id", .value = "req-123" },
        .{ .name = "X-RateLimit-Remaining", .value = "50" },
        .{ .name = "X-RateLimit-Reset", .value = "1234567890" },
    };

    const metadata = extractResponseMetadata(&headers);

    try std.testing.expect(metadata.content_type != null);
    try std.testing.expectEqualStrings("application/json", metadata.content_type.?);
    try std.testing.expect(metadata.content_length != null);
    try std.testing.expectEqual(@as(u64, 100), metadata.content_length.?);
    try std.testing.expect(metadata.request_id != null);
    try std.testing.expectEqualStrings("req-123", metadata.request_id.?);
    try std.testing.expect(metadata.rate_limit_remaining != null);
    try std.testing.expectEqual(@as(u32, 50), metadata.rate_limit_remaining.?);
    try std.testing.expect(metadata.rate_limit_reset != null);
    try std.testing.expectEqual(@as(i64, 1234567890), metadata.rate_limit_reset.?);
}

test "extractResponseMetadata minimal" {
    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Server", .value = "nginx" },
    };

    const metadata = extractResponseMetadata(&headers);

    try std.testing.expect(metadata.content_type == null);
    try std.testing.expect(metadata.content_length == null);
    try std.testing.expect(metadata.request_id == null);
    try std.testing.expect(metadata.rate_limit_remaining == null);
    try std.testing.expect(metadata.rate_limit_reset == null);
}

test "getHeaderValue not found" {
    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    try std.testing.expect(getHeaderValue(&headers, "X-Missing") == null);
}

test "isJsonResponse with different cases" {
    const headers1 = [_]http_client.HttpClient.Header{
        .{ .name = "content-type", .value = "application/json" },
    };

    const headers2 = [_]http_client.HttpClient.Header{
        .{ .name = "CONTENT-TYPE", .value = "application/json" },
    };

    try std.testing.expect(isJsonResponse(&headers1));
    try std.testing.expect(isJsonResponse(&headers2));
}

test "extractResponseHeaders duplicate keys" {
    const allocator = std.testing.allocator;

    const headers = [_]http_client.HttpClient.Header{
        .{ .name = "Set-Cookie", .value = "cookie1=value1" },
        .{ .name = "Set-Cookie", .value = "cookie2=value2" },
    };

    var extracted = try extractResponseHeaders(allocator, &headers);
    defer {
        var iter = extracted.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        extracted.deinit();
    }

    // HashMap will only keep the last value for duplicate keys
    try std.testing.expectEqual(@as(usize, 1), extracted.count());
}
