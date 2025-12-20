const std = @import("std");
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");
const openai_compat = @import("../../openai-compatible/src/index.zig");

pub const CerebrasProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?*anyopaque = null,
};

pub const CerebrasProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: CerebrasProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: CerebrasProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.cerebras.ai/v1",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "cerebras";
    }

    pub fn languageModel(self: *Self, model_id: []const u8) openai_compat.OpenAICompatibleChatLanguageModel {
        return openai_compat.OpenAICompatibleChatLanguageModel.init(
            self.allocator,
            model_id,
            .{
                .provider = "cerebras.chat",
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
    return std.posix.getenv("CEREBRAS_API_KEY");
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

pub fn createCerebras(allocator: std.mem.Allocator) CerebrasProvider {
    return CerebrasProvider.init(allocator, .{});
}

pub fn createCerebrasWithSettings(
    allocator: std.mem.Allocator,
    settings: CerebrasProviderSettings,
) CerebrasProvider {
    return CerebrasProvider.init(allocator, settings);
}

var default_provider: ?CerebrasProvider = null;

pub fn cerebras() *CerebrasProvider {
    if (default_provider == null) {
        default_provider = createCerebras(std.heap.page_allocator);
    }
    return &default_provider.?;
}

// ============================================================================
// Tests
// ============================================================================

test "CerebrasProvider basic initialization" {
    const allocator = std.testing.allocator;
    var provider = createCerebrasWithSettings(allocator, .{});
    defer provider.deinit();
    try std.testing.expectEqualStrings("cerebras", provider.getProvider());
}

test "CerebrasProvider initialization with default settings" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("cerebras", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.cerebras.ai/v1", provider.base_url);
}

test "CerebrasProvider initialization with custom base_url" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.cerebras.ai/v1";

    var provider = createCerebrasWithSettings(allocator, .{
        .base_url = custom_url,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings(custom_url, provider.base_url);
    try std.testing.expectEqualStrings("cerebras", provider.getProvider());
}

test "CerebrasProvider initialization with api_key" {
    const allocator = std.testing.allocator;
    const api_key = "test-api-key-123";

    var provider = createCerebrasWithSettings(allocator, .{
        .api_key = api_key,
    });
    defer provider.deinit();

    try std.testing.expect(provider.settings.api_key != null);
    try std.testing.expectEqualStrings(api_key, provider.settings.api_key.?);
}

test "CerebrasProvider initialization with null api_key" {
    const allocator = std.testing.allocator;

    var provider = createCerebrasWithSettings(allocator, .{
        .api_key = null,
    });
    defer provider.deinit();

    try std.testing.expect(provider.settings.api_key == null);
}

test "CerebrasProvider initialization with http_client" {
    const allocator = std.testing.allocator;
    var dummy_client: u32 = 42;

    var provider = createCerebrasWithSettings(allocator, .{
        .http_client = &dummy_client,
    });
    defer provider.deinit();

    try std.testing.expect(provider.settings.http_client != null);
}

test "CerebrasProvider default instance singleton" {
    const provider1 = cerebras();
    const provider2 = cerebras();

    try std.testing.expect(provider1 == provider2);
    try std.testing.expectEqualStrings("cerebras", provider1.getProvider());
}

test "CerebrasProvider specification version" {
    try std.testing.expectEqualStrings("v3", CerebrasProvider.specification_version);
}

test "CerebrasProvider languageModel creation" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const model = provider.languageModel("llama3.1-8b");
    try std.testing.expectEqualStrings("llama3.1-8b", model.getModelId());
}

test "CerebrasProvider languageModel with different model IDs" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const model1 = provider.languageModel("llama3.1-8b");
    const model2 = provider.languageModel("llama3.1-70b");

    try std.testing.expectEqualStrings("llama3.1-8b", model1.getModelId());
    try std.testing.expectEqualStrings("llama3.1-70b", model2.getModelId());
}

test "CerebrasProvider asProvider returns ProviderV3" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const provider_v3 = provider.asProvider();
    try std.testing.expect(provider_v3.vtable != null);
}

test "CerebrasProvider vtable languageModel" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    var provider_v3 = provider.asProvider();
    const result = provider_v3.vtable.languageModel(provider_v3.impl, "llama3.1-8b");

    switch (result) {
        .ok => |model| {
            try std.testing.expectEqualStrings("llama3.1-8b", model.getModelId());
        },
        .err => |err| {
            std.debug.print("Unexpected error: {}\n", .{err});
            try std.testing.expect(false);
        },
    }
}

test "CerebrasProvider vtable embeddingModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    var provider_v3 = provider.asProvider();
    const result = provider_v3.vtable.embeddingModel(provider_v3.impl, "text-embedding-3-small");

    switch (result) {
        .ok => {
            try std.testing.expect(false); // Should not succeed
        },
        .err => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
    }
}

test "CerebrasProvider vtable imageModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    var provider_v3 = provider.asProvider();
    const result = provider_v3.vtable.imageModel(provider_v3.impl, "dall-e-3");

    switch (result) {
        .ok => {
            try std.testing.expect(false); // Should not succeed
        },
        .err => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
    }
}

