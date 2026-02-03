const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;

const config_mod = @import("mistral-config.zig");
const chat_model = @import("mistral-chat-language-model.zig");
const embed_model = @import("mistral-embedding-model.zig");

/// Mistral Provider settings
pub const MistralProviderSettings = struct {
    /// Base URL for API calls
    base_url: ?[]const u8 = null,

    /// API key
    api_key: ?[]const u8 = null,

    /// Custom headers
    headers: ?std.StringHashMap([]const u8) = null,

    /// HTTP client
    http_client: ?provider_utils.HttpClient = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// Mistral Provider
pub const MistralProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: MistralProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    /// Create a new Mistral provider
    pub fn init(allocator: std.mem.Allocator, settings: MistralProviderSettings) Self {
        const base_url = settings.base_url orelse "https://api.mistral.ai/v1";

        return .{
            .allocator = allocator,
            .settings = settings,
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
        return "mistral";
    }

    // -- Language Models --

    /// Create a language model
    pub fn languageModel(self: *Self, model_id: []const u8) chat_model.MistralChatLanguageModel {
        return chat_model.MistralChatLanguageModel.init(
            self.allocator,
            model_id,
            self.buildConfig("mistral.chat"),
        );
    }

    /// Create a language model (alias)
    pub fn chat(self: *Self, model_id: []const u8) chat_model.MistralChatLanguageModel {
        return self.languageModel(model_id);
    }

    // -- Embedding Models --

    /// Create an embedding model
    pub fn embeddingModel(self: *Self, model_id: []const u8) embed_model.MistralEmbeddingModel {
        return embed_model.MistralEmbeddingModel.init(
            self.allocator,
            model_id,
            self.buildConfig("mistral.embedding"),
        );
    }

    /// Create an embedding model (alias)
    pub fn embedding(self: *Self, model_id: []const u8) embed_model.MistralEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Create a text embedding model (deprecated alias)
    pub fn textEmbedding(self: *Self, model_id: []const u8) embed_model.MistralEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Create a text embedding model (deprecated alias)
    pub fn textEmbeddingModel(self: *Self, model_id: []const u8) embed_model.MistralEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Build config for models
    fn buildConfig(self: *Self, provider_name: []const u8) config_mod.MistralConfig {
        return .{
            .provider = provider_name,
            .base_url = self.base_url,
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

/// Get API key from environment
fn getApiKeyFromEnv() ?[]const u8 {
    return std.posix.getenv("MISTRAL_API_KEY");
}

/// Headers function for config.
/// Caller owns the returned HashMap and must call deinit() when done.
fn getHeadersFn(config: *const config_mod.MistralConfig, allocator: std.mem.Allocator) std.StringHashMap([]const u8) {
    _ = config;
    var headers = std.StringHashMap([]const u8).init(allocator);

    // Add content-type
    headers.put("Content-Type", "application/json") catch {};

    // Add authorization
    if (getApiKeyFromEnv()) |api_key| {
        const auth_header = std.fmt.allocPrint(
            allocator,
            "Bearer {s}",
            .{api_key},
        ) catch return headers;
        headers.put("Authorization", auth_header) catch {};
    }

    return headers;
}

/// Create a new Mistral provider with default settings
pub fn createMistral(allocator: std.mem.Allocator) MistralProvider {
    return MistralProvider.init(allocator, .{});
}

/// Create a new Mistral provider with custom settings
pub fn createMistralWithSettings(
    allocator: std.mem.Allocator,
    settings: MistralProviderSettings,
) MistralProvider {
    return MistralProvider.init(allocator, settings);
}


test "MistralProvider basic" {
    const allocator = std.testing.allocator;

    var provider = createMistralWithSettings(allocator, .{
        .base_url = "https://api.mistral.ai/v1",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("mistral", provider.getProvider());
}

test "MistralProvider language model" {
    const allocator = std.testing.allocator;

    var provider = createMistralWithSettings(allocator, .{});
    defer provider.deinit();

    const model = provider.languageModel("mistral-large-latest");
    try std.testing.expectEqualStrings("mistral-large-latest", model.getModelId());
}

test "MistralProvider embedding model" {
    const allocator = std.testing.allocator;

    var provider = createMistralWithSettings(allocator, .{});
    defer provider.deinit();

    const model = provider.embeddingModel("mistral-embed");
    try std.testing.expectEqualStrings("mistral-embed", model.getModelId());
}
