const std = @import("std");
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");
const lm = @import("../../provider/src/language-model/v3/index.zig");

const config_mod = @import("azure-config.zig");

// Import OpenAI models (Azure reuses them)
const openai_chat = @import("../../openai/src/chat/openai-chat-language-model.zig");
const openai_embed = @import("../../openai/src/embedding/openai-embedding-model.zig");
const openai_image = @import("../../openai/src/image/openai-image-model.zig");
const openai_speech = @import("../../openai/src/speech/openai-speech-model.zig");
const openai_transcription = @import("../../openai/src/transcription/openai-transcription-model.zig");
const openai_config = @import("../../openai/src/openai-config.zig");

/// Azure OpenAI Provider settings
pub const AzureOpenAIProviderSettings = struct {
    /// Azure resource name (used if baseURL not provided)
    resource_name: ?[]const u8 = null,

    /// Base URL for API calls (overrides resource_name)
    base_url: ?[]const u8 = null,

    /// API key for authentication
    api_key: ?[]const u8 = null,

    /// Custom headers
    headers: ?std.StringHashMap([]const u8) = null,

    /// API version (defaults to "v1")
    api_version: ?[]const u8 = null,

    /// Use deployment-based URLs
    use_deployment_based_urls: ?bool = null,

    /// HTTP client
    http_client: ?*anyopaque = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// Azure OpenAI Provider
pub const AzureOpenAIProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: AzureOpenAIProviderSettings,
    config: config_mod.AzureOpenAIConfig,

    pub const specification_version = "v3";

    /// Create a new Azure OpenAI provider
    pub fn init(allocator: std.mem.Allocator, settings: AzureOpenAIProviderSettings) Self {
        // Build base URL
        const base_url = settings.base_url orelse blk: {
            const resource_name = settings.resource_name orelse getResourceNameFromEnv() orelse "default";
            break :blk config_mod.buildBaseUrlFromResourceName(allocator, resource_name) catch "https://azure.openai.com/openai";
        };

        return .{
            .allocator = allocator,
            .settings = settings,
            .config = .{
                .provider = "azure",
                .base_url = base_url,
                .api_version = settings.api_version orelse "v1",
                .use_deployment_based_urls = settings.use_deployment_based_urls orelse false,
                .headers_fn = getHeadersFn,
                .http_client = settings.http_client,
                .generate_id = settings.generate_id,
            },
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
        return "azure";
    }

    // -- Language Models --

    /// Create a chat language model
    pub fn chat(self: *Self, deployment_id: []const u8) openai_chat.OpenAIChatLanguageModel {
        return openai_chat.OpenAIChatLanguageModel.init(
            self.allocator,
            deployment_id,
            self.buildOpenAIConfig("azure.chat"),
        );
    }

    /// Create a language model (alias for responses)
    pub fn languageModel(self: *Self, deployment_id: []const u8) openai_chat.OpenAIChatLanguageModel {
        return self.chat(deployment_id);
    }

    // -- Embedding Models --

    /// Create an embedding model
    pub fn embeddingModel(self: *Self, deployment_id: []const u8) openai_embed.OpenAIEmbeddingModel {
        return openai_embed.OpenAIEmbeddingModel.init(
            self.allocator,
            deployment_id,
            self.buildOpenAIConfig("azure.embeddings"),
        );
    }

    /// Create an embedding model (alias)
    pub fn embedding(self: *Self, deployment_id: []const u8) openai_embed.OpenAIEmbeddingModel {
        return self.embeddingModel(deployment_id);
    }

    /// Create a text embedding model (deprecated alias)
    pub fn textEmbedding(self: *Self, deployment_id: []const u8) openai_embed.OpenAIEmbeddingModel {
        return self.embeddingModel(deployment_id);
    }

    /// Create a text embedding model (deprecated alias)
    pub fn textEmbeddingModel(self: *Self, deployment_id: []const u8) openai_embed.OpenAIEmbeddingModel {
        return self.embeddingModel(deployment_id);
    }

    // -- Image Models --

    /// Create an image model
    pub fn imageModel(self: *Self, deployment_id: []const u8) openai_image.OpenAIImageModel {
        return openai_image.OpenAIImageModel.init(
            self.allocator,
            deployment_id,
            self.buildOpenAIConfig("azure.image"),
        );
    }

    /// Create an image model (alias)
    pub fn image(self: *Self, deployment_id: []const u8) openai_image.OpenAIImageModel {
        return self.imageModel(deployment_id);
    }

    // -- Speech Models --

    /// Create a speech model
    pub fn speech(self: *Self, deployment_id: []const u8) openai_speech.OpenAISpeechModel {
        return openai_speech.OpenAISpeechModel.init(
            self.allocator,
            deployment_id,
            self.buildOpenAIConfig("azure.speech"),
        );
    }

    // -- Transcription Models --

    /// Create a transcription model
    pub fn transcription(self: *Self, deployment_id: []const u8) openai_transcription.OpenAITranscriptionModel {
        return openai_transcription.OpenAITranscriptionModel.init(
            self.allocator,
            deployment_id,
            self.buildOpenAIConfig("azure.transcription"),
        );
    }

    /// Build OpenAI config for models
    fn buildOpenAIConfig(self: *Self, provider_name: []const u8) openai_config.OpenAIConfig {
        return .{
            .provider = provider_name,
            .base_url = self.config.base_url,
            .headers_fn = getOpenAIHeadersFn,
            .http_client = self.config.http_client,
            .generate_id = self.config.generate_id,
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
        return .{ .ok = model.asLanguageModel() };
    }

    fn embeddingModelVtable(impl: *anyopaque, model_id: []const u8) provider_v3.EmbeddingModelResult {
        const self: *Self = @ptrCast(@alignCast(impl));
        var model = self.embeddingModel(model_id);
        return .{ .ok = model.asEmbeddingModel() };
    }

    fn imageModelVtable(impl: *anyopaque, model_id: []const u8) provider_v3.ImageModelResult {
        const self: *Self = @ptrCast(@alignCast(impl));
        var model = self.imageModel(model_id);
        return .{ .ok = model.asImageModel() };
    }

    fn speechModelVtable(impl: *anyopaque, model_id: []const u8) provider_v3.SpeechModelResult {
        const self: *Self = @ptrCast(@alignCast(impl));
        var model = self.speech(model_id);
        return .{ .ok = model.asSpeechModel() };
    }

    fn transcriptionModelVtable(impl: *anyopaque, model_id: []const u8) provider_v3.TranscriptionModelResult {
        const self: *Self = @ptrCast(@alignCast(impl));
        var model = self.transcription(model_id);
        return .{ .ok = model.asTranscriptionModel() };
    }
};

/// Get resource name from environment
fn getResourceNameFromEnv() ?[]const u8 {
    return std.posix.getenv("AZURE_RESOURCE_NAME");
}

/// Get API key from environment
fn getApiKeyFromEnv() ?[]const u8 {
    return std.posix.getenv("AZURE_API_KEY");
}

/// Headers function for Azure config
fn getHeadersFn(config: *const config_mod.AzureOpenAIConfig) std.StringHashMap([]const u8) {
    _ = config;
    var headers = std.StringHashMap([]const u8).init(std.heap.page_allocator);

    // Add API key header
    if (getApiKeyFromEnv()) |api_key| {
        headers.put("api-key", api_key) catch {};
    }

    // Add content-type
    headers.put("Content-Type", "application/json") catch {};

    return headers;
}

/// Headers function for OpenAI config (used by models)
fn getOpenAIHeadersFn(config: *const openai_config.OpenAIConfig) std.StringHashMap([]const u8) {
    _ = config;
    var headers = std.StringHashMap([]const u8).init(std.heap.page_allocator);

    // Add API key header (Azure uses api-key instead of Authorization)
    if (getApiKeyFromEnv()) |api_key| {
        headers.put("api-key", api_key) catch {};
    }

    // Add content-type
    headers.put("Content-Type", "application/json") catch {};

    return headers;
}

/// Create a new Azure OpenAI provider with default settings
pub fn createAzure(allocator: std.mem.Allocator) AzureOpenAIProvider {
    return AzureOpenAIProvider.init(allocator, .{});
}

/// Create a new Azure OpenAI provider with custom settings
pub fn createAzureWithSettings(
    allocator: std.mem.Allocator,
    settings: AzureOpenAIProviderSettings,
) AzureOpenAIProvider {
    return AzureOpenAIProvider.init(allocator, settings);
}

/// Default Azure OpenAI provider instance (created lazily)
var default_provider: ?AzureOpenAIProvider = null;

/// Get the default Azure OpenAI provider
pub fn azure() *AzureOpenAIProvider {
    if (default_provider == null) {
        default_provider = createAzure(std.heap.page_allocator);
    }
    return &default_provider.?;
}

test "AzureOpenAIProviderSettings defaults" {
    const settings = AzureOpenAIProviderSettings{};

    try std.testing.expectEqual(null, settings.resource_name);
    try std.testing.expectEqual(null, settings.base_url);
    try std.testing.expectEqual(null, settings.api_key);
    try std.testing.expectEqual(null, settings.headers);
    try std.testing.expectEqual(null, settings.api_version);
    try std.testing.expectEqual(null, settings.use_deployment_based_urls);
    try std.testing.expectEqual(null, settings.http_client);
    try std.testing.expectEqual(null, settings.generate_id);
}

test "AzureOpenAIProviderSettings custom values" {
    const settings = AzureOpenAIProviderSettings{
        .resource_name = "myresource",
        .base_url = "https://custom.openai.azure.com/openai",
        .api_key = "test-key",
        .api_version = "2024-03-01-preview",
        .use_deployment_based_urls = true,
    };

    try std.testing.expectEqualStrings("myresource", settings.resource_name.?);
    try std.testing.expectEqualStrings("https://custom.openai.azure.com/openai", settings.base_url.?);
    try std.testing.expectEqualStrings("test-key", settings.api_key.?);
    try std.testing.expectEqualStrings("2024-03-01-preview", settings.api_version.?);
    try std.testing.expectEqual(true, settings.use_deployment_based_urls.?);
}

test "AzureOpenAIProvider basic" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("azure", provider.getProvider());
}

test "AzureOpenAIProvider with default settings" {
    const allocator = std.testing.allocator;

    var provider = createAzure(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("azure", provider.getProvider());
    try std.testing.expectEqualStrings("v1", provider.config.api_version);
    try std.testing.expectEqual(false, provider.config.use_deployment_based_urls);
}

test "AzureOpenAIProvider with resource name" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .resource_name = "myresource",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("azure", provider.getProvider());
}

test "AzureOpenAIProvider with custom base_url overrides resource_name" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .resource_name = "ignored-resource",
        .base_url = "https://custom.openai.azure.com/openai",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://custom.openai.azure.com/openai", provider.config.base_url);
}

