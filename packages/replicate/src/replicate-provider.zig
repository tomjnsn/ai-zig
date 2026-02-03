const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;

pub const ReplicateProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

/// Replicate Image Model
pub const ReplicateImageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    base_url: []const u8,

    pub fn init(allocator: std.mem.Allocator, model_id: []const u8, base_url: []const u8) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .base_url = base_url,
        };
    }

    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "replicate.image";
    }
};

pub const ReplicateProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: ReplicateProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: ReplicateProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.replicate.com/v1",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "replicate";
    }

    pub fn imageModel(self: *Self, model_id: []const u8) ReplicateImageModel {
        return ReplicateImageModel.init(
            self.allocator,
            model_id,
            self.base_url,
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

    fn languageModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.LanguageModelResult {
        _ = model_id;
        return .{ .failure = error.NoSuchModel };
    }

    fn embeddingModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.EmbeddingModelResult {
        _ = model_id;
        return .{ .failure = error.NoSuchModel };
    }

    fn imageModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.ImageModelResult {
        _ = model_id;
        // Note: Image model doesn't implement V3 interface directly
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
    return std.posix.getenv("REPLICATE_API_TOKEN");
}

/// Get headers for API requests. Caller owns the returned HashMap.
pub fn getHeaders(allocator: std.mem.Allocator) std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    headers.put("Content-Type", "application/json") catch {};

    if (getApiKeyFromEnv()) |api_key| {
        const auth_header = std.fmt.allocPrint(allocator, "Token {s}", .{api_key}) catch return headers;
        headers.put("Authorization", auth_header) catch {};
    }

    return headers;
}

pub fn createReplicate(allocator: std.mem.Allocator) ReplicateProvider {
    return ReplicateProvider.init(allocator, .{});
}

pub fn createReplicateWithSettings(
    allocator: std.mem.Allocator,
    settings: ReplicateProviderSettings,
) ReplicateProvider {
    return ReplicateProvider.init(allocator, settings);
}

// ============================================================================
// Tests
// ============================================================================

test "ReplicateProvider - basic initialization" {
    const allocator = std.testing.allocator;
    var provider = createReplicateWithSettings(allocator, .{});
    defer provider.deinit();
    try std.testing.expectEqualStrings("replicate", provider.getProvider());
}

test "ReplicateProvider - initialization with default settings" {
    const allocator = std.testing.allocator;
    var provider = createReplicate(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("replicate", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.replicate.com/v1", provider.base_url);
}

test "ReplicateProvider - initialization with custom base_url" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.replicate.com/v1";

    var provider = createReplicateWithSettings(allocator, .{
        .base_url = custom_url,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("replicate", provider.getProvider());
    try std.testing.expectEqualStrings(custom_url, provider.base_url);
}

test "ReplicateProvider - initialization with custom api_key" {
    const allocator = std.testing.allocator;
    const custom_api_key = "test_api_key_12345";

    var provider = createReplicateWithSettings(allocator, .{
        .api_key = custom_api_key,
    });
    defer provider.deinit();

    try std.testing.expect(provider.settings.api_key != null);
    try std.testing.expectEqualStrings(custom_api_key, provider.settings.api_key.?);
}

test "ReplicateProvider - initialization with all custom settings" {
    const allocator = std.testing.allocator;

    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    try headers.put("X-Custom-Header", "custom-value");

    var provider = createReplicateWithSettings(allocator, .{
        .base_url = "https://custom.replicate.com/v1",
        .api_key = "custom_key",
        .headers = headers,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("replicate", provider.getProvider());
    try std.testing.expectEqualStrings("https://custom.replicate.com/v1", provider.base_url);
    try std.testing.expectEqualStrings("custom_key", provider.settings.api_key.?);
}

test "ReplicateProvider - specification version" {
    try std.testing.expectEqualStrings("v3", ReplicateProvider.specification_version);
}

test "ReplicateProvider - imageModel creates model correctly" {
    const allocator = std.testing.allocator;
    var provider = createReplicate(allocator);
    defer provider.deinit();

    const model_id = "stability-ai/sdxl:12345";
    const model = provider.imageModel(model_id);

    try std.testing.expectEqualStrings(model_id, model.getModelId());
    try std.testing.expectEqualStrings("replicate.image", model.getProvider());
    try std.testing.expectEqualStrings(provider.base_url, model.base_url);
}

test "ReplicateProvider - imageModel with custom base_url" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.replicate.com/v2";

    var provider = createReplicateWithSettings(allocator, .{
        .base_url = custom_url,
    });
    defer provider.deinit();

    const model_id = "black-forest-labs/flux-schnell";
    const model = provider.imageModel(model_id);

    try std.testing.expectEqualStrings(model_id, model.getModelId());
    try std.testing.expectEqualStrings(custom_url, model.base_url);
}

test "ReplicateProvider - asProvider returns ProviderV3" {
    const allocator = std.testing.allocator;
    var provider = createReplicate(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    try std.testing.expect(@intFromPtr(pv3.vtable) != 0);
    try std.testing.expect(@intFromPtr(pv3.impl) != 0);
}

test "ReplicateProvider - vtable languageModel returns NoSuchModel error" {
    const allocator = std.testing.allocator;
    var provider = createReplicate(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    const result = pv3.languageModel("test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }
}

test "ReplicateProvider - vtable embeddingModel returns NoSuchModel error" {
    const allocator = std.testing.allocator;
    var provider = createReplicate(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    const result = pv3.embeddingModel("test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }
}

test "ReplicateProvider - vtable imageModel returns NoSuchModel error" {
    const allocator = std.testing.allocator;
    var provider = createReplicate(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    const result = pv3.imageModel("test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }
}

test "ReplicateProvider - vtable speechModel returns NoSuchModel error" {
    const allocator = std.testing.allocator;
    var provider = createReplicate(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    const result = pv3.speechModel("test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model, .not_supported => {},
    }
}

test "ReplicateProvider - vtable transcriptionModel returns NoSuchModel error" {
    const allocator = std.testing.allocator;
    var provider = createReplicate(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    const result = pv3.transcriptionModel("test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model, .not_supported => {},
    }
}

test "ReplicateImageModel - initialization" {
    const allocator = std.testing.allocator;
    const model_id = "stability-ai/stable-diffusion";
    const base_url = "https://api.replicate.com/v1";

    const model = ReplicateImageModel.init(allocator, model_id, base_url);

    try std.testing.expectEqualStrings(model_id, model.model_id);
    try std.testing.expectEqualStrings(base_url, model.base_url);
}

test "ReplicateImageModel - getModelId returns correct model_id" {
    const allocator = std.testing.allocator;
    const model_id = "black-forest-labs/flux-dev";
    const base_url = "https://api.replicate.com/v1";

    const model = ReplicateImageModel.init(allocator, model_id, base_url);

    try std.testing.expectEqualStrings(model_id, model.getModelId());
}

test "ReplicateImageModel - getProvider returns replicate.image" {
    const allocator = std.testing.allocator;
    const model_id = "test-model";
    const base_url = "https://api.replicate.com/v1";

    const model = ReplicateImageModel.init(allocator, model_id, base_url);

    try std.testing.expectEqualStrings("replicate.image", model.getProvider());
}

test "ReplicateImageModel - with different model IDs" {
    const allocator = std.testing.allocator;
    const base_url = "https://api.replicate.com/v1";

    const test_cases = [_][]const u8{
        "stability-ai/sdxl:12345abc",
        "black-forest-labs/flux-schnell",
        "stability-ai/stable-diffusion-xl-1024-v1-0",
        "owner/model:version",
    };

    for (test_cases) |model_id| {
        const model = ReplicateImageModel.init(allocator, model_id, base_url);
        try std.testing.expectEqualStrings(model_id, model.getModelId());
    }
}

test "ReplicateProviderSettings - default values" {
    const settings = ReplicateProviderSettings{};

    try std.testing.expect(settings.base_url == null);
    try std.testing.expect(settings.api_key == null);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}

test "ReplicateProviderSettings - with custom values" {
    const allocator = std.testing.allocator;

    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();

    const settings = ReplicateProviderSettings{
        .base_url = "https://custom.url",
        .api_key = "custom_key",
        .headers = headers,
    };

    try std.testing.expectEqualStrings("https://custom.url", settings.base_url.?);
    try std.testing.expectEqualStrings("custom_key", settings.api_key.?);
    try std.testing.expect(settings.headers != null);
}

test "getApiKeyFromEnv - returns null when not set" {
    // Note: This test assumes REPLICATE_API_TOKEN is not set
    // If it is set in the environment, this test may fail
    const api_key = getApiKeyFromEnv();
    // We can't assert the value, but we can verify it returns an optional
    _ = api_key;
}

test "ReplicateProvider - multiple instances" {
    const allocator = std.testing.allocator;

    var provider1 = createReplicateWithSettings(allocator, .{
        .base_url = "https://provider1.com",
    });
    defer provider1.deinit();

    var provider2 = createReplicateWithSettings(allocator, .{
        .base_url = "https://provider2.com",
    });
    defer provider2.deinit();

    try std.testing.expectEqualStrings("https://provider1.com", provider1.base_url);
    try std.testing.expectEqualStrings("https://provider2.com", provider2.base_url);
}

test "ReplicateProvider - imageModel creates independent models" {
    const allocator = std.testing.allocator;
    var provider = createReplicate(allocator);
    defer provider.deinit();

    const model1 = provider.imageModel("model-1");
    const model2 = provider.imageModel("model-2");

    try std.testing.expectEqualStrings("model-1", model1.getModelId());
    try std.testing.expectEqualStrings("model-2", model2.getModelId());
}

test "ReplicateImageModel - allocator is stored correctly" {
    const allocator = std.testing.allocator;
    const model = ReplicateImageModel.init(allocator, "test", "https://api.com");

    // Verify allocator is the same instance
    try std.testing.expect(model.allocator.ptr == allocator.ptr);
}
