const std = @import("std");
const provider_v3 = @import("provider").v3;
const openai_compat = @import("openai-compatible");

pub const PerplexityProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?*anyopaque = null,
};

pub const PerplexityProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: PerplexityProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: PerplexityProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.perplexity.ai",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "perplexity";
    }

    pub fn languageModel(self: *Self, model_id: []const u8) openai_compat.OpenAICompatibleChatLanguageModel {
        return openai_compat.OpenAICompatibleChatLanguageModel.init(
            self.allocator,
            model_id,
            .{
                .provider = "perplexity.chat",
                .base_url = self.base_url,
                .headers_fn = getHeadersFn,
                .http_client = self.settings.http_client,
            },
        );
    }

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

    fn embeddingModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.EmbeddingModelResult {
        _ = model_id;
        return .{ .err = error.NoSuchModel };
    }

    fn imageModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.ImageModelResult {
        _ = model_id;
        return .{ .err = error.NoSuchModel };
    }

    fn speechModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.SpeechModelResult {
        _ = model_id;
        return .{ .err = error.NoSuchModel };
    }

    fn transcriptionModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.TranscriptionModelResult {
        _ = model_id;
        return .{ .err = error.NoSuchModel };
    }
};

fn getApiKeyFromEnv() ?[]const u8 {
    return std.posix.getenv("PERPLEXITY_API_KEY");
}

fn getHeadersFn(config: *const openai_compat.OpenAICompatibleConfig) std.StringHashMap([]const u8) {
    _ = config;
    var headers = std.StringHashMap([]const u8).init(std.heap.page_allocator);
    headers.put("Content-Type", "application/json") catch {};

    if (getApiKeyFromEnv()) |api_key| {
        const auth_header = std.fmt.allocPrint(
            std.heap.page_allocator,
            "Bearer {s}",
            .{api_key},
        ) catch return headers;
        headers.put("Authorization", auth_header) catch {};
    }

    return headers;
}

pub fn createPerplexity(allocator: std.mem.Allocator) PerplexityProvider {
    return PerplexityProvider.init(allocator, .{});
}

pub fn createPerplexityWithSettings(
    allocator: std.mem.Allocator,
    settings: PerplexityProviderSettings,
) PerplexityProvider {
    return PerplexityProvider.init(allocator, settings);
}

var default_provider: ?PerplexityProvider = null;

