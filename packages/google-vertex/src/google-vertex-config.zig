const std = @import("std");
const provider_utils = @import("provider-utils");
const HttpClient = provider_utils.HttpClient;

/// Configuration for Google Vertex AI API
pub const GoogleVertexConfig = struct {
    /// Provider name
    provider: []const u8 = "google.vertex.chat",

    /// Base URL for API calls
    base_url: []const u8,

    /// Function to get headers.
    /// Caller owns the returned HashMap and must call deinit() when done.
    headers_fn: ?*const fn (*const GoogleVertexConfig, std.mem.Allocator) std.StringHashMap([]const u8) = null,

    /// Custom HTTP client
    http_client: ?HttpClient = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// Express mode base URL (for API key authentication)
pub const express_mode_base_url = "https://aiplatform.googleapis.com/v1/publishers/google";

/// Build the base URL for Google Vertex AI
pub fn buildBaseUrl(
    allocator: std.mem.Allocator,
    project: []const u8,
    location: []const u8,
    api_key: ?[]const u8,
) ![]const u8 {
    if (api_key != null) {
        return express_mode_base_url;
    }

    // For global region, use aiplatform.googleapis.com directly
    // For other regions, use region-aiplatform.googleapis.com
    if (std.mem.eql(u8, location, "global")) {
        return try std.fmt.allocPrint(
            allocator,
            "https://aiplatform.googleapis.com/v1beta1/projects/{s}/locations/{s}/publishers/google",
            .{ project, location },
        );
    }

    return try std.fmt.allocPrint(
        allocator,
        "https://{s}-aiplatform.googleapis.com/v1beta1/projects/{s}/locations/{s}/publishers/google",
        .{ location, project, location },
    );
}

test "buildBaseUrl with global location" {
    const allocator = std.testing.allocator;

    const url = try buildBaseUrl(allocator, "my-project", "global", null);
    defer allocator.free(url);

    try std.testing.expect(std.mem.indexOf(u8, url, "aiplatform.googleapis.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "my-project") != null);
}

test "buildBaseUrl with regional location" {
    const allocator = std.testing.allocator;

    const url = try buildBaseUrl(allocator, "my-project", "us-central1", null);
    defer allocator.free(url);

    try std.testing.expect(std.mem.indexOf(u8, url, "us-central1-aiplatform.googleapis.com") != null);
}

test "buildBaseUrl with API key" {
    const allocator = std.testing.allocator;

    const url = try buildBaseUrl(allocator, "my-project", "us-central1", "my-api-key");

    try std.testing.expectEqualStrings(express_mode_base_url, url);
}
