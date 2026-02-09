const std = @import("std");

/// Validate a URL for use as an API endpoint.
/// Checks scheme, basic structure, and optionally rejects non-HTTPS URLs.
pub fn validateUrl(url: []const u8, allow_http: bool) !void {
    // TODO: Implement validation
    _ = url;
    _ = allow_http;
}

/// Normalize a URL by removing duplicate slashes in the path portion.
/// Caller owns the returned slice if it differs from input.
pub fn normalizeUrl(url: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // TODO: Implement normalization
    _ = allocator;
    return url;
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
