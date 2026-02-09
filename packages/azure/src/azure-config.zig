const std = @import("std");
const provider_utils = @import("provider-utils");
const HttpClient = provider_utils.HttpClient;

/// Configuration for Azure OpenAI API
pub const AzureOpenAIConfig = struct {
    /// Provider name
    provider: []const u8 = "azure.chat",

    /// Base URL for API calls
    base_url: []const u8,

    /// API version
    api_version: []const u8 = "v1",

    /// Use deployment-based URLs
    use_deployment_based_urls: bool = false,

    /// Function to get headers.
    /// Caller owns the returned HashMap and must call deinit() when done.
    headers_fn: ?*const fn (*const AzureOpenAIConfig, std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) = null,

    /// Custom HTTP client
    http_client: ?HttpClient = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// Build Azure OpenAI URL
pub fn buildAzureUrl(
    allocator: std.mem.Allocator,
    config: *const AzureOpenAIConfig,
    path: []const u8,
    model_id: []const u8,
) ![]const u8 {
    if (config.use_deployment_based_urls) {
        // Use deployment-based format: {baseURL}/deployments/{deploymentId}{path}?api-version={apiVersion}
        return try std.fmt.allocPrint(
            allocator,
            "{s}/deployments/{s}{s}?api-version={s}",
            .{ config.base_url, model_id, path, config.api_version },
        );
    }

    // Use v1 API format: {baseURL}/v1{path}?api-version={apiVersion}
    return try std.fmt.allocPrint(
        allocator,
        "{s}/v1{s}?api-version={s}",
        .{ config.base_url, path, config.api_version },
    );
}

/// Build base URL from resource name
pub fn buildBaseUrlFromResourceName(allocator: std.mem.Allocator, resource_name: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "https://{s}.openai.azure.com/openai",
        .{resource_name},
    );
}

test "AzureOpenAIConfig default values" {
    const config = AzureOpenAIConfig{
        .base_url = "https://test.openai.azure.com/openai",
    };

    try std.testing.expectEqualStrings("azure.chat", config.provider);
    try std.testing.expectEqualStrings("v1", config.api_version);
    try std.testing.expectEqual(false, config.use_deployment_based_urls);
    try std.testing.expectEqual(null, config.headers_fn);
    try std.testing.expectEqual(null, config.http_client);
    try std.testing.expectEqual(null, config.generate_id);
}

test "AzureOpenAIConfig custom values" {
    const config = AzureOpenAIConfig{
        .provider = "azure.custom",
        .base_url = "https://custom.openai.azure.com/openai",
        .api_version = "2024-03-01-preview",
        .use_deployment_based_urls = true,
    };

    try std.testing.expectEqualStrings("azure.custom", config.provider);
    try std.testing.expectEqualStrings("https://custom.openai.azure.com/openai", config.base_url);
    try std.testing.expectEqualStrings("2024-03-01-preview", config.api_version);
    try std.testing.expectEqual(true, config.use_deployment_based_urls);
}

test "buildAzureUrl with v1 API" {
    const allocator = std.testing.allocator;

    const config = AzureOpenAIConfig{
        .base_url = "https://myresource.openai.azure.com/openai",
        .api_version = "2024-02-15-preview",
        .use_deployment_based_urls = false,
    };

    const url = try buildAzureUrl(allocator, &config, "/chat/completions", "gpt-4");
    defer allocator.free(url);

    try std.testing.expect(std.mem.indexOf(u8, url, "/v1/chat/completions") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "api-version=2024-02-15-preview") != null);
    try std.testing.expectEqualStrings("https://myresource.openai.azure.com/openai/v1/chat/completions?api-version=2024-02-15-preview", url);
}

test "buildAzureUrl with deployment-based URLs" {
    const allocator = std.testing.allocator;

    const config = AzureOpenAIConfig{
        .base_url = "https://myresource.openai.azure.com/openai",
        .api_version = "2024-02-15-preview",
        .use_deployment_based_urls = true,
    };

    const url = try buildAzureUrl(allocator, &config, "/chat/completions", "gpt-4");
    defer allocator.free(url);

    try std.testing.expect(std.mem.indexOf(u8, url, "/deployments/gpt-4/chat/completions") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "api-version=2024-02-15-preview") != null);
    try std.testing.expectEqualStrings("https://myresource.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview", url);
}