pub fn perplexity() *PerplexityProvider {
    if (default_provider == null) {
        default_provider = createPerplexity(std.heap.page_allocator);
    }
    return &default_provider.?;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "PerplexityProvider basic initialization" {
    const allocator = std.testing.allocator;
    var provider = createPerplexity(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("perplexity", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.perplexity.ai", provider.base_url);
}

test "PerplexityProvider with default settings" {
    const allocator = std.testing.allocator;
    var provider = createPerplexityWithSettings(allocator, .{});
    defer provider.deinit();

    try std.testing.expectEqualStrings("perplexity", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.perplexity.ai", provider.base_url);
}

test "PerplexityProvider with custom base_url" {
    const allocator = std.testing.allocator;
    var provider = createPerplexityWithSettings(allocator, .{
        .base_url = "https://custom.perplexity.ai",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("perplexity", provider.getProvider());
    try std.testing.expectEqualStrings("https://custom.perplexity.ai", provider.base_url);
}

test "PerplexityProvider with custom api_key" {
    const allocator = std.testing.allocator;
    var provider = createPerplexityWithSettings(allocator, .{
        .api_key = "test-api-key-12345",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("perplexity", provider.getProvider());
}

test "PerplexityProvider with all custom settings" {
    const allocator = std.testing.allocator;

    var provider = createPerplexityWithSettings(allocator, .{
        .base_url = "https://custom.perplexity.ai/v1",
        .api_key = "test-key",
        .headers = null,
        .http_client = null,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("perplexity", provider.getProvider());
    try std.testing.expectEqualStrings("https://custom.perplexity.ai/v1", provider.base_url);
}

test "PerplexityProvider language model creation" {
    const allocator = std.testing.allocator;
    var provider = createPerplexity(allocator);
    defer provider.deinit();

    const model = provider.languageModel("llama-3.1-sonar-small-128k-online");
    try std.testing.expectEqualStrings("llama-3.1-sonar-small-128k-online", model.getModelId());
    try std.testing.expectEqualStrings("perplexity.chat", model.getProvider());
}

test "PerplexityProvider multiple model creation" {
    const allocator = std.testing.allocator;
    var provider = createPerplexity(allocator);
    defer provider.deinit();

    // Test various Perplexity model IDs
    const model1 = provider.languageModel("llama-3.1-sonar-small-128k-online");
    try std.testing.expectEqualStrings("llama-3.1-sonar-small-128k-online", model1.getModelId());

    const model2 = provider.languageModel("llama-3.1-sonar-large-128k-online");
    try std.testing.expectEqualStrings("llama-3.1-sonar-large-128k-online", model2.getModelId());

    const model3 = provider.languageModel("llama-3.1-sonar-huge-128k-online");
    try std.testing.expectEqualStrings("llama-3.1-sonar-huge-128k-online", model3.getModelId());
}

test "PerplexityProvider specification version" {
    try std.testing.expectEqualStrings("v3", PerplexityProvider.specification_version);
}

test "PerplexityProvider asProvider vtable" {
    const allocator = std.testing.allocator;
    var provider = createPerplexity(allocator);
    defer provider.deinit();

    var as_provider = provider.asProvider();

    // Test that language model works through vtable
    const result = as_provider.vtable.languageModel(as_provider.impl, "test-model");
    switch (result) {
        .ok => |model| {
            try std.testing.expectEqualStrings("test-model", model.getModelId());
        },
        .err => |err| {
            return err;
        },
    }
}

test "PerplexityProvider vtable unsupported models return errors" {
    const allocator = std.testing.allocator;
    var provider = createPerplexity(allocator);
    defer provider.deinit();

    var as_provider = provider.asProvider();

    // Test embedding model returns error
    const embedding_result = as_provider.vtable.embeddingModel(as_provider.impl, "test-model");
    switch (embedding_result) {
        .ok => return error.TestExpectedError,
        .err => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
    }

    // Test image model returns error
    const image_result = as_provider.vtable.imageModel(as_provider.impl, "test-model");
    switch (image_result) {
        .ok => return error.TestExpectedError,
        .err => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
    }

    // Test speech model returns error
    const speech_result = as_provider.vtable.speechModel(as_provider.impl, "test-model");
    switch (speech_result) {
        .ok => return error.TestExpectedError,
        .err => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
    }

    // Test transcription model returns error
    const transcription_result = as_provider.vtable.transcriptionModel(as_provider.impl, "test-model");
    switch (transcription_result) {
        .ok => return error.TestExpectedError,
        .err => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
    }
}

test "PerplexityProvider singleton instance" {
    // Get default provider
    const provider1 = perplexity();
    const provider2 = perplexity();

    // Should return the same instance
    try std.testing.expectEqual(provider1, provider2);
    try std.testing.expectEqualStrings("perplexity", provider1.getProvider());
}

test "createPerplexity creates valid provider" {
    const allocator = std.testing.allocator;
    var provider = createPerplexity(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("perplexity", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.perplexity.ai", provider.base_url);
}

test "createPerplexityWithSettings creates valid provider" {
    const allocator = std.testing.allocator;
    var provider = createPerplexityWithSettings(allocator, .{
        .base_url = "https://test.api.perplexity.ai",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("perplexity", provider.getProvider());
    try std.testing.expectEqualStrings("https://test.api.perplexity.ai", provider.base_url);
}

test "PerplexityProviderSettings default values" {
    const settings: PerplexityProviderSettings = .{};

    try std.testing.expect(settings.base_url == null);
    try std.testing.expect(settings.api_key == null);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}

test "PerplexityProviderSettings custom values" {
    const settings: PerplexityProviderSettings = .{
        .base_url = "https://custom.api.perplexity.ai",
        .api_key = "test-key-123",
        .headers = null,
        .http_client = null,
    };

    try std.testing.expect(settings.base_url != null);
    try std.testing.expectEqualStrings("https://custom.api.perplexity.ai", settings.base_url.?);
    try std.testing.expect(settings.api_key != null);
    try std.testing.expectEqualStrings("test-key-123", settings.api_key.?);
}

test "getHeadersFn creates headers with content type" {
    const config = openai_compat.OpenAICompatibleConfig{
        .provider = "perplexity.chat",
        .base_url = "https://api.perplexity.ai",
        .headers_fn = getHeadersFn,
        .http_client = null,
    };

    var headers = getHeadersFn(&config);
    defer headers.deinit();

    // Content-Type header should always be present
    const content_type = headers.get("Content-Type");
    try std.testing.expect(content_type != null);
    try std.testing.expectEqualStrings("application/json", content_type.?);
}

test "PerplexityProvider model with custom settings preserves base_url" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.perplexity.ai/v2";

    var provider = createPerplexityWithSettings(allocator, .{
        .base_url = custom_url,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings(custom_url, provider.base_url);

    const model = provider.languageModel("test-model");
    try std.testing.expectEqualStrings("test-model", model.getModelId());
}

test "PerplexityProvider init with null settings uses defaults" {
    const allocator = std.testing.allocator;
    var provider = PerplexityProvider.init(allocator, .{});
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://api.perplexity.ai", provider.base_url);
}

test "PerplexityProvider deinit is safe to call" {
    const allocator = std.testing.allocator;
    var provider = createPerplexity(allocator);

    // Should not crash or leak
    provider.deinit();

    // Safe to call multiple times
    provider.deinit();
}

test "PerplexityProvider getProvider is const" {
    const allocator = std.testing.allocator;
    var provider = createPerplexity(allocator);
    defer provider.deinit();

    const const_provider: *const PerplexityProvider = &provider;
    const name = const_provider.getProvider();

    try std.testing.expectEqualStrings("perplexity", name);
}

test "PerplexityProvider supports various model names" {
    const allocator = std.testing.allocator;
    var provider = createPerplexity(allocator);
    defer provider.deinit();

    // Test with various valid model ID formats
    const test_models = [_][]const u8{
        "llama-3.1-sonar-small-128k-online",
        "llama-3.1-sonar-large-128k-online",
        "llama-3.1-sonar-huge-128k-online",
        "llama-3.1-8b-instruct",
        "llama-3.1-70b-instruct",
        "custom-model-name",
        "model-with-numbers-123",
        "model_with_underscores",
    };

    for (test_models) |model_id| {
        const model = provider.languageModel(model_id);
        try std.testing.expectEqualStrings(model_id, model.getModelId());
        try std.testing.expectEqualStrings("perplexity.chat", model.getProvider());
    }
}

test "PerplexityProvider edge case: empty model ID" {
    const allocator = std.testing.allocator;
    var provider = createPerplexity(allocator);
    defer provider.deinit();

    // Should handle empty model ID without crashing
    const model = provider.languageModel("");
    try std.testing.expectEqualStrings("", model.getModelId());
}

test "PerplexityProvider edge case: very long model ID" {
    const allocator = std.testing.allocator;
    var provider = createPerplexity(allocator);
    defer provider.deinit();

    const long_model_id = "a" ** 256;
    const model = provider.languageModel(long_model_id);
    try std.testing.expectEqualStrings(long_model_id, model.getModelId());
}

test "PerplexityProvider edge case: special characters in model ID" {
    const allocator = std.testing.allocator;
    var provider = createPerplexity(allocator);
    defer provider.deinit();

    // Test model IDs with special characters
    const special_models = [_][]const u8{
        "model-with-dashes",
        "model_with_underscores",
        "model.with.dots",
        "model:with:colons",
        "model/with/slashes",
    };

    for (special_models) |model_id| {
        const model = provider.languageModel(model_id);
        try std.testing.expectEqualStrings(model_id, model.getModelId());
    }
}
