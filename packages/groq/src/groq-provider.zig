const std = @import("std");
const provider_v3 = @import("provider").provider;

const config_mod = @import("groq-config.zig");
const chat_model = @import("groq-chat-language-model.zig");
const transcription_model = @import("groq-transcription-model.zig");

/// Groq Provider settings
pub const GroqProviderSettings = struct {
    /// Base URL for API calls
    base_url: ?[]const u8 = null,

    /// API key
    api_key: ?[]const u8 = null,

    /// Custom headers
    headers: ?std.StringHashMap([]const u8) = null,

    /// HTTP client
    http_client: ?*anyopaque = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// Groq Provider
pub const GroqProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: GroqProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    /// Create a new Groq provider
    pub fn init(allocator: std.mem.Allocator, settings: GroqProviderSettings) Self {
        const base_url = settings.base_url orelse "https://api.groq.com/openai/v1";

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
        return "groq";
    }

    // -- Language Models --

    /// Create a language model
    pub fn languageModel(self: *Self, model_id: []const u8) chat_model.GroqChatLanguageModel {
        return chat_model.GroqChatLanguageModel.init(
            self.allocator,
            model_id,
            self.buildConfig("groq.chat"),
        );
    }

    /// Create a language model (alias)
    pub fn chat(self: *Self, model_id: []const u8) chat_model.GroqChatLanguageModel {
        return self.languageModel(model_id);
    }

    // -- Transcription Models --

    /// Create a transcription model
    pub fn transcriptionModel(self: *Self, model_id: []const u8) transcription_model.GroqTranscriptionModel {
        return transcription_model.GroqTranscriptionModel.init(
            self.allocator,
            model_id,
            self.buildConfig("groq.transcription"),
        );
    }

    /// Create a transcription model (alias)
    pub fn transcription(self: *Self, model_id: []const u8) transcription_model.GroqTranscriptionModel {
        return self.transcriptionModel(model_id);
    }

    /// Build config for models
    fn buildConfig(self: *Self, provider_name: []const u8) config_mod.GroqConfig {
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

    fn embeddingModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.EmbeddingModelResult {
        _ = model_id;
        return .{ .failure = error.NoSuchModel };
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
        // Note: Transcription model doesn't implement V3 interface directly
        return .{ .failure = error.NoSuchModel };
    }
};

/// Get API key from environment
fn getApiKeyFromEnv() ?[]const u8 {
    return std.posix.getenv("GROQ_API_KEY");
}

/// Headers function for config
fn getHeadersFn(config: *const config_mod.GroqConfig, allocator: std.mem.Allocator) std.StringHashMap([]const u8) {
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

/// Create a new Groq provider with default settings
pub fn createGroq(allocator: std.mem.Allocator) GroqProvider {
    return GroqProvider.init(allocator, .{});
}

/// Create a new Groq provider with custom settings
pub fn createGroqWithSettings(
    allocator: std.mem.Allocator,
    settings: GroqProviderSettings,
) GroqProvider {
    return GroqProvider.init(allocator, settings);
}

/// Default Groq provider instance (created lazily)
var default_provider: ?GroqProvider = null;

/// Get the default Groq provider
pub fn groq() *GroqProvider {
    if (default_provider == null) {
        default_provider = createGroq(std.heap.page_allocator);
    }
    return &default_provider.?;
}

test "GroqProvider basic" {
    const allocator = std.testing.allocator;

    var provider = createGroqWithSettings(allocator, .{
        .base_url = "https://api.groq.com/openai/v1",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("groq", provider.getProvider());
}

test "GroqProvider language model" {
    const allocator = std.testing.allocator;

    var provider = createGroqWithSettings(allocator, .{});
    defer provider.deinit();

    const model = provider.languageModel("llama-3.3-70b-versatile");
    try std.testing.expectEqualStrings("llama-3.3-70b-versatile", model.getModelId());
}

test "GroqProvider transcription model" {
    const allocator = std.testing.allocator;

    var provider = createGroqWithSettings(allocator, .{});
    defer provider.deinit();

    const model = provider.transcriptionModel("whisper-large-v3-turbo");
    try std.testing.expectEqualStrings("whisper-large-v3-turbo", model.getModelId());
}

test "GroqProvider initialization with default settings" {
    const allocator = std.testing.allocator;

    var provider = createGroq(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("groq", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.groq.com/openai/v1", provider.base_url);
}

test "GroqProvider initialization with custom base URL" {
    const allocator = std.testing.allocator;

    var provider = createGroqWithSettings(allocator, .{
        .base_url = "https://custom.groq.com/v2",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://custom.groq.com/v2", provider.base_url);
}

test "GroqProvider specification version" {
    try std.testing.expectEqualStrings("v3", GroqProvider.specification_version);
}

test "GroqProvider chat alias for language model" {
    const allocator = std.testing.allocator;

    var provider = createGroq(allocator);
    defer provider.deinit();

    const model1 = provider.chat("llama-3.3-70b-versatile");
    const model2 = provider.languageModel("llama-3.3-70b-versatile");

    try std.testing.expectEqualStrings(model1.getModelId(), model2.getModelId());
    try std.testing.expectEqualStrings(model1.getProvider(), model2.getProvider());
}

test "GroqProvider transcription alias" {
    const allocator = std.testing.allocator;

    var provider = createGroq(allocator);
    defer provider.deinit();

    const model1 = provider.transcription("whisper-large-v3");
    const model2 = provider.transcriptionModel("whisper-large-v3");

    try std.testing.expectEqualStrings(model1.getModelId(), model2.getModelId());
}

test "GroqProvider buildConfig generates correct config" {
    const allocator = std.testing.allocator;

    var provider = createGroqWithSettings(allocator, .{
        .base_url = "https://test.groq.com",
    });
    defer provider.deinit();

    const config = provider.buildConfig("groq.test");
    try std.testing.expectEqualStrings("groq.test", config.provider);
    try std.testing.expectEqualStrings("https://test.groq.com", config.base_url);
}

test "GroqProvider ProviderV3 interface language model" {
    const allocator = std.testing.allocator;

    var provider = createGroq(allocator);
    defer provider.deinit();

    const provider_v3_interface = provider.asProvider();
    const result = provider_v3_interface.vtable.languageModel(provider_v3_interface.impl, "llama-3.3-70b-versatile");

    try std.testing.expect(result == .success);
}

test "GroqProvider ProviderV3 interface unsupported models return errors" {
    const allocator = std.testing.allocator;

    var provider = createGroq(allocator);
    defer provider.deinit();

    const provider_v3_interface = provider.asProvider();

    const embedding_result = provider_v3_interface.vtable.embeddingModel(provider_v3_interface.impl, "test");
    switch (embedding_result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }

    const image_result = provider_v3_interface.vtable.imageModel(provider_v3_interface.impl, "test");
    switch (image_result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }

    const speech_result = provider_v3_interface.speechModel("test");
    switch (speech_result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model, .not_supported => {},
    }

    const transcription_result = provider_v3_interface.transcriptionModel("test");
    switch (transcription_result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model, .not_supported => {},
    }
}

test "GroqProvider multiple models can be created from same provider" {
    const allocator = std.testing.allocator;

    var provider = createGroq(allocator);
    defer provider.deinit();

    const model1 = provider.languageModel("llama-3.3-70b-versatile");
    const model2 = provider.languageModel("llama-3.1-8b-instant");
    const model3 = provider.transcriptionModel("whisper-large-v3");

    try std.testing.expectEqualStrings("llama-3.3-70b-versatile", model1.getModelId());
    try std.testing.expectEqualStrings("llama-3.1-8b-instant", model2.getModelId());
    try std.testing.expectEqualStrings("whisper-large-v3", model3.getModelId());
}
