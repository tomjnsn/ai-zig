const std = @import("std");
const provider_utils = @import("provider-utils");
const HttpClient = provider_utils.HttpClient;

/// OpenAI-compatible API configuration
pub const OpenAICompatibleConfig = struct {
    /// Provider name
    provider: []const u8 = "openai-compatible",

    /// Base URL for API calls
    base_url: []const u8,

    /// Function to get headers.
    /// Caller owns the returned HashMap and must call deinit() when done.
    headers_fn: ?*const fn (*const OpenAICompatibleConfig, std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) = null,

    /// HTTP client (optional)
    http_client: ?HttpClient = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// Build the chat completions URL
pub fn buildChatCompletionsUrl(
    allocator: std.mem.Allocator,
    base_url: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/chat/completions", .{base_url});
}

/// Build the completions URL
pub fn buildCompletionsUrl(
    allocator: std.mem.Allocator,
    base_url: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/completions", .{base_url});
}

/// Build the embeddings URL
pub fn buildEmbeddingsUrl(
    allocator: std.mem.Allocator,
    base_url: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/embeddings", .{base_url});
}

/// Build the images generations URL
pub fn buildImagesGenerationsUrl(
    allocator: std.mem.Allocator,
    base_url: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/images/generations", .{base_url});
}

test "buildChatCompletionsUrl" {
    const allocator = std.testing.allocator;
    const url = try buildChatCompletionsUrl(allocator, "https://api.example.com/v1");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://api.example.com/v1/chat/completions", url);
}
