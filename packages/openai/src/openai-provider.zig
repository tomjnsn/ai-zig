const std = @import("std");
const provider_v3 = @import("provider").provider;
const lm = @import("provider").language_model;
const em = @import("provider").embedding_model;
const im = @import("provider").image_model;
const sm = @import("provider").speech_model;
const tm = @import("provider").transcription_model;
const provider_utils = @import("provider-utils");

const config_mod = @import("openai-config.zig");
const chat_mod = @import("chat/index.zig");
const embedding_mod = @import("embedding/index.zig");
const image_mod = @import("image/index.zig");
const speech_mod = @import("speech/index.zig");
const transcription_mod = @import("transcription/index.zig");

/// OpenAI Provider settings
pub const OpenAIProviderSettings = struct {
    /// Base URL for the OpenAI API calls
    base_url: ?[]const u8 = null,

    /// API key for authenticating requests
    api_key: ?[]const u8 = null,

    /// OpenAI Organization
    organization: ?[]const u8 = null,

    /// OpenAI project
    project: ?[]const u8 = null,

    /// Custom headers to include in the requests
    headers: ?std.StringHashMap([]const u8) = null,

    /// Provider name (overrides the `openai` default name for 3rd party providers)
    name: ?[]const u8 = null,

    /// HTTP client for making requests
    http_client: ?provider_utils.HttpClient = null,
};

