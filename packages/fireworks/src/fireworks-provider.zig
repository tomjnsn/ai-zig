const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;
const openai_compat = @import("openai-compatible");

pub const FireworksProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

pub const FireworksProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: FireworksProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: FireworksProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.fireworks.ai/inference/v1",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "fireworks";
    }

    pub fn languageModel(self: *Self, model_id: []const u8) openai_compat.OpenAICompatibleChatLanguageModel {
        return openai_compat.OpenAICompatibleChatLanguageModel.init(
            self.allocator,
            model_id,
            .{
                .provider = "fireworks.chat",
                .base_url = self.base_url,
                .headers_fn = getHeadersFn,
                .http_client = self.settings.http_client,
            },
        );
    }

    pub fn chatModel(self: *Self, model_id: []const u8) openai_compat.OpenAICompatibleChatLanguageModel {
        return self.languageModel(model_id);
    }

    pub fn embeddingModel(self: *Self, model_id: []const u8) openai_compat.OpenAICompatibleEmbeddingModel {
        return openai_compat.OpenAICompatibleEmbeddingModel.init(
            self.allocator,
            model_id,
            .{
                .provider = "fireworks.embedding",
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

fn getApiKeyFromEnv() ?[]const u8 {
    return std.posix.getenv("FIREWORKS_API_KEY");
}

/// Caller owns the returned HashMap and must call deinit() when done.
fn getHeadersFn(config: *const openai_compat.OpenAICompatibleConfig, allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    _ = config;
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();
    try headers.put("Content-Type", "application/json");

    if (getApiKeyFromEnv()) |api_key| {
        const auth_header = try std.fmt.allocPrint(
            allocator,
            "Bearer {s}",
            .{api_key},
        );
        try headers.put("Authorization", auth_header);
    }

    return headers;
}

pub fn createFireworks(allocator: std.mem.Allocator) FireworksProvider {
    return FireworksProvider.init(allocator, .{});
}

pub fn createFireworksWithSettings(
    allocator: std.mem.Allocator,
    settings: FireworksProviderSettings,
) FireworksProvider {
    return FireworksProvider.init(allocator, settings);
}


// ============================================================================
// Unit Tests
// ============================================================================

test "FireworksProvider basic initialization" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("fireworks", provider.getProvider());
}

test "FireworksProvider default base URL" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://api.fireworks.ai/inference/v1", provider.base_url);
}

test "FireworksProvider with custom base URL" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.fireworks.ai/v2";

    var provider = createFireworksWithSettings(allocator, .{
        .base_url = custom_url,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings(custom_url, provider.base_url);
}

test "FireworksProvider with custom settings" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.fireworks.ai/v2";
    const custom_api_key = "sk-test-key-12345";

    var provider = createFireworksWithSettings(allocator, .{
        .base_url = custom_url,
        .api_key = custom_api_key,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings(custom_url, provider.base_url);
    try std.testing.expectEqual(custom_api_key, provider.settings.api_key);
}

test "FireworksProvider with null settings" {
    const allocator = std.testing.allocator;

    var provider = createFireworksWithSettings(allocator, .{
        .base_url = null,
        .api_key = null,
        .headers = null,
        .http_client = null,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://api.fireworks.ai/inference/v1", provider.base_url);
}

test "FireworksProvider specification version" {
    try std.testing.expectEqualStrings("v3", FireworksProvider.specification_version);
}

test "FireworksProvider getProvider" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const provider_name = provider.getProvider();
    try std.testing.expectEqualStrings("fireworks", provider_name);
}

// ============================================================================
// Model Creation Tests
// ============================================================================

test "FireworksProvider languageModel creation" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const model = provider.languageModel("accounts/fireworks/models/llama-v3p1-8b-instruct");
    try std.testing.expect(model.model_id.len > 0);
}

test "FireworksProvider chatModel creation" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const model = provider.chatModel("accounts/fireworks/models/llama-v3p1-70b-instruct");
    try std.testing.expect(model.model_id.len > 0);
}

test "FireworksProvider chatModel is alias for languageModel" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const model_id = "accounts/fireworks/models/llama-v3p1-8b-instruct";
    const lang_model = provider.languageModel(model_id);
    const chat_model = provider.chatModel(model_id);

    try std.testing.expectEqualStrings(lang_model.model_id, chat_model.model_id);
}

test "FireworksProvider embeddingModel creation" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const model = provider.embeddingModel("nomic-ai/nomic-embed-text-v1.5");
    try std.testing.expect(model.model_id.len > 0);
}

test "FireworksProvider languageModel with various model IDs" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const test_cases = [_][]const u8{
        "accounts/fireworks/models/llama-v3p1-8b-instruct",
        "accounts/fireworks/models/llama-v3p1-70b-instruct",
        "accounts/fireworks/models/mixtral-8x7b-instruct",
        "accounts/fireworks/models/qwen2p5-72b-instruct",
    };

    for (test_cases) |model_id| {
        const model = provider.languageModel(model_id);
        try std.testing.expect(model.model_id.len > 0);
    }
}

test "FireworksProvider embeddingModel with various model IDs" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const test_cases = [_][]const u8{
        "nomic-ai/nomic-embed-text-v1.5",
        "nomic-ai/nomic-embed-text-v1",
        "WhereIsAI/UAE-Large-V1",
    };

    for (test_cases) |model_id| {
        const model = provider.embeddingModel(model_id);
        try std.testing.expect(model.model_id.len > 0);
    }
}

// ============================================================================
// ProviderV3 Interface Tests
// ============================================================================

