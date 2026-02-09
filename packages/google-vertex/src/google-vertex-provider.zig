const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");
const lm = @import("../../provider/src/language-model/v3/index.zig");

const config_mod = @import("google-vertex-config.zig");
const embed_model = @import("google-vertex-embedding-model.zig");
const image_model = @import("google-vertex-image-model.zig");
const options_mod = @import("google-vertex-options.zig");

// Import Google AI language model (Vertex reuses it)
const google_lang_model = @import("../../google/src/google-generative-ai-language-model.zig");
const google_config = @import("../../google/src/google-config.zig");

/// Google Vertex AI Provider settings
pub const GoogleVertexProviderSettings = struct {
    /// API key for express mode authentication
    api_key: ?[]const u8 = null,

    /// Google Cloud project ID
    project: ?[]const u8 = null,

    /// Google Cloud region/location
    location: ?[]const u8 = null,

    /// Base URL for API calls (overrides default)
    base_url: ?[]const u8 = null,

    /// Custom headers to include in the requests
    headers: ?std.StringHashMap([]const u8) = null,

    /// HTTP client for making requests
    http_client: ?provider_utils.HttpClient = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// Google Vertex AI Provider
pub const GoogleVertexProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: GoogleVertexProviderSettings,
    base_url: []const u8,
    api_key: ?[]const u8,

    pub const specification_version = "v3";

    /// Create a new Google Vertex AI provider
    pub fn init(allocator: std.mem.Allocator, settings: GoogleVertexProviderSettings) Self {
        // Get API key from settings or environment
        const api_key = settings.api_key orelse getApiKeyFromEnv();

        // Get project and location
        const project = settings.project orelse getProjectFromEnv() orelse "unknown-project";
        const location = settings.location orelse getLocationFromEnv() orelse "us-central1";

        // Build base URL
        const base_url = settings.base_url orelse blk: {
            if (api_key != null) {
                break :blk config_mod.express_mode_base_url;
            }
            // For non-express mode, we need to build the URL
            // This would normally be done with the project/location
            break :blk buildDefaultBaseUrl(allocator, project, location) catch config_mod.express_mode_base_url;
        };

        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = base_url,
            .api_key = api_key,
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
        return "google.vertex";
    }

    // -- Language Models --

    /// Create a language model
    pub fn languageModel(self: *Self, model_id: []const u8) google_lang_model.GoogleGenerativeAILanguageModel {
        return google_lang_model.GoogleGenerativeAILanguageModel.init(
            self.allocator,
            model_id,
            self.buildLanguageModelConfig(),
        );
    }

    /// Build config for language model
    fn buildLanguageModelConfig(self: *Self) google_config.GoogleGenerativeAIConfig {
        return .{
            .provider = "google.vertex.chat",
            .base_url = self.base_url,
            .headers_fn = getHeadersFn,
            .http_client = self.settings.http_client,
            .generate_id = self.settings.generate_id,
        };
    }

    // -- Embedding Models --

    /// Create an embedding model
    pub fn embeddingModel(self: *Self, model_id: []const u8) embed_model.GoogleVertexEmbeddingModel {
        return embed_model.GoogleVertexEmbeddingModel.init(
            self.allocator,
            model_id,
            self.buildEmbeddingConfig(),
        );
    }

    /// Create an embedding model (deprecated alias)
    pub fn textEmbeddingModel(self: *Self, model_id: []const u8) embed_model.GoogleVertexEmbeddingModel {
        return self.embeddingModel(model_id);
    }

    /// Build config for embedding model
    fn buildEmbeddingConfig(self: *Self) config_mod.GoogleVertexConfig {
        return .{
            .provider = "google.vertex.embedding",
            .base_url = self.base_url,
            .headers_fn = getVertexHeadersFn,
            .http_client = self.settings.http_client,
            .generate_id = self.settings.generate_id,
        };
    }

    // -- Image Models --

    /// Create an image model
    pub fn imageModel(self: *Self, model_id: []const u8) image_model.GoogleVertexImageModel {
        return image_model.GoogleVertexImageModel.init(
            self.allocator,
            model_id,
            self.buildImageConfig(),
        );
    }

    /// Create an image model (alias)
    pub fn image(self: *Self, model_id: []const u8) image_model.GoogleVertexImageModel {
        return self.imageModel(model_id);
    }

    /// Build config for image model
    fn buildImageConfig(self: *Self) config_mod.GoogleVertexConfig {
        return .{
            .provider = "google.vertex.image",
            .base_url = self.base_url,
            .headers_fn = getVertexHeadersFn,
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

/// Get API key from environment
fn getApiKeyFromEnv() ?[]const u8 {
    return std.posix.getenv("GOOGLE_VERTEX_API_KEY");
}

/// Get project from environment
fn getProjectFromEnv() ?[]const u8 {
    return std.posix.getenv("GOOGLE_VERTEX_PROJECT");
}

/// Get location from environment
fn getLocationFromEnv() ?[]const u8 {
    return std.posix.getenv("GOOGLE_VERTEX_LOCATION");
}

/// Build default base URL
fn buildDefaultBaseUrl(allocator: std.mem.Allocator, project: []const u8, location: []const u8) ![]const u8 {
    return config_mod.buildBaseUrl(allocator, project, location, null);
}

/// Headers function for Google AI config.
/// Caller owns the returned HashMap and must call deinit() when done.
fn getHeadersFn(config: *const google_config.GoogleGenerativeAIConfig, allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    _ = config;
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    // Add content-type
    try headers.put("Content-Type", "application/json");

    return headers;
}

/// Headers function for Vertex config.
/// Caller owns the returned HashMap and must call deinit() when done.
fn getVertexHeadersFn(config: *const config_mod.GoogleVertexConfig, allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    _ = config;
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    // Add content-type
    try headers.put("Content-Type", "application/json");

    return headers;
}

/// Create a new Google Vertex AI provider with default settings
pub fn createVertex(allocator: std.mem.Allocator) GoogleVertexProvider {
    return GoogleVertexProvider.init(allocator, .{});
}

/// Create a new Google Vertex AI provider with custom settings
pub fn createVertexWithSettings(
    allocator: std.mem.Allocator,
    settings: GoogleVertexProviderSettings,
) GoogleVertexProvider {
    return GoogleVertexProvider.init(allocator, settings);
}


test "GoogleVertexProvider basic" {
    const allocator = std.testing.allocator;

    var provider = createVertex(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("google.vertex", provider.getProvider());
}

test "GoogleVertexProvider with custom settings" {
    const allocator = std.testing.allocator;

    var provider = createVertexWithSettings(allocator, .{
        .project = "my-project",
        .location = "us-central1",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("google.vertex", provider.getProvider());
}

test "GoogleVertexProvider language model" {
    const allocator = std.testing.allocator;

    var provider = createVertex(allocator);
    defer provider.deinit();

    const model = provider.languageModel("gemini-2.0-flash");
    try std.testing.expectEqualStrings("gemini-2.0-flash", model.getModelId());
}

test "GoogleVertexProvider embedding model" {
    const allocator = std.testing.allocator;

    var provider = createVertex(allocator);
    defer provider.deinit();

    const model = provider.embeddingModel("text-embedding-004");
    try std.testing.expectEqualStrings("text-embedding-004", model.getModelId());
}

test "GoogleVertexProvider image model" {
    const allocator = std.testing.allocator;

    var provider = createVertex(allocator);
    defer provider.deinit();

    const model = provider.imageModel("imagen-3.0-generate-001");
    try std.testing.expectEqualStrings("imagen-3.0-generate-001", model.getModelId());
}