test "AzureOpenAIProvider with custom api_version" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
        .api_version = "2024-03-01-preview",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("2024-03-01-preview", provider.config.api_version);
}

test "AzureOpenAIProvider with deployment-based URLs" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
        .use_deployment_based_urls = true,
    });
    defer provider.deinit();

    try std.testing.expectEqual(true, provider.config.use_deployment_based_urls);
}

test "AzureOpenAIProvider specification version" {
    try std.testing.expectEqualStrings("v3", AzureOpenAIProvider.specification_version);
}

test "AzureOpenAIProvider chat model" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const model = provider.chat("gpt-4");
    try std.testing.expectEqualStrings("gpt-4", model.getModelId());
}

test "AzureOpenAIProvider languageModel alias" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const model = provider.languageModel("gpt-4-turbo");
    try std.testing.expectEqualStrings("gpt-4-turbo", model.getModelId());
}

test "AzureOpenAIProvider embedding model" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const model = provider.embeddingModel("text-embedding-ada-002");
    try std.testing.expectEqualStrings("text-embedding-ada-002", model.getModelId());
}

test "AzureOpenAIProvider embedding alias" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const model = provider.embedding("text-embedding-3-small");
    try std.testing.expectEqualStrings("text-embedding-3-small", model.getModelId());
}

