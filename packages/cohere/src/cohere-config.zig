const std = @import("std");
const provider_utils = @import("provider-utils");
const HttpClient = provider_utils.HttpClient;

/// Cohere API configuration
pub const CohereConfig = struct {
    /// Provider name
    provider: []const u8 = "cohere",

    /// Base URL for API calls
    base_url: []const u8 = "https://api.cohere.com/v2",

    /// Function to get headers.
    /// Caller owns the returned HashMap and must call deinit() when done.
    headers_fn: ?*const fn (*const CohereConfig, std.mem.Allocator) std.StringHashMap([]const u8) = null,

    /// HTTP client (optional)
    http_client: ?HttpClient = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// Build the chat URL
pub fn buildChatUrl(
    allocator: std.mem.Allocator,
    base_url: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/chat", .{base_url});
}

/// Build the embed URL
pub fn buildEmbedUrl(
    allocator: std.mem.Allocator,
    base_url: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/embed", .{base_url});
}

/// Build the rerank URL
pub fn buildRerankUrl(
    allocator: std.mem.Allocator,
    base_url: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/rerank", .{base_url});
}

test "buildChatUrl" {
    const allocator = std.testing.allocator;
    const url = try buildChatUrl(allocator, "https://api.cohere.com/v2");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://api.cohere.com/v2/chat", url);
}

test "buildEmbedUrl" {
    const allocator = std.testing.allocator;
    const url = try buildEmbedUrl(allocator, "https://api.cohere.com/v2");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://api.cohere.com/v2/embed", url);
}

test "buildRerankUrl" {
    const allocator = std.testing.allocator;
    const url = try buildRerankUrl(allocator, "https://api.cohere.com/v2");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://api.cohere.com/v2/rerank", url);
}