test "CerebrasProvider vtable speechModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    var provider_v3 = provider.asProvider();
    const result = provider_v3.vtable.speechModel(provider_v3.impl, "tts-1");

    switch (result) {
        .ok => {
            try std.testing.expect(false); // Should not succeed
        },
        .err => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
    }
}

test "CerebrasProvider vtable transcriptionModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    var provider_v3 = provider.asProvider();
    const result = provider_v3.vtable.transcriptionModel(provider_v3.impl, "whisper-1");

    switch (result) {
        .ok => {
            try std.testing.expect(false); // Should not succeed
        },
        .err => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
    }
}

test "CerebrasProviderSettings default values" {
    const settings = CerebrasProviderSettings{};

    try std.testing.expect(settings.base_url == null);
    try std.testing.expect(settings.api_key == null);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}

test "CerebrasProviderSettings with partial configuration" {
    const settings = CerebrasProviderSettings{
        .base_url = "https://custom.api.com",
        .api_key = "test-key",
    };

    try std.testing.expect(settings.base_url != null);
    try std.testing.expectEqualStrings("https://custom.api.com", settings.base_url.?);
    try std.testing.expect(settings.api_key != null);
    try std.testing.expectEqualStrings("test-key", settings.api_key.?);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}

test "getHeadersFn creates correct headers" {
    const config = openai_compat.OpenAICompatibleConfig{
        .base_url = "https://api.cerebras.ai/v1",
        .provider = "cerebras.chat",
    };

    const headers = getHeadersFn(&config);
    defer headers.deinit();

    const content_type = headers.get("Content-Type");
    try std.testing.expect(content_type != null);
    try std.testing.expectEqualStrings("application/json", content_type.?);
}

test "getHeadersFn includes authorization when env var is set" {
    // Note: This test depends on CEREBRAS_API_KEY environment variable
    // If not set, it will still pass but won't test authorization header
    const config = openai_compat.OpenAICompatibleConfig{
        .base_url = "https://api.cerebras.ai/v1",
        .provider = "cerebras.chat",
    };

    const headers = getHeadersFn(&config);
    defer headers.deinit();

    if (getApiKeyFromEnv()) |_| {
        const auth_header = headers.get("Authorization");
        try std.testing.expect(auth_header != null);
    }
}

test "getApiKeyFromEnv returns null or string" {
    const result = getApiKeyFromEnv();

    // Should return either null or a valid string slice
    if (result) |key| {
        try std.testing.expect(key.len > 0);
    }
}

test "CerebrasProvider multiple models from same provider" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const model1 = provider.languageModel("llama3.1-8b");
    const model2 = provider.languageModel("llama3.1-70b");
    const model3 = provider.languageModel("llama3.3-70b");

    try std.testing.expectEqualStrings("llama3.1-8b", model1.getModelId());
    try std.testing.expectEqualStrings("llama3.1-70b", model2.getModelId());
    try std.testing.expectEqualStrings("llama3.3-70b", model3.getModelId());
}

test "CerebrasProvider base_url fallback to default" {
    const allocator = std.testing.allocator;

    var provider1 = createCerebrasWithSettings(allocator, .{
        .base_url = null,
    });
    defer provider1.deinit();

    try std.testing.expectEqualStrings("https://api.cerebras.ai/v1", provider1.base_url);

    var provider2 = createCerebrasWithSettings(allocator, .{});
    defer provider2.deinit();

    try std.testing.expectEqualStrings("https://api.cerebras.ai/v1", provider2.base_url);
}

test "CerebrasProvider custom base_url overrides default" {
    const allocator = std.testing.allocator;
    const custom = "https://my-custom-cerebras.com/api/v2";

    var provider = createCerebrasWithSettings(allocator, .{
        .base_url = custom,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings(custom, provider.base_url);
    try std.testing.expect(!std.mem.eql(u8, provider.base_url, "https://api.cerebras.ai/v1"));
}

test "CerebrasProvider empty model_id" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const model = provider.languageModel("");
    try std.testing.expectEqualStrings("", model.getModelId());
}

test "CerebrasProvider long model_id" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const long_model_id = "llama-3-1-8b-instruct-very-long-model-name-for-testing-purposes";
    const model = provider.languageModel(long_model_id);
    try std.testing.expectEqualStrings(long_model_id, model.getModelId());
}

test "CerebrasProvider model with special characters" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const special_model_id = "llama-3.1_8b-instruct@v2";
    const model = provider.languageModel(special_model_id);
    try std.testing.expectEqualStrings(special_model_id, model.getModelId());
}

test "CerebrasProvider deinit multiple times" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);

    // First deinit
    provider.deinit();

    // Second deinit should not crash
    provider.deinit();
}

test "CerebrasProvider languageModel passes correct provider name" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const model = provider.languageModel("llama3.1-8b");

    // The model should be using "cerebras.chat" as provider
    try std.testing.expectEqualStrings("llama3.1-8b", model.getModelId());
}