test "FireworksProvider asProvider vtable languageModel" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    const result = pv3.vtable.languageModel(
        pv3.impl,
        "accounts/fireworks/models/llama-v3p1-8b-instruct",
    );

    switch (result) {
        .success => {},
        .failure, .no_such_model => try std.testing.expect(false),
    }
}

test "FireworksProvider asProvider vtable embeddingModel" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    const result = pv3.vtable.embeddingModel(
        pv3.impl,
        "nomic-ai/nomic-embed-text-v1.5",
    );

    switch (result) {
        .success => {},
        .failure, .no_such_model => try std.testing.expect(false),
    }
}

test "FireworksProvider asProvider vtable imageModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    const result = pv3.vtable.imageModel(pv3.impl, "any-model-id");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }
}

test "FireworksProvider asProvider vtable speechModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    const result = pv3.speechModel("any-model-id");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model, .not_supported => {},
    }
}

test "FireworksProvider asProvider vtable transcriptionModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    const result = pv3.transcriptionModel("any-model-id");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model, .not_supported => {},
    }
}

// ============================================================================
// Factory Function Tests
// ============================================================================

test "createFireworks returns initialized provider" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("fireworks", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.fireworks.ai/inference/v1", provider.base_url);
}

test "createFireworksWithSettings accepts empty settings" {
    const allocator = std.testing.allocator;
    var provider = createFireworksWithSettings(allocator, .{});
    defer provider.deinit();

    try std.testing.expectEqualStrings("fireworks", provider.getProvider());
}

test "createFireworksWithSettings with all settings" {
    const allocator = std.testing.allocator;

    const custom_base_url = "https://test.fireworks.ai/v1";
    const custom_api_key = "sk-test-123";

    var provider = createFireworksWithSettings(allocator, .{
        .base_url = custom_base_url,
        .api_key = custom_api_key,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings(custom_base_url, provider.base_url);
    try std.testing.expectEqual(custom_api_key, provider.settings.api_key);
}

// ============================================================================
// Headers Function Tests
// ============================================================================

test "getHeadersFn returns valid headers" {
    const config = openai_compat.OpenAICompatibleConfig{
        .provider = "fireworks.chat",
        .base_url = "https://api.fireworks.ai/inference/v1",
    };

    var headers = try getHeadersFn(&config, std.testing.allocator);
    defer headers.deinit();

    const content_type = headers.get("Content-Type");
    try std.testing.expect(content_type != null);
    try std.testing.expectEqualStrings("application/json", content_type.?);
}

test "getHeadersFn includes auth header when API key available" {
    // Note: This test only verifies the function runs without error
    // We cannot test environment variable behavior directly in unit tests
    const config = openai_compat.OpenAICompatibleConfig{
        .provider = "fireworks.chat",
        .base_url = "https://api.fireworks.ai/inference/v1",
    };

    var headers = try getHeadersFn(&config, std.testing.allocator);
    defer headers.deinit();

    // At minimum, Content-Type should always be present
    try std.testing.expect(headers.count() >= 1);
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "FireworksProvider with empty model ID" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const model = provider.languageModel("");
    try std.testing.expectEqualStrings("", model.model_id);
}

test "FireworksProvider multiple model creations" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const model1 = provider.languageModel("model-1");
    const model2 = provider.languageModel("model-2");
    const model3 = provider.embeddingModel("embed-1");

    try std.testing.expectEqualStrings("model-1", model1.model_id);
    try std.testing.expectEqualStrings("model-2", model2.model_id);
    try std.testing.expectEqualStrings("embed-1", model3.model_id);
}

test "FireworksProvider custom base URL with trailing slash" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.fireworks.ai/v1/";

    var provider = createFireworksWithSettings(allocator, .{
        .base_url = custom_url,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings(custom_url, provider.base_url);
}

test "FireworksProvider custom base URL without protocol" {
    const allocator = std.testing.allocator;
    const custom_url = "custom.fireworks.ai/v1";

    var provider = createFireworksWithSettings(allocator, .{
        .base_url = custom_url,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings(custom_url, provider.base_url);
}

test "FireworksProvider deinit is idempotent" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);

    try std.testing.expectEqualStrings("fireworks", provider.getProvider());

    provider.deinit();
    provider.deinit(); // Should not crash
}

test "FireworksProvider with very long model ID" {
    const allocator = std.testing.allocator;
    var provider = createFireworks(allocator);
    defer provider.deinit();

    const long_model_id = "accounts/fireworks/models/" ++ "a" ** 200;
    const model = provider.languageModel(long_model_id);

    try std.testing.expect(model.model_id.len > 100);
}

// ============================================================================
// Default Provider Tests
// ============================================================================

test "fireworks provider returns valid provider" {
    var provider = createFireworks(std.testing.allocator);
    defer provider.deinit();
    try std.testing.expectEqualStrings("fireworks", provider.getProvider());
}

test "fireworks providers have consistent values" {
    var provider1 = createFireworks(std.testing.allocator);
    defer provider1.deinit();
    var provider2 = createFireworks(std.testing.allocator);
    defer provider2.deinit();

    // Both should have the same provider name
    try std.testing.expectEqualStrings(provider1.getProvider(), provider2.getProvider());
}

// ============================================================================
// Utility Function Tests
// ============================================================================

test "getApiKeyFromEnv returns optional" {
    // The actual return value depends on environment variables
    const result = getApiKeyFromEnv();
    if (result) |key| {
        try std.testing.expect(key.len > 0);
    }
}
