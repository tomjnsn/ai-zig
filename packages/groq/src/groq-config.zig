const std = @import("std");
const provider_utils = @import("provider-utils");
const HttpClient = provider_utils.HttpClient;

/// Groq API configuration
pub const GroqConfig = struct {
    /// Provider name
    provider: []const u8 = "groq",

    /// Base URL for API calls
    base_url: []const u8 = "https://api.groq.com/openai/v1",

    /// Function to get headers
    headers_fn: ?*const fn (*const GroqConfig, std.mem.Allocator) std.StringHashMap([]const u8) = null,

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

/// Build the transcriptions URL
pub fn buildTranscriptionsUrl(
    allocator: std.mem.Allocator,
    base_url: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/audio/transcriptions", .{base_url});
}

test "buildChatCompletionsUrl" {
    const allocator = std.testing.allocator;
    const url = try buildChatCompletionsUrl(allocator, "https://api.groq.com/openai/v1");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://api.groq.com/openai/v1/chat/completions", url);
}

test "buildTranscriptionsUrl" {
    const allocator = std.testing.allocator;
    const url = try buildTranscriptionsUrl(allocator, "https://api.groq.com/openai/v1");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://api.groq.com/openai/v1/audio/transcriptions", url);
}

test "GroqConfig default values" {
    const config = GroqConfig{};

    try std.testing.expectEqualStrings("groq", config.provider);
    try std.testing.expectEqualStrings("https://api.groq.com/openai/v1", config.base_url);
    try std.testing.expect(config.headers_fn == null);
    try std.testing.expect(config.http_client == null);
    try std.testing.expect(config.generate_id == null);
}

test "GroqConfig custom values" {
    const test_headers_fn = struct {
        fn getHeaders(_: *const GroqConfig, alloc: std.mem.Allocator) std.StringHashMap([]const u8) {
            return std.StringHashMap([]const u8).init(alloc);
        }
    }.getHeaders;

    const config = GroqConfig{
        .provider = "custom-groq",
        .base_url = "https://custom.api.com",
        .headers_fn = test_headers_fn,
    };

    try std.testing.expectEqualStrings("custom-groq", config.provider);
    try std.testing.expectEqualStrings("https://custom.api.com", config.base_url);
    try std.testing.expect(config.headers_fn != null);
}

test "buildChatCompletionsUrl with custom base URL" {
    const allocator = std.testing.allocator;
    const url = try buildChatCompletionsUrl(allocator, "https://custom.groq.com/v2");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://custom.groq.com/v2/chat/completions", url);
}

test "buildChatCompletionsUrl with trailing slash" {
    const allocator = std.testing.allocator;
    const url = try buildChatCompletionsUrl(allocator, "https://api.groq.com/openai/v1/");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://api.groq.com/openai/v1//chat/completions", url);
}

test "buildTranscriptionsUrl with custom base URL" {
    const allocator = std.testing.allocator;
    const url = try buildTranscriptionsUrl(allocator, "https://custom.groq.com/v2");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://custom.groq.com/v2/audio/transcriptions", url);
}

test "buildChatCompletionsUrl with empty base URL" {
    const allocator = std.testing.allocator;
    const url = try buildChatCompletionsUrl(allocator, "");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("/chat/completions", url);
}

test "buildTranscriptionsUrl with empty base URL" {
    const allocator = std.testing.allocator;
    const url = try buildTranscriptionsUrl(allocator, "");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("/audio/transcriptions", url);
}
