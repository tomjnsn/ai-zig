const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;

const config_mod = @import("cohere-config.zig");
const chat_model = @import("cohere-chat-language-model.zig");
const embed_model = @import("cohere-embedding-model.zig");
const rerank_model = @import("cohere-reranking-model.zig");

/// Cohere Provider settings
pub const CohereProviderSettings = struct {
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

/// Cohere Provider
pub const CohereProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: CohereProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    /// Create a new Cohere provider
    pub fn init(allocator: std.mem.Allocator, settings: CohereProviderSettings) Self {
        const base_url = settings.base_url orelse "https://api.cohere.com/v2";

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
        return "cohere";
    }

    // -- Language Models --

    /// Create a language model
    pub fn languageModel(self: *Self, model_id: []const u8) chat_model.CohereChatLanguageModel {
        return chat_model.CohereChatLanguageModel.init(
            self.allocator,
            model_id,
            self.buildConfig("cohere.chat"),
        );
    }

    // -- Embedding Models --

    /// Create an embedding model
    pub fn embeddingModel(self: *Self, model_id: []const u8) embed_model.CohereEmbeddingModel {
        return embed_model.CohereEmbeddingModel.init(
            self.allocator,
            model_id,
            self.buildConfig("cohere.embedding"),
        );
    }

    /// Create an embedding model (alias)
    pub fn embedding(self: *Self, model_id: []const u8) embed_model.CohereEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Create a text embedding model (deprecated alias)
    pub fn textEmbedding(self: *Self, model_id: []const u8) embed_model.CohereEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Create a text embedding model (deprecated alias)
    pub fn textEmbeddingModel(self: *Self, model_id: []const u8) embed_model.CohereEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    // -- Reranking Models --

    /// Create a reranking model
    pub fn rerankingModel(self: *Self, model_id: []const u8) rerank_model.CohereRerankingModel {
        return rerank_model.CohereRerankingModel.init(
            self.allocator,
            model_id,
            self.buildConfig("cohere.reranking"),
        );
    }

    /// Create a reranking model (alias)
    pub fn reranking(self: *Self, model_id: []const u8) rerank_model.CohereRerankingModel {
        return self.rerankingModel(model_id);
    }

    /// Build config for models
    fn buildConfig(self: *Self, provider_name: []const u8) config_mod.CohereConfig {
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
    return std.posix.getenv("COHERE_API_KEY");
}

/// Headers function for config.
/// Caller owns the returned HashMap and must call deinit() when done.
fn getHeadersFn(config: *const config_mod.CohereConfig, allocator: std.mem.Allocator) std.StringHashMap([]const u8) {
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

/// Create a new Cohere provider with default settings
pub fn createCohere(allocator: std.mem.Allocator) CohereProvider {
    return CohereProvider.init(allocator, .{});
}

/// Create a new Cohere provider with custom settings
pub fn createCohereWithSettings(
    allocator: std.mem.Allocator,
    settings: CohereProviderSettings,
) CohereProvider {
    return CohereProvider.init(allocator, settings);
}


test "CohereProvider basic" {
    const allocator = std.testing.allocator;

    var provider = createCohereWithSettings(allocator, .{
        .base_url = "https://api.cohere.com/v2",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("cohere", provider.getProvider());
}

test "CohereProvider language model" {
    const allocator = std.testing.allocator;

    var provider = createCohereWithSettings(allocator, .{});
    defer provider.deinit();

    const model = provider.languageModel("command-r-plus");
    try std.testing.expectEqualStrings("command-r-plus", model.getModelId());
}

test "CohereProvider embedding model" {
    const allocator = std.testing.allocator;

    var provider = createCohereWithSettings(allocator, .{});
    defer provider.deinit();

    const model = provider.embeddingModel("embed-english-v3.0");
    try std.testing.expectEqualStrings("embed-english-v3.0", model.getModelId());
}

test "CohereProvider reranking model" {
    const allocator = std.testing.allocator;

    var provider = createCohereWithSettings(allocator, .{});
    defer provider.deinit();

    const model = provider.rerankingModel("rerank-v3.5");
    try std.testing.expectEqualStrings("rerank-v3.5", model.getModelId());
}
