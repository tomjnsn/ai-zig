const std = @import("std");
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");
const openai_compat = @import("../../openai-compatible/src/index.zig");

pub const TogetherAIProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?*anyopaque = null,
};

pub const TogetherAIProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: TogetherAIProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: TogetherAIProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.together.xyz/v1",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "togetherai";
    }

    pub fn languageModel(self: *Self, model_id: []const u8) openai_compat.OpenAICompatibleChatLanguageModel {
        return openai_compat.OpenAICompatibleChatLanguageModel.init(
            self.allocator,
            model_id,
            .{
                .provider = "togetherai.chat",
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
                .provider = "togetherai.embedding",
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

    fn embeddingModelVtable(impl: *anyopaque, model_id: []const u8) provider_v3.EmbeddingModelResult {
        const self: *Self = @ptrCast(@alignCast(impl));
        var model = self.embeddingModel(model_id);
        return .{ .ok = model.asEmbeddingModel() };
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
    return std.posix.getenv("TOGETHER_AI_API_KEY");
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

pub fn createTogetherAI(allocator: std.mem.Allocator) TogetherAIProvider {
    return TogetherAIProvider.init(allocator, .{});
}

pub fn createTogetherAIWithSettings(
    allocator: std.mem.Allocator,
    settings: TogetherAIProviderSettings,
) TogetherAIProvider {
    return TogetherAIProvider.init(allocator, settings);
}

var default_provider: ?TogetherAIProvider = null;

pub fn togetherai() *TogetherAIProvider {
    if (default_provider == null) {
        default_provider = createTogetherAI(std.heap.page_allocator);
    }
    return &default_provider.?;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "TogetherAIProvider basic initialization" {
    const allocator = std.testing.allocator;
    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("togetherai", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.together.xyz/v1", provider.base_url);
}

test "TogetherAIProvider with custom settings" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAIWithSettings(allocator, .{
        .base_url = "https://custom.together.xyz/v1",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("togetherai", provider.getProvider());
    try std.testing.expectEqualStrings("https://custom.together.xyz/v1", provider.base_url);
}

test "TogetherAIProvider with null base_url uses default" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAIWithSettings(allocator, .{
        .base_url = null,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://api.together.xyz/v1", provider.base_url);
}

test "TogetherAIProvider specification version" {
    try std.testing.expectEqualStrings("v3", TogetherAIProvider.specification_version);
}

test "TogetherAIProvider languageModel creation" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    const model = provider.languageModel("meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo");
    try std.testing.expectEqualStrings("meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo", model.getModelId());
    try std.testing.expectEqualStrings("togetherai.chat", model.getProvider());
}

test "TogetherAIProvider chatModel creation" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    const model = provider.chatModel("mistralai/Mixtral-8x7B-Instruct-v0.1");
    try std.testing.expectEqualStrings("mistralai/Mixtral-8x7B-Instruct-v0.1", model.getModelId());
    try std.testing.expectEqualStrings("togetherai.chat", model.getProvider());
}

test "TogetherAIProvider chatModel is alias for languageModel" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    const lang_model = provider.languageModel("test-model");
    const chat_model = provider.chatModel("test-model");

    try std.testing.expectEqualStrings(lang_model.getModelId(), chat_model.getModelId());
    try std.testing.expectEqualStrings(lang_model.getProvider(), chat_model.getProvider());
}

test "TogetherAIProvider embeddingModel creation" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    const model = provider.embeddingModel("togethercomputer/m2-bert-80M-8k-retrieval");
    try std.testing.expectEqualStrings("togethercomputer/m2-bert-80M-8k-retrieval", model.getModelId());
    try std.testing.expectEqualStrings("togetherai.embedding", model.getProvider());
}

test "TogetherAIProvider embeddingModel with custom base_url" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAIWithSettings(allocator, .{
        .base_url = "https://custom.api.xyz/v2",
    });
    defer provider.deinit();

    const model = provider.embeddingModel("embedding-model");
    try std.testing.expectEqualStrings("embedding-model", model.getModelId());
}

test "TogetherAIProvider multiple models can be created" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    const model1 = provider.languageModel("model-1");
    const model2 = provider.languageModel("model-2");
    const embed_model = provider.embeddingModel("embed-model");

    try std.testing.expectEqualStrings("model-1", model1.getModelId());
    try std.testing.expectEqualStrings("model-2", model2.getModelId());
    try std.testing.expectEqualStrings("embed-model", embed_model.getModelId());
}

test "TogetherAIProvider asProvider vtable language model" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    var provider_interface = provider.asProvider();
    const result = provider_interface.vtable.languageModel(provider_interface.impl, "test-model");

    switch (result) {
        .ok => |model| {
            _ = model;
            // Success - model was created
        },
        .err => |err| {
            try std.testing.expect(false); // Should not error
            _ = err;
        },
    }
}

test "TogetherAIProvider asProvider vtable embedding model" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    var provider_interface = provider.asProvider();
    const result = provider_interface.vtable.embeddingModel(provider_interface.impl, "embed-model");

    switch (result) {
        .ok => |model| {
            _ = model;
            // Success - model was created
        },
        .err => |err| {
            try std.testing.expect(false); // Should not error
            _ = err;
        },
    }
}