test "AzureOpenAIProvider textEmbedding deprecated alias" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const model = provider.textEmbedding("text-embedding-3-large");
    try std.testing.expectEqualStrings("text-embedding-3-large", model.getModelId());
}

test "AzureOpenAIProvider textEmbeddingModel deprecated alias" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const model = provider.textEmbeddingModel("text-embedding-ada-002");
    try std.testing.expectEqualStrings("text-embedding-ada-002", model.getModelId());
}

test "AzureOpenAIProvider image model" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const model = provider.imageModel("dall-e-3");
    try std.testing.expectEqualStrings("dall-e-3", model.getModelId());
}

test "AzureOpenAIProvider image alias" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const model = provider.image("dall-e-2");
    try std.testing.expectEqualStrings("dall-e-2", model.getModelId());
}

test "AzureOpenAIProvider speech model" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const model = provider.speech("tts-1");
    try std.testing.expectEqualStrings("tts-1", model.getModelId());
}

test "AzureOpenAIProvider transcription model" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const model = provider.transcription("whisper-1");
    try std.testing.expectEqualStrings("whisper-1", model.getModelId());
}

test "AzureOpenAIProvider multiple models from same provider" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const chat_model = provider.chat("gpt-4");
    const embed_model = provider.embeddingModel("text-embedding-ada-002");
    const image_model = provider.imageModel("dall-e-3");

    try std.testing.expectEqualStrings("gpt-4", chat_model.getModelId());
    try std.testing.expectEqualStrings("text-embedding-ada-002", embed_model.getModelId());
    try std.testing.expectEqualStrings("dall-e-3", image_model.getModelId());
}

