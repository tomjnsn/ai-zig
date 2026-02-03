const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");
const lm = @import("../../provider/src/language-model/v3/index.zig");

const config_mod = @import("bedrock-config.zig");
const chat_model = @import("bedrock-chat-language-model.zig");
const embed_model = @import("bedrock-embedding-model.zig");
const options_mod = @import("bedrock-options.zig");

/// Amazon Bedrock Provider settings
pub const AmazonBedrockProviderSettings = struct {
    /// AWS region
    region: ?[]const u8 = null,

    /// API key (for bearer token authentication)
    api_key: ?[]const u8 = null,

    /// AWS access key ID
    access_key_id: ?[]const u8 = null,

    /// AWS secret access key
    secret_access_key: ?[]const u8 = null,

    /// AWS session token (for temporary credentials)
    session_token: ?[]const u8 = null,

    /// Base URL for API calls
    base_url: ?[]const u8 = null,

    /// Custom headers
    headers: ?std.StringHashMap([]const u8) = null,

    /// HTTP client
    http_client: ?provider_utils.HttpClient = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// Amazon Bedrock Provider
pub const AmazonBedrockProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: AmazonBedrockProviderSettings,
    region: []const u8,
    base_url: []const u8,

    pub const specification_version = "v3";

    /// Create a new Amazon Bedrock provider
    pub fn init(allocator: std.mem.Allocator, settings: AmazonBedrockProviderSettings) Self {
        const region = settings.region orelse getRegionFromEnv() orelse "us-east-1";

        const base_url = settings.base_url orelse blk: {
            break :blk config_mod.buildBedrockRuntimeUrl(allocator, region) catch
                "https://bedrock-runtime.us-east-1.amazonaws.com";
        };

        return .{
            .allocator = allocator,
            .settings = settings,
            .region = region,
            .base_url = base_url,
        };
    }

    /// Deinitialize the provider
    pub fn deinit(self: *Self) void {
        _ = self;
        // Clean up any allocated resources
    }

    /// Get the provider name
    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "bedrock";
    }

    // -- Language Models --

    /// Create a language model
    pub fn languageModel(self: *Self, model_id: []const u8) chat_model.BedrockChatLanguageModel {
        return chat_model.BedrockChatLanguageModel.init(
            self.allocator,
            model_id,
            self.buildConfig("bedrock.chat"),
        );
    }

    // -- Embedding Models --

    /// Create an embedding model
    pub fn embeddingModel(self: *Self, model_id: []const u8) embed_model.BedrockEmbeddingModel {
        return embed_model.BedrockEmbeddingModel.init(
            self.allocator,
            model_id,
            self.buildConfig("bedrock.embedding"),
        );
    }

    /// Create an embedding model (alias)
    pub fn embedding(self: *Self, model_id: []const u8) embed_model.BedrockEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Create a text embedding model (deprecated alias)
    pub fn textEmbedding(self: *Self, model_id: []const u8) embed_model.BedrockEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Create a text embedding model (deprecated alias)
    pub fn textEmbeddingModel(self: *Self, model_id: []const u8) embed_model.BedrockEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Build config for models
    fn buildConfig(self: *Self, provider_name: []const u8) config_mod.BedrockConfig {
        return .{
            .provider = provider_name,
            .base_url = self.base_url,
            .region = self.region,
            .headers_fn = getHeadersFn,
            .http_client = self.settings.http_client,
            .generate_id = self.settings.generate_id,
        };
    }

    // -- ProviderV3 Interface --

    /// Convert to ProviderV3 interface
    pub fn asProvider(self: *Self) provider_v3.ProviderV3 {
        return .{
            .vtable = &vtable,
            .impl = self,
        };
    }

    const vtable = provider_v3.ProviderV3.VTable{
        .languageModel = languageModelVtable,
        .embeddingModel = embeddingModelVtable,
        .imageModel = imageModelVtable,
        .speechModel = speechModelVtable,
        .transcriptionModel = transcriptionModelVtable,
    };

    fn languageModelVtable(impl: *anyopaque, model_id: []const u8) provider_v3.LanguageModelResult {
        const self: *Self = @ptrCast(@alignCast(impl));
        var model = self.languageModel(model_id);
        return .{ .success = model.asLanguageModel() };
    }

    fn embeddingModelVtable(impl: *anyopaque, model_id: []const u8) provider_v3.EmbeddingModelResult {
        const self: *Self = @ptrCast(@alignCast(impl));
        var model = self.embeddingModel(model_id);
        return .{ .success = model.asEmbeddingModel() };
    }

    fn imageModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.ImageModelResult {
        _ = model_id;
        // Image model not yet implemented
        return .{ .failure = error.NoSuchModel };
    }

    fn speechModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.SpeechModelResult {
        _ = model_id;
        return .{ .failure = error.NoSuchModel };
    }

    fn transcriptionModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.TranscriptionModelResult {
        _ = model_id;
        return .{ .failure = error.NoSuchModel };
    }
};