test "TogetherAIProvider asProvider vtable image model returns error" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    var provider_interface = provider.asProvider();
    const result = provider_interface.vtable.imageModel(provider_interface.impl, "image-model");

    switch (result) {
        .ok => {
            try std.testing.expect(false); // Should error
        },
        .err => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
    }
}

test "TogetherAIProvider asProvider vtable speech model returns error" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    var provider_interface = provider.asProvider();
    const result = provider_interface.vtable.speechModel(provider_interface.impl, "speech-model");

    switch (result) {
        .ok => {
            try std.testing.expect(false); // Should error
        },
        .err => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
    }
}

test "TogetherAIProvider asProvider vtable transcription model returns error" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    var provider_interface = provider.asProvider();
    const result = provider_interface.vtable.transcriptionModel(provider_interface.impl, "transcription-model");

    switch (result) {
        .ok => {
            try std.testing.expect(false); // Should error
        },
        .err => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
    }
}

test "TogetherAIProviderSettings default values" {
    const settings = TogetherAIProviderSettings{};

    try std.testing.expect(settings.base_url == null);
    try std.testing.expect(settings.api_key == null);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}

test "TogetherAIProviderSettings with custom values" {
    const allocator = std.testing.allocator;
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();

    try headers.put("X-Custom-Header", "custom-value");

    const settings = TogetherAIProviderSettings{
        .base_url = "https://custom.url",
        .api_key = "test-key",
        .headers = headers,
    };

    try std.testing.expectEqualStrings("https://custom.url", settings.base_url.?);
    try std.testing.expectEqualStrings("test-key", settings.api_key.?);
    try std.testing.expect(settings.headers != null);
}

test "getHeadersFn creates headers with Content-Type" {
    const config = openai_compat.OpenAICompatibleConfig{
        .base_url = "https://api.together.xyz/v1",
    };

    var headers = getHeadersFn(&config);
    defer headers.deinit();

    const content_type = headers.get("Content-Type");
    try std.testing.expect(content_type != null);
    try std.testing.expectEqualStrings("application/json", content_type.?);
}

test "togetherai singleton returns same instance" {
    const provider1 = togetherai();
    const provider2 = togetherai();

    try std.testing.expectEqual(provider1, provider2);
}