test "AzureOpenAIProvider models with deployment names" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
        .use_deployment_based_urls = true,
    });
    defer provider.deinit();

    // Test with deployment names instead of model IDs
    const chat_model = provider.chat("my-gpt4-deployment");
    const embed_model = provider.embeddingModel("my-embedding-deployment");

    try std.testing.expectEqualStrings("my-gpt4-deployment", chat_model.getModelId());
    try std.testing.expectEqualStrings("my-embedding-deployment", embed_model.getModelId());
}

test "AzureOpenAIProvider buildOpenAIConfig" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const config = provider.buildOpenAIConfig("azure.test");
    try std.testing.expectEqualStrings("azure.test", config.provider);
    try std.testing.expectEqualStrings("https://myresource.openai.azure.com/openai", config.base_url);
}

test "createAzure helper function" {
    const allocator = std.testing.allocator;

    var provider = createAzure(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("azure", provider.getProvider());
}

test "createAzureWithSettings helper function" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://test.openai.azure.com/openai",
        .api_version = "2024-02-15-preview",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("azure", provider.getProvider());
    try std.testing.expectEqualStrings("2024-02-15-preview", provider.config.api_version);
}

test "AzureOpenAIProvider asProvider interface" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    const provider_interface = provider.asProvider();

    // Test language model through vtable
    const lang_result = provider_interface.vtable.languageModel(provider_interface.impl, "gpt-4");
    try std.testing.expectEqual(@as(@TypeOf(lang_result), provider_v3.LanguageModelResult{ .ok = lang_result.ok }), lang_result);

    // Test embedding model through vtable
    const embed_result = provider_interface.vtable.embeddingModel(provider_interface.impl, "text-embedding-ada-002");
    try std.testing.expectEqual(@as(@TypeOf(embed_result), provider_v3.EmbeddingModelResult{ .ok = embed_result.ok }), embed_result);

    // Test image model through vtable
    const image_result = provider_interface.vtable.imageModel(provider_interface.impl, "dall-e-3");
    try std.testing.expectEqual(@as(@TypeOf(image_result), provider_v3.ImageModelResult{ .ok = image_result.ok }), image_result);

    // Test speech model through vtable
    const speech_result = provider_interface.vtable.speechModel(provider_interface.impl, "tts-1");
    try std.testing.expectEqual(@as(@TypeOf(speech_result), provider_v3.SpeechModelResult{ .ok = speech_result.ok }), speech_result);

    // Test transcription model through vtable
    const transcription_result = provider_interface.vtable.transcriptionModel(provider_interface.impl, "whisper-1");
    try std.testing.expectEqual(@as(@TypeOf(transcription_result), provider_v3.TranscriptionModelResult{ .ok = transcription_result.ok }), transcription_result);
}

