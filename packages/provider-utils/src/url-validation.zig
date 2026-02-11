const std = @import("std");

/// Validate a URL for use as an API endpoint.
/// Checks scheme, basic structure, and optionally rejects non-HTTPS URLs.
pub fn validateUrl(url: []const u8, allow_http: bool) !void {
    if (url.len == 0) return error.InvalidUrl;

    // Check for valid scheme
    if (std.mem.startsWith(u8, url, "https://")) {
        if (url.len <= "https://".len) return error.InvalidUrl;
        return; // valid
    }

    if (std.mem.startsWith(u8, url, "http://")) {
        if (url.len <= "http://".len) return error.InvalidUrl;
        if (!allow_http) return error.InsecureUrl;
        return; // valid when http is allowed
    }

    // No valid scheme found
    return error.InvalidUrl;
}

/// Normalize a URL by removing duplicate slashes in the path portion.
/// Preserves the double slash after the scheme (e.g., "https://").
/// Caller owns the returned slice if it differs from input.
pub fn normalizeUrl(url: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // Find the start of the path (after "scheme://host")
    const scheme_end = std.mem.indexOf(u8, url, "://") orelse return url;
    const after_scheme = scheme_end + 3; // skip "://"

    // Find the first slash after the host
    const path_start = std.mem.indexOfScalarPos(u8, url, after_scheme, '/') orelse return url;

    // Check if there are any duplicate slashes in the path
    var has_duplicates = false;
    var i: usize = path_start;
    while (i < url.len - 1) : (i += 1) {
        if (url[i] == '/' and url[i + 1] == '/') {
            has_duplicates = true;
            break;
        }
    }

    if (!has_duplicates) return url;

    // Build normalized URL
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    // Copy everything up to and including the first path slash
    try result.appendSlice(allocator, url[0 .. path_start + 1]);

    // Copy path, collapsing duplicate slashes
    var prev_was_slash = true; // we just wrote the first slash
    for (url[path_start + 1 ..]) |c| {
        if (c == '/' and prev_was_slash) continue;
        try result.append(allocator, c);
        prev_was_slash = (c == '/');
    }

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "validateUrl accepts valid https URL" {
    try validateUrl("https://api.example.com/v1/chat", false);
    try validateUrl("https://api.openai.com", false);
}

test "validateUrl rejects http URL when not allowed" {
    const result = validateUrl("http://api.example.com/v1/chat", false);
    try std.testing.expectError(error.InsecureUrl, result);
}

test "validateUrl allows http URL when explicitly permitted" {
    try validateUrl("http://localhost:8080/api", true);
}

test "validateUrl rejects malformed URL" {
    try std.testing.expectError(error.InvalidUrl, validateUrl("", false));
    try std.testing.expectError(error.InvalidUrl, validateUrl("not-a-url", false));
    try std.testing.expectError(error.InvalidUrl, validateUrl("://missing-scheme", false));
    try std.testing.expectError(error.InvalidUrl, validateUrl("ftp://example.com", false));
}

test "normalizeUrl removes duplicate slashes in path" {
    const allocator = std.testing.allocator;

    const result = try normalizeUrl("https://api.example.com//v1///chat", allocator);
    defer if (result.ptr != "https://api.example.com//v1///chat".ptr) allocator.free(result);

    try std.testing.expectEqualStrings("https://api.example.com/v1/chat", result);
}

test "normalizeUrl preserves valid URL" {
    const allocator = std.testing.allocator;
    const input = "https://api.example.com/v1/chat";

    const result = try normalizeUrl(input, allocator);
    // Should return the same pointer since no normalization needed
    try std.testing.expectEqualStrings(input, result);
}