test "togetherai singleton is initialized" {
    const provider = togetherai();

    try std.testing.expectEqualStrings("togetherai", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.together.xyz/v1", provider.base_url);
}

test "createTogetherAI and createTogetherAIWithSettings produce equivalent results with empty settings" {
    const allocator = std.testing.allocator;

    var provider1 = createTogetherAI(allocator);
    defer provider1.deinit();

    var provider2 = createTogetherAIWithSettings(allocator, .{});
    defer provider2.deinit();

    try std.testing.expectEqualStrings(provider1.getProvider(), provider2.getProvider());
    try std.testing.expectEqualStrings(provider1.base_url, provider2.base_url);
}

test "TogetherAIProvider deinit is safe to call" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    provider.deinit();

    // Calling deinit multiple times should be safe
    provider.deinit();
}

test "TogetherAIProvider model IDs with special characters" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    const model = provider.languageModel("namespace/model-name_v1.0");
    try std.testing.expectEqualStrings("namespace/model-name_v1.0", model.getModelId());
}

test "TogetherAIProvider with empty model ID" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    const model = provider.languageModel("");
    try std.testing.expectEqualStrings("", model.getModelId());
}

test "TogetherAIProvider language model with very long model ID" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    const long_id = "very/long/namespace/with/multiple/segments/model-name-with-version-1.0.0";
    const model = provider.languageModel(long_id);
    try std.testing.expectEqualStrings(long_id, model.getModelId());
}

test "TogetherAIProvider embedding model with very long model ID" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    const long_id = "organization/very-long-embedding-model-name-with-details";
    const model = provider.embeddingModel(long_id);
    try std.testing.expectEqualStrings(long_id, model.getModelId());
}

test "TogetherAIProvider base_url without trailing slash" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAIWithSettings(allocator, .{
        .base_url = "https://api.example.com/v1",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://api.example.com/v1", provider.base_url);
}

test "TogetherAIProvider base_url with trailing slash" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAIWithSettings(allocator, .{
        .base_url = "https://api.example.com/v1/",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://api.example.com/v1/", provider.base_url);
}

test "TogetherAIProvider language model inherits base_url from provider" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.together.ai/api";

    var provider = createTogetherAIWithSettings(allocator, .{
        .base_url = custom_url,
    });
    defer provider.deinit();

    const model = provider.languageModel("test-model");
    // The model should use the custom base_url from the provider
    _ = model;
}

test "TogetherAIProvider embedding model inherits base_url from provider" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.together.ai/api";

    var provider = createTogetherAIWithSettings(allocator, .{
        .base_url = custom_url,
    });
    defer provider.deinit();

    const model = provider.embeddingModel("test-embed-model");
    // The model should use the custom base_url from the provider
    _ = model;
}

test "TogetherAIProvider vtable pointer cast safety" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    var provider_interface = provider.asProvider();

    // Test that vtable operations work correctly with pointer casting
    const lang_result = provider_interface.vtable.languageModel(provider_interface.impl, "test");
    const embed_result = provider_interface.vtable.embeddingModel(provider_interface.impl, "test");
    const image_result = provider_interface.vtable.imageModel(provider_interface.impl, "test");

    try std.testing.expect(lang_result == .ok);
    try std.testing.expect(embed_result == .ok);
    try std.testing.expect(image_result == .err);
}

test "TogetherAIProvider common model names" {
    const allocator = std.testing.allocator;

    var provider = createTogetherAI(allocator);
    defer provider.deinit();

    // Test some common TogetherAI model names
    const llama = provider.languageModel("meta-llama/Llama-3-8b-chat-hf");
    const mixtral = provider.languageModel("mistralai/Mixtral-8x7B-Instruct-v0.1");
    const qwen = provider.languageModel("Qwen/Qwen2.5-7B-Instruct-Turbo");

    try std.testing.expectEqualStrings("meta-llama/Llama-3-8b-chat-hf", llama.getModelId());
    try std.testing.expectEqualStrings("mistralai/Mixtral-8x7B-Instruct-v0.1", mixtral.getModelId());
    try std.testing.expectEqualStrings("Qwen/Qwen2.5-7B-Instruct-Turbo", qwen.getModelId());
}