test "buildAzureUrl with different paths" {
    const allocator = std.testing.allocator;

    const config = AzureOpenAIConfig{
        .base_url = "https://myresource.openai.azure.com/openai",
        .api_version = "v1",
        .use_deployment_based_urls = false,
    };

    // Test embeddings path
    {
        const url = try buildAzureUrl(allocator, &config, "/embeddings", "text-embedding-ada-002");
        defer allocator.free(url);
        try std.testing.expectEqualStrings("https://myresource.openai.azure.com/openai/v1/embeddings?api-version=v1", url);
    }

    // Test images path
    {
        const url = try buildAzureUrl(allocator, &config, "/images/generations", "dall-e-3");
        defer allocator.free(url);
        try std.testing.expectEqualStrings("https://myresource.openai.azure.com/openai/v1/images/generations?api-version=v1", url);
    }

    // Test audio path
    {
        const url = try buildAzureUrl(allocator, &config, "/audio/transcriptions", "whisper-1");
        defer allocator.free(url);
        try std.testing.expectEqualStrings("https://myresource.openai.azure.com/openai/v1/audio/transcriptions?api-version=v1", url);
    }
}

test "buildAzureUrl with deployment-based URLs different paths" {
    const allocator = std.testing.allocator;

    const config = AzureOpenAIConfig{
        .base_url = "https://myresource.openai.azure.com/openai",
        .api_version = "2024-02-15-preview",
        .use_deployment_based_urls = true,
    };

    // Test embeddings path
    {
        const url = try buildAzureUrl(allocator, &config, "/embeddings", "embedding-deployment");
        defer allocator.free(url);
        try std.testing.expectEqualStrings("https://myresource.openai.azure.com/openai/deployments/embedding-deployment/embeddings?api-version=2024-02-15-preview", url);
    }

    // Test images path
    {
        const url = try buildAzureUrl(allocator, &config, "/images/generations", "dalle-deployment");
        defer allocator.free(url);
        try std.testing.expectEqualStrings("https://myresource.openai.azure.com/openai/deployments/dalle-deployment/images/generations?api-version=2024-02-15-preview", url);
    }
}

test "buildAzureUrl with special characters in model_id" {
    const allocator = std.testing.allocator;

    const config = AzureOpenAIConfig{
        .base_url = "https://myresource.openai.azure.com/openai",
        .api_version = "v1",
        .use_deployment_based_urls = true,
    };

    const url = try buildAzureUrl(allocator, &config, "/chat/completions", "gpt-4-turbo-preview");
    defer allocator.free(url);

    try std.testing.expect(std.mem.indexOf(u8, url, "/deployments/gpt-4-turbo-preview/chat/completions") != null);
}

test "buildAzureUrl with empty path" {
    const allocator = std.testing.allocator;

    const config = AzureOpenAIConfig{
        .base_url = "https://myresource.openai.azure.com/openai",
        .api_version = "v1",
        .use_deployment_based_urls = false,
    };

    const url = try buildAzureUrl(allocator, &config, "", "gpt-4");
    defer allocator.free(url);

    try std.testing.expectEqualStrings("https://myresource.openai.azure.com/openai/v1?api-version=v1", url);
}

test "buildBaseUrlFromResourceName" {
    const allocator = std.testing.allocator;

    const url = try buildBaseUrlFromResourceName(allocator, "myresource");
    defer allocator.free(url);

    try std.testing.expectEqualStrings("https://myresource.openai.azure.com/openai", url);
}

test "buildBaseUrlFromResourceName with different resource names" {
    const allocator = std.testing.allocator;

    // Test simple name
    {
        const url = try buildBaseUrlFromResourceName(allocator, "test");
        defer allocator.free(url);
        try std.testing.expectEqualStrings("https://test.openai.azure.com/openai", url);
    }

    // Test name with dashes
    {
        const url = try buildBaseUrlFromResourceName(allocator, "my-resource-123");
        defer allocator.free(url);
        try std.testing.expectEqualStrings("https://my-resource-123.openai.azure.com/openai", url);
    }

    // Test longer name
    {
        const url = try buildBaseUrlFromResourceName(allocator, "production-openai-east");
        defer allocator.free(url);
        try std.testing.expectEqualStrings("https://production-openai-east.openai.azure.com/openai", url);
    }
}

test "buildBaseUrlFromResourceName with empty string" {
    const allocator = std.testing.allocator;

    const url = try buildBaseUrlFromResourceName(allocator, "");
    defer allocator.free(url);

    try std.testing.expectEqualStrings("https://.openai.azure.com/openai", url);
}