/// OpenAI Provider
pub const OpenAIProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: OpenAIProviderSettings,
    config: config_mod.OpenAIConfig,

    pub const specification_version = "v3";

    /// Create a new OpenAI provider
    pub fn init(allocator: std.mem.Allocator, settings: OpenAIProviderSettings) Self {
        const base_url = settings.base_url orelse getBaseUrlFromEnv() orelse "https://api.openai.com/v1";
        const provider_name = settings.name orelse "openai";

        return .{
            .allocator = allocator,
            .settings = settings,
            .config = .{
                .provider = provider_name,
                .base_url = base_url,
                .headers_fn = getHeadersFn,
                .http_client = settings.http_client,
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
        return self.config.provider;
    }

    // -- Language Models --

    /// Create a language model
    pub fn languageModel(self: *Self, model_id: []const u8) chat_mod.OpenAIChatLanguageModel {
        var model_config = self.config;
        model_config.provider = self.getChatProviderName();
        return chat_mod.OpenAIChatLanguageModel.init(self.allocator, model_id, model_config);
    }

    /// Create a chat language model (alias for languageModel)
    pub fn chatModel(self: *Self, model_id: []const u8) chat_mod.OpenAIChatLanguageModel {
        return self.languageModel(model_id);
    }

    /// Create a chat language model (alias for languageModel)
    pub fn chat(self: *Self, model_id: []const u8) chat_mod.OpenAIChatLanguageModel {
        return self.languageModel(model_id);
    }

    // -- Embedding Model --

    /// Create an embedding model
    pub fn embeddingModel(self: *Self, model_id: []const u8) embedding_mod.OpenAIEmbeddingModel {
        var model_config = self.config;
        model_config.provider = self.getEmbeddingProviderName();
        return embedding_mod.OpenAIEmbeddingModel.init(self.allocator, model_id, model_config);
    }

    /// Create an embedding model (alias)
    pub fn embedding(self: *Self, model_id: []const u8) embedding_mod.OpenAIEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Create a text embedding model (deprecated alias)
    pub fn textEmbedding(self: *Self, model_id: []const u8) embedding_mod.OpenAIEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Create a text embedding model (deprecated alias)
    pub fn textEmbeddingModel(self: *Self, model_id: []const u8) embedding_mod.OpenAIEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    // -- Image Model --

    /// Create an image model
    pub fn imageModel(self: *Self, model_id: []const u8) image_mod.OpenAIImageModel {
        var model_config = self.config;
        model_config.provider = self.getImageProviderName();
        return image_mod.OpenAIImageModel.init(self.allocator, model_id, model_config);
    }

    /// Create an image model (alias)
    pub fn image(self: *Self, model_id: []const u8) image_mod.OpenAIImageModel {
        return self.imageModel(model_id);
    }

    // -- Speech Model --

    /// Create a speech model
    pub fn speechModel(self: *Self, model_id: []const u8) speech_mod.OpenAISpeechModel {
        var model_config = self.config;
        model_config.provider = self.getSpeechProviderName();
        return speech_mod.OpenAISpeechModel.init(self.allocator, model_id, model_config);
    }

    /// Create a speech model (alias)
    pub fn speech(self: *Self, model_id: []const u8) speech_mod.OpenAISpeechModel {
        return self.speechModel(model_id);
    }

    // -- Transcription Model --

    /// Create a transcription model
    pub fn transcriptionModel(self: *Self, model_id: []const u8) transcription_mod.OpenAITranscriptionModel {
        var model_config = self.config;
        model_config.provider = self.getTranscriptionProviderName();
        return transcription_mod.OpenAITranscriptionModel.init(self.allocator, model_id, model_config);
    }

    /// Create a transcription model (alias)
    pub fn transcription(self: *Self, model_id: []const u8) transcription_mod.OpenAITranscriptionModel {
        return self.transcriptionModel(model_id);
    }

    // -- Provider Name Helpers --

    fn getChatProviderName(self: *const Self) []const u8 {
        _ = self;
        return "openai.chat";
    }

    fn getEmbeddingProviderName(self: *const Self) []const u8 {
        _ = self;
        return "openai.embedding";
    }

    fn getImageProviderName(self: *const Self) []const u8 {
        _ = self;
        return "openai.image";
    }

    fn getSpeechProviderName(self: *const Self) []const u8 {
        _ = self;
        return "openai.speech";
    }

    fn getTranscriptionProviderName(self: *const Self) []const u8 {
        _ = self;
        return "openai.transcription";
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

    fn imageModelVtable(impl: *anyopaque, model_id: []const u8) provider_v3.ImageModelResult {
        const self: *Self = @ptrCast(@alignCast(impl));
        var model = self.imageModel(model_id);
        return .{ .success = model.asImageModel() };
    }

    fn speechModelVtable(impl: *anyopaque, model_id: []const u8) provider_v3.SpeechModelResult {
        const self: *Self = @ptrCast(@alignCast(impl));
        var model = self.speechModel(model_id);
        return .{ .success = model.asSpeechModel() };
    }

    fn transcriptionModelVtable(impl: *anyopaque, model_id: []const u8) provider_v3.TranscriptionModelResult {
        const self: *Self = @ptrCast(@alignCast(impl));
        var model = self.transcriptionModel(model_id);
        return .{ .success = model.asTranscriptionModel() };
    }
};

/// Get base URL from environment
fn getBaseUrlFromEnv() ?[]const u8 {
    return std.posix.getenv("OPENAI_BASE_URL");
}

/// Get API key from environment
fn getApiKeyFromEnv() ?[]const u8 {
    return std.posix.getenv("OPENAI_API_KEY");
}

/// Headers function for config.
/// Caller owns the returned HashMap and must call deinit() when done.
fn getHeadersFn(config: *const config_mod.OpenAIConfig, allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    _ = config;
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    // Add authorization header
    if (getApiKeyFromEnv()) |api_key| {
        const auth_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
        try headers.put("Authorization", auth_value);
    }

    // Add content-type
    try headers.put("Content-Type", "application/json");

    return headers;
}

/// Create a new OpenAI provider with default settings
pub fn createOpenAI(allocator: std.mem.Allocator) OpenAIProvider {
    return OpenAIProvider.init(allocator, .{});
}

/// Create a new OpenAI provider with custom settings
pub fn createOpenAIWithSettings(allocator: std.mem.Allocator, settings: OpenAIProviderSettings) OpenAIProvider {
    return OpenAIProvider.init(allocator, settings);
}

test "OpenAIProvider basic" {
    const allocator = std.testing.allocator;

    var provider = createOpenAI(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("openai", provider.getProvider());
}

test "OpenAIProvider with custom settings" {
    const allocator = std.testing.allocator;

    var provider = createOpenAIWithSettings(allocator, .{
        .base_url = "https://custom.openai.com/v1",
        .name = "custom-openai",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("custom-openai", provider.getProvider());
}

test "OpenAIProvider language model" {
    const allocator = std.testing.allocator;

    var provider = createOpenAI(allocator);
    defer provider.deinit();

    const model = provider.languageModel("gpt-4o");
    try std.testing.expectEqualStrings("gpt-4o", model.getModelId());
}

test "OpenAIProvider chat model alias" {
    const allocator = std.testing.allocator;

    var provider = createOpenAI(allocator);
    defer provider.deinit();

    const model = provider.chat("gpt-4o");
    try std.testing.expectEqualStrings("gpt-4o", model.getModelId());
}

test "OpenAIProvider embedding model" {
    const allocator = std.testing.allocator;

    var provider = createOpenAI(allocator);
    defer provider.deinit();

    const model = provider.embeddingModel("text-embedding-3-small");
    try std.testing.expectEqualStrings("text-embedding-3-small", model.getModelId());
}