/// Get region from environment
fn getRegionFromEnv() ?[]const u8 {
    return std.posix.getenv("AWS_REGION");
}

/// Get access key ID from environment
fn getAccessKeyIdFromEnv() ?[]const u8 {
    return std.posix.getenv("AWS_ACCESS_KEY_ID");
}

/// Get secret access key from environment
fn getSecretAccessKeyFromEnv() ?[]const u8 {
    return std.posix.getenv("AWS_SECRET_ACCESS_KEY");
}

/// Get session token from environment
fn getSessionTokenFromEnv() ?[]const u8 {
    return std.posix.getenv("AWS_SESSION_TOKEN");
}

/// Get bearer token from environment
fn getBearerTokenFromEnv() ?[]const u8 {
    return std.posix.getenv("AWS_BEARER_TOKEN_BEDROCK");
}

/// Headers function for config.
/// Caller owns the returned HashMap and must call deinit() when done.
fn getHeadersFn(config: *const config_mod.BedrockConfig, allocator: std.mem.Allocator) std.StringHashMap([]const u8) {
    _ = config;
    var headers = std.StringHashMap([]const u8).init(allocator);

    // Add content-type
    headers.put("Content-Type", "application/json") catch {};

    // Add authorization (would need SigV4 or bearer token)
    if (getBearerTokenFromEnv()) |token| {
        const auth_header = std.fmt.allocPrint(
            allocator,
            "Bearer {s}",
            .{token},
        ) catch return headers;
        headers.put("Authorization", auth_header) catch {};
    }

    return headers;
}

/// Create a new Amazon Bedrock provider with default settings
pub fn createAmazonBedrock(allocator: std.mem.Allocator) AmazonBedrockProvider {
    return AmazonBedrockProvider.init(allocator, .{});
}

/// Create a new Amazon Bedrock provider with custom settings
pub fn createAmazonBedrockWithSettings(
    allocator: std.mem.Allocator,
    settings: AmazonBedrockProviderSettings,
) AmazonBedrockProvider {
    return AmazonBedrockProvider.init(allocator, settings);
}


test "AmazonBedrockProvider basic" {
    const allocator = std.testing.allocator;

    var provider = createAmazonBedrockWithSettings(allocator, .{
        .region = "us-east-1",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("bedrock", provider.getProvider());
}

test "AmazonBedrockProvider language model" {
    const allocator = std.testing.allocator;

    var provider = createAmazonBedrockWithSettings(allocator, .{
        .region = "us-east-1",
    });
    defer provider.deinit();

    const model = provider.languageModel("anthropic.claude-3-5-sonnet-20241022-v2:0");
    try std.testing.expectEqualStrings("anthropic.claude-3-5-sonnet-20241022-v2:0", model.getModelId());
}

test "AmazonBedrockProvider embedding model" {
    const allocator = std.testing.allocator;

    var provider = createAmazonBedrockWithSettings(allocator, .{
        .region = "us-east-1",
    });
    defer provider.deinit();

    const model = provider.embeddingModel("amazon.titan-embed-text-v2:0");
    try std.testing.expectEqualStrings("amazon.titan-embed-text-v2:0", model.getModelId());
}