test "AzureOpenAIProvider config propagation" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://custom.openai.azure.com/openai",
        .api_version = "2024-03-01-preview",
        .use_deployment_based_urls = true,
    });
    defer provider.deinit();

    // Verify config is properly initialized
    try std.testing.expectEqualStrings("azure", provider.config.provider);
    try std.testing.expectEqualStrings("https://custom.openai.azure.com/openai", provider.config.base_url);
    try std.testing.expectEqualStrings("2024-03-01-preview", provider.config.api_version);
    try std.testing.expectEqual(true, provider.config.use_deployment_based_urls);
}

test "AzureOpenAIProvider allocator usage" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    // Verify allocator is stored correctly
    try std.testing.expectEqual(allocator, provider.allocator);
}

test "AzureOpenAIProvider deinit safety" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });

    // Call deinit multiple times should be safe
    provider.deinit();
    provider.deinit();
}

test "AzureOpenAIProvider different API versions" {
    const allocator = std.testing.allocator;

    // Test with various API versions
    const versions = [_][]const u8{
        "v1",
        "2023-05-15",
        "2024-02-15-preview",
        "2024-03-01-preview",
        "2024-05-01-preview",
    };

    for (versions) |version| {
        var provider = createAzureWithSettings(allocator, .{
            .base_url = "https://myresource.openai.azure.com/openai",
            .api_version = version,
        });
        defer provider.deinit();

        try std.testing.expectEqualStrings(version, provider.config.api_version);
    }
}

test "AzureOpenAIProvider empty deployment ID" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    // Test with empty deployment ID
    const model = provider.chat("");
    try std.testing.expectEqualStrings("", model.getModelId());
}

test "AzureOpenAIProvider long deployment ID" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    // Test with very long deployment ID
    const long_id = "this-is-a-very-long-deployment-id-with-many-characters-and-dashes-1234567890";
    const model = provider.chat(long_id);
    try std.testing.expectEqualStrings(long_id, model.getModelId());
}

test "AzureOpenAIProvider model factory methods return correct types" {
    const allocator = std.testing.allocator;

    var provider = createAzureWithSettings(allocator, .{
        .base_url = "https://myresource.openai.azure.com/openai",
    });
    defer provider.deinit();

    // Verify each factory method returns the expected model type
    _ = provider.chat("gpt-4");
    _ = provider.languageModel("gpt-4");
    _ = provider.embeddingModel("text-embedding-ada-002");
    _ = provider.embedding("text-embedding-ada-002");
    _ = provider.textEmbedding("text-embedding-ada-002");
    _ = provider.textEmbeddingModel("text-embedding-ada-002");
    _ = provider.imageModel("dall-e-3");
    _ = provider.image("dall-e-3");
    _ = provider.speech("tts-1");
    _ = provider.transcription("whisper-1");
}
