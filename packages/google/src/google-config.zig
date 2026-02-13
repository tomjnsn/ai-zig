const std = @import("std");
const provider_utils = @import("provider-utils");
const HttpClient = provider_utils.HttpClient;

/// Configuration for Google Generative AI API
pub const GoogleGenerativeAIConfig = struct {
    /// Provider name
    provider: []const u8 = "google.generative-ai",

    /// Base URL for API calls
    base_url: []const u8 = default_base_url,

    /// API key for authenticating requests (preferred over env var)
    api_key: ?[]const u8 = null,

    /// Function to get headers.
    /// Caller owns the returned HashMap and must call deinit() when done.
    headers_fn: ?*const fn (*const GoogleGenerativeAIConfig, std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) = null,

    /// Custom HTTP client
    http_client: ?HttpClient = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// Default base URL for Google Generative AI API
pub const default_base_url = "https://generativelanguage.googleapis.com/v1beta";

/// API version string
pub const google_ai_version = "v1beta";

test "GoogleGenerativeAIConfig defaults" {
    const config = GoogleGenerativeAIConfig{};
    try std.testing.expectEqualStrings("google.generative-ai", config.provider);
    try std.testing.expectEqualStrings(default_base_url, config.base_url);
}
