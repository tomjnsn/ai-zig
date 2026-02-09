const std = @import("std");
const provider_v3 = @import("provider").provider;
const lm = @import("provider").language_model;
const provider_utils = @import("provider-utils");

const config_mod = @import("google-config.zig");
const lang_model = @import("google-generative-ai-language-model.zig");
const embed_model = @import("google-generative-ai-embedding-model.zig");
const image_model = @import("google-generative-ai-image-model.zig");
const options_mod = @import("google-generative-ai-options.zig");

/// Google Generative AI Provider settings
pub const GoogleGenerativeAIProviderSettings = struct {
    /// Base URL for the Google AI API calls
    base_url: ?[]const u8 = null,

    /// API key for authenticating requests
    api_key: ?[]const u8 = null,

    /// Custom headers to include in the requests
    headers: ?std.StringHashMap([]const u8) = null,

    /// Provider name (overrides the default name)
    name: ?[]const u8 = null,

    /// HTTP client for making requests
    http_client: ?provider_utils.HttpClient = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// Google Generative AI Provider
pub const GoogleGenerativeAIProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: GoogleGenerativeAIProviderSettings,
    config: config_mod.GoogleGenerativeAIConfig,

    pub const specification_version = "v3";

    /// Create a new Google Generative AI provider
    pub fn init(allocator: std.mem.Allocator, settings: GoogleGenerativeAIProviderSettings) Self {
        const base_url = settings.base_url orelse getBaseUrlFromEnv() orelse config_mod.default_base_url;
        const provider_name = settings.name orelse "google.generative-ai";

        return .{
            .allocator = allocator,
            .settings = settings,
            .config = .{
                .provider = provider_name,
                .base_url = base_url,
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
        return self.config.provider;
    }

    // -- Language Models --

    /// Create a language model
    pub fn languageModel(self: *Self, model_id: []const u8) lang_model.GoogleGenerativeAILanguageModel {
        return lang_model.GoogleGenerativeAILanguageModel.init(self.allocator, model_id, self.config);
    }

    /// Create a chat model (alias for languageModel)
    pub fn chat(self: *Self, model_id: []const u8) lang_model.GoogleGenerativeAILanguageModel {
        return self.languageModel(model_id);
    }

    /// Create a generativeAI model (deprecated alias for languageModel)
    pub fn generativeAI(self: *Self, model_id: []const u8) lang_model.GoogleGenerativeAILanguageModel {
        return self.languageModel(model_id);
    }

    // -- Embedding Models --

    /// Create an embedding model
    pub fn embeddingModel(self: *Self, model_id: []const u8) embed_model.GoogleGenerativeAIEmbeddingModel {
        return embed_model.GoogleGenerativeAIEmbeddingModel.init(self.allocator, model_id, self.config);
    }

    /// Create an embedding model (alias)
    pub fn embedding(self: *Self, model_id: []const u8) embed_model.GoogleGenerativeAIEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Create a text embedding model (deprecated alias)
    pub fn textEmbedding(self: *Self, model_id: []const u8) embed_model.GoogleGenerativeAIEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Create a text embedding model (deprecated alias)
    pub fn textEmbeddingModel(self: *Self, model_id: []const u8) embed_model.GoogleGenerativeAIEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    // -- Image Models --

    /// Create an image model
    pub fn imageModel(
        self: *Self,
        model_id: []const u8,
    ) image_model.GoogleGenerativeAIImageModel {
        return self.imageModelWithSettings(model_id, .{});
    }

    /// Create an image model with settings
    pub fn imageModelWithSettings(
        self: *Self,
        model_id: []const u8,
        settings: options_mod.GoogleGenerativeAIImageSettings,
    ) image_model.GoogleGenerativeAIImageModel {
        return image_model.GoogleGenerativeAIImageModel.init(
            self.allocator,
            model_id,
            settings,
            self.config,
        );
    }

    /// Create an image model (alias)
    pub fn image(self: *Self, model_id: []const u8) image_model.GoogleGenerativeAIImageModel {
        return self.imageModel(model_id);
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

    fn speechModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.SpeechModelResult {
        _ = model_id;
        return .{ .failure = error.NoSuchModel };
    }

    fn transcriptionModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.TranscriptionModelResult {
        _ = model_id;
        return .{ .failure = error.NoSuchModel };
    }
};

/// Get base URL from environment
fn getBaseUrlFromEnv() ?[]const u8 {
    return std.posix.getenv("GOOGLE_GENERATIVE_AI_BASE_URL");
}

/// Get API key from environment
fn getApiKeyFromEnv() ?[]const u8 {
    return std.posix.getenv("GOOGLE_GENERATIVE_AI_API_KEY");
}

/// Headers function for config.
/// Caller owns the returned HashMap and must call deinit() when done.
fn getHeadersFn(config: *const config_mod.GoogleGenerativeAIConfig, allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    _ = config;
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    // Add API key header
    if (getApiKeyFromEnv()) |api_key| {
        try headers.put("x-goog-api-key", api_key);
    }

    // Add content-type
    try headers.put("Content-Type", "application/json");

    return headers;
}

/// Create a new Google Generative AI provider with default settings
pub fn createGoogleGenerativeAI(allocator: std.mem.Allocator) GoogleGenerativeAIProvider {
    return GoogleGenerativeAIProvider.init(allocator, .{});
}

/// Create a new Google Generative AI provider with custom settings
pub fn createGoogleGenerativeAIWithSettings(
    allocator: std.mem.Allocator,
    settings: GoogleGenerativeAIProviderSettings,
) GoogleGenerativeAIProvider {
    return GoogleGenerativeAIProvider.init(allocator, settings);
}


test "GoogleGenerativeAIProvider basic" {
    const allocator = std.testing.allocator;

    var provider = createGoogleGenerativeAI(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("google.generative-ai", provider.getProvider());
}

test "GoogleGenerativeAIProvider with custom settings" {
    const allocator = std.testing.allocator;

    var provider = createGoogleGenerativeAIWithSettings(allocator, .{
        .base_url = "https://custom.google.com/v1",
        .name = "custom-google",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("custom-google", provider.getProvider());
}

test "GoogleGenerativeAIProvider language model" {
    const allocator = std.testing.allocator;

    var provider = createGoogleGenerativeAI(allocator);
    defer provider.deinit();

    const model = provider.languageModel("gemini-2.0-flash");
    try std.testing.expectEqualStrings("gemini-2.0-flash", model.getModelId());
}

test "GoogleGenerativeAIProvider embedding model" {
    const allocator = std.testing.allocator;

    var provider = createGoogleGenerativeAI(allocator);
    defer provider.deinit();

    const model = provider.embeddingModel("text-embedding-004");
    try std.testing.expectEqualStrings("text-embedding-004", model.getModelId());
}

test "GoogleGenerativeAIProvider image model" {
    const allocator = std.testing.allocator;

    var provider = createGoogleGenerativeAI(allocator);
    defer provider.deinit();

    const model = provider.imageModel("imagen-4.0-generate-001");
    try std.testing.expectEqualStrings("imagen-4.0-generate-001", model.getModelId());
}
