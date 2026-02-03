const std = @import("std");
const provider_utils = @import("provider-utils");
const HttpClient = provider_utils.HttpClient;

/// Configuration for Amazon Bedrock API
pub const BedrockConfig = struct {
    /// Provider name
    provider: []const u8 = "bedrock",

    /// Base URL for Bedrock runtime
    base_url: []const u8,

    /// AWS region
    region: []const u8 = "us-east-1",

    /// Function to get headers.
    /// Caller owns the returned HashMap and must call deinit() when done.
    headers_fn: ?*const fn (*const BedrockConfig, std.mem.Allocator) std.StringHashMap([]const u8) = null,

    /// Custom HTTP client
    http_client: ?HttpClient = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// AWS credentials for SigV4 authentication
pub const BedrockCredentials = struct {
    region: []const u8,
    access_key_id: []const u8,
    secret_access_key: []const u8,
    session_token: ?[]const u8 = null,
};

/// Build Bedrock runtime base URL
pub fn buildBedrockRuntimeUrl(allocator: std.mem.Allocator, region: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "https://bedrock-runtime.{s}.amazonaws.com",
        .{region},
    );
}

/// Build Bedrock agent runtime base URL
pub fn buildBedrockAgentRuntimeUrl(allocator: std.mem.Allocator, region: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "https://bedrock-agent-runtime.{s}.amazonaws.com",
        .{region},
    );
}

/// Build converse API URL
pub fn buildConverseUrl(allocator: std.mem.Allocator, base_url: []const u8, model_id: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{s}/model/{s}/converse",
        .{ base_url, model_id },
    );
}

/// Build converse stream API URL
pub fn buildConverseStreamUrl(allocator: std.mem.Allocator, base_url: []const u8, model_id: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{s}/model/{s}/converse-stream",
        .{ base_url, model_id },
    );
}

/// Build invoke model URL (for embeddings)
pub fn buildInvokeModelUrl(allocator: std.mem.Allocator, base_url: []const u8, model_id: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{s}/model/{s}/invoke",
        .{ base_url, model_id },
    );
}

test "buildBedrockRuntimeUrl" {
    const allocator = std.testing.allocator;

    const url = try buildBedrockRuntimeUrl(allocator, "us-east-1");
    defer allocator.free(url);

    try std.testing.expectEqualStrings("https://bedrock-runtime.us-east-1.amazonaws.com", url);
}

test "buildConverseUrl" {
    const allocator = std.testing.allocator;

    const url = try buildConverseUrl(
        allocator,
        "https://bedrock-runtime.us-east-1.amazonaws.com",
        "anthropic.claude-3-sonnet-20240229-v1:0",
    );
    defer allocator.free(url);

    try std.testing.expect(std.mem.indexOf(u8, url, "/model/anthropic.claude-3-sonnet") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "/converse") != null);
}
