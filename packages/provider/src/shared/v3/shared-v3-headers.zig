const std = @import("std");

/// HTTP headers as a string map.
/// Used for custom headers passed to API calls.
pub const SharedV3Headers = std.StringHashMap([]const u8);

/// Create a new empty headers map
pub fn createHeaders(allocator: std.mem.Allocator) SharedV3Headers {
    return SharedV3Headers.init(allocator);
}

/// Create headers from a slice of key-value pairs
pub fn headersFromSlice(allocator: std.mem.Allocator, pairs: []const [2][]const u8) !SharedV3Headers {
    var headers = SharedV3Headers.init(allocator);
    errdefer headers.deinit();

    for (pairs) |pair| {
        try headers.put(pair[0], pair[1]);
    }

    return headers;
}

/// Get a header value by name (case-sensitive)
pub fn getHeader(headers: SharedV3Headers, name: []const u8) ?[]const u8 {
    return headers.get(name);
}

/// Set a header value
pub fn setHeader(headers: *SharedV3Headers, name: []const u8, value: []const u8) !void {
    try headers.put(name, value);
}

/// Remove a header
pub fn removeHeader(headers: *SharedV3Headers, name: []const u8) bool {
    return headers.remove(name);
}

/// Merge two header maps
/// Values from `other` will override values in `base` for the same keys
pub fn mergeHeaders(
    allocator: std.mem.Allocator,
    base: SharedV3Headers,
    other: SharedV3Headers,
) !SharedV3Headers {
    var result = SharedV3Headers.init(allocator);
    errdefer result.deinit();

    // Copy base
    var base_iter = base.iterator();
    while (base_iter.next()) |entry| {
        try result.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    // Merge/override with other
    var other_iter = other.iterator();
    while (other_iter.next()) |entry| {
        try result.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    return result;
}

/// Convert headers to a slice for HTTP client use
pub fn headersToSlice(headers: SharedV3Headers, allocator: std.mem.Allocator) ![]const [2][]const u8 {
    var list = std.ArrayList([2][]const u8).empty;
    errdefer list.deinit(allocator);

    var iter = headers.iterator();
    while (iter.next()) |entry| {
        try list.append(allocator, .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    return list.toOwnedSlice(allocator);
}

/// Check if a header exists
pub fn hasHeader(headers: SharedV3Headers, name: []const u8) bool {
    return headers.contains(name);
}

test "SharedV3Headers creation and manipulation" {
    const allocator = std.testing.allocator;

    var headers = createHeaders(allocator);
    defer headers.deinit();

    try setHeader(&headers, "Content-Type", "application/json");
    try setHeader(&headers, "Authorization", "Bearer token123");

    try std.testing.expectEqualStrings("application/json", getHeader(headers, "Content-Type").?);
    try std.testing.expectEqualStrings("Bearer token123", getHeader(headers, "Authorization").?);
    try std.testing.expect(hasHeader(headers, "Content-Type"));
    try std.testing.expect(!hasHeader(headers, "X-Custom"));
}

test "SharedV3Headers merge" {
    const allocator = std.testing.allocator;

    var base = createHeaders(allocator);
    defer base.deinit();
    try setHeader(&base, "Content-Type", "text/plain");
    try setHeader(&base, "Accept", "application/json");

    var other = createHeaders(allocator);
    defer other.deinit();
    try setHeader(&other, "Content-Type", "application/json"); // Override
    try setHeader(&other, "Authorization", "Bearer token");

    var merged = try mergeHeaders(allocator, base, other);
    defer merged.deinit();

    try std.testing.expectEqualStrings("application/json", getHeader(merged, "Content-Type").?);
    try std.testing.expectEqualStrings("application/json", getHeader(merged, "Accept").?);
    try std.testing.expectEqualStrings("Bearer token", getHeader(merged, "Authorization").?);
}
