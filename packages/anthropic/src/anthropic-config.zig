const std = @import("std");
const provider_utils = @import("provider-utils");

/// Anthropic API configuration
pub const AnthropicConfig = struct {
    /// Provider name (e.g. "anthropic.messages")
    provider: []const u8,

    /// Base URL for API calls
    base_url: []const u8,

    /// Function to get headers
    headers_fn: *const fn (*const AnthropicConfig, std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8),

    /// Optional HTTP client
    http_client: ?provider_utils.HttpClient = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,

    /// Build a URL for the API
    pub fn buildUrl(self: *const AnthropicConfig, allocator: std.mem.Allocator, path: []const u8, model_id: []const u8) ![]u8 {
        _ = model_id;
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ self.base_url, path });
    }

    /// Get headers for a request
    pub fn getHeaders(self: *const AnthropicConfig, allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
        return self.headers_fn(self, allocator);
    }
};

/// Default Anthropic API version
pub const anthropic_version = "2024-06-01";

/// Default base URL
pub const default_base_url = "https://api.anthropic.com/v1";

test "AnthropicConfig buildUrl" {
    const allocator = std.testing.allocator;

    const config = AnthropicConfig{
        .provider = "anthropic.messages",
        .base_url = "https://api.anthropic.com/v1",
        .headers_fn = struct {
            fn getHeaders(_: *const AnthropicConfig, alloc: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(alloc);
            }
        }.getHeaders,
    };

    const url = try config.buildUrl(allocator, "/messages", "claude-3-5-sonnet-latest");
    defer allocator.free(url);

    try std.testing.expectEqualStrings("https://api.anthropic.com/v1/messages", url);
}
