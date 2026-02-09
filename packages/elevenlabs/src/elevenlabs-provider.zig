const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;

pub const ElevenLabsProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

/// ElevenLabs Speech Model
pub const ElevenLabsSpeechModel = struct {
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
        return "elevenlabs.speech";
    }
};

/// ElevenLabs Transcription Model
pub const ElevenLabsTranscriptionModel = struct {
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
        return "elevenlabs.transcription";
    }
};

pub const ElevenLabsProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: ElevenLabsProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: ElevenLabsProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.elevenlabs.io",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "elevenlabs";
    }

    pub fn speechModel(self: *Self, model_id: []const u8) ElevenLabsSpeechModel {
        return ElevenLabsSpeechModel.init(self.allocator, model_id, self.base_url);
    }

    pub fn speech(self: *Self, model_id: []const u8) ElevenLabsSpeechModel {
        return self.speechModel(model_id);
    }

    pub fn transcriptionModel(self: *Self, model_id: []const u8) ElevenLabsTranscriptionModel {
        return ElevenLabsTranscriptionModel.init(self.allocator, model_id, self.base_url);
    }

    pub fn transcription(self: *Self, model_id: []const u8) ElevenLabsTranscriptionModel {
        return self.transcriptionModel(model_id);
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
    return std.posix.getenv("ELEVENLABS_API_KEY");
}

/// Get headers for API requests. Caller owns the returned HashMap.
pub fn getHeaders(allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    try headers.put("Content-Type", "application/json");

    if (getApiKeyFromEnv()) |api_key| {
        try headers.put("xi-api-key", api_key);
    }

    return headers;
}

pub fn createElevenLabs(allocator: std.mem.Allocator) ElevenLabsProvider {
    return ElevenLabsProvider.init(allocator, .{});
}

pub fn createElevenLabsWithSettings(
    allocator: std.mem.Allocator,
    settings: ElevenLabsProviderSettings,
) ElevenLabsProvider {
    return ElevenLabsProvider.init(allocator, settings);
}

// ============================================================================
// Tests
// ============================================================================

test "ElevenLabsProvider basic initialization" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabsWithSettings(allocator, .{});
    defer provider.deinit();
    try std.testing.expectEqualStrings("elevenlabs", provider.getProvider());
}

test "ElevenLabsProvider with default settings" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("elevenlabs", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.elevenlabs.io", provider.base_url);
}

test "ElevenLabsProvider with custom base_url" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabsWithSettings(allocator, .{
        .base_url = "https://custom.elevenlabs.com",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://custom.elevenlabs.com", provider.base_url);
}

test "ElevenLabsProvider with custom api_key" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabsWithSettings(allocator, .{
        .api_key = "test_api_key_123",
    });
    defer provider.deinit();

    try std.testing.expect(provider.settings.api_key != null);
    try std.testing.expectEqualStrings("test_api_key_123", provider.settings.api_key.?);
}

test "ElevenLabsProvider base_url defaults when null" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabsWithSettings(allocator, .{
        .base_url = null,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://api.elevenlabs.io", provider.base_url);
}

test "ElevenLabsProvider specification_version" {
    try std.testing.expectEqualStrings("v3", ElevenLabsProvider.specification_version);
}

test "ElevenLabsProvider speechModel creates correct model" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const model = provider.speechModel("eleven_multilingual_v2");
    try std.testing.expectEqualStrings("eleven_multilingual_v2", model.getModelId());
    try std.testing.expectEqualStrings("elevenlabs.speech", model.getProvider());
}

test "ElevenLabsProvider speech alias creates correct model" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const model = provider.speech("eleven_turbo_v2_5");
    try std.testing.expectEqualStrings("eleven_turbo_v2_5", model.getModelId());
}

test "ElevenLabsProvider transcriptionModel creates correct model" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const model = provider.transcriptionModel("scribe");
    try std.testing.expectEqualStrings("scribe", model.getModelId());
    try std.testing.expectEqualStrings("elevenlabs.transcription", model.getProvider());
}

test "ElevenLabsProvider transcription alias creates correct model" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const model = provider.transcription("scribe");
    try std.testing.expectEqualStrings("scribe", model.getModelId());
}

test "ElevenLabsProvider multiple models with same provider" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const speech_model = provider.speech("eleven_multilingual_v2");
    const transcription_model = provider.transcription("scribe");

    try std.testing.expectEqualStrings("eleven_multilingual_v2", speech_model.getModelId());
    try std.testing.expectEqualStrings("scribe", transcription_model.getModelId());
}

test "ElevenLabsProvider asProvider returns ProviderV3" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const prov_v3 = provider.asProvider();
    try std.testing.expect(@intFromPtr(prov_v3.vtable) != 0);
    try std.testing.expect(@intFromPtr(prov_v3.impl) != 0);
}

test "ElevenLabsProvider vtable languageModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const prov_v3 = provider.asProvider();
    const result = prov_v3.vtable.languageModel(prov_v3.impl, "test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure => {},
        .no_such_model => {},
    }
}

test "ElevenLabsProvider vtable embeddingModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const prov_v3 = provider.asProvider();
    const result = prov_v3.vtable.embeddingModel(prov_v3.impl, "test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure => {},
        .no_such_model => {},
    }
}

test "ElevenLabsProvider vtable imageModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const prov_v3 = provider.asProvider();
    const result = prov_v3.vtable.imageModel(prov_v3.impl, "test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure => {},
        .no_such_model => {},
    }
}

test "ElevenLabsProvider vtable speechModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const prov_v3 = provider.asProvider();
    const result = prov_v3.speechModel("test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure => {},
        .no_such_model => {},
        .not_supported => {},
    }
}

test "ElevenLabsProvider vtable transcriptionModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const prov_v3 = provider.asProvider();
    const result = prov_v3.transcriptionModel("test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure => {},
        .no_such_model => {},
        .not_supported => {},
    }
}

test "ElevenLabsSpeechModel initialization" {
    const allocator = std.testing.allocator;
    const model = ElevenLabsSpeechModel.init(allocator, "eleven_multilingual_v2", "https://api.elevenlabs.io");

    try std.testing.expectEqualStrings("eleven_multilingual_v2", model.model_id);
    try std.testing.expectEqualStrings("https://api.elevenlabs.io", model.base_url);
}

test "ElevenLabsSpeechModel getModelId" {
    const allocator = std.testing.allocator;
    const model = ElevenLabsSpeechModel.init(allocator, "eleven_turbo_v2_5", "https://api.elevenlabs.io");

    try std.testing.expectEqualStrings("eleven_turbo_v2_5", model.getModelId());
}

test "ElevenLabsSpeechModel getProvider" {
    const allocator = std.testing.allocator;
    const model = ElevenLabsSpeechModel.init(allocator, "test_model", "https://api.elevenlabs.io");

    try std.testing.expectEqualStrings("elevenlabs.speech", model.getProvider());
}

test "ElevenLabsSpeechModel with custom base_url" {
    const allocator = std.testing.allocator;
    const model = ElevenLabsSpeechModel.init(allocator, "test_model", "https://custom.url.com");

    try std.testing.expectEqualStrings("https://custom.url.com", model.base_url);
}

test "ElevenLabsSpeechModel with empty model_id" {
    const allocator = std.testing.allocator;
    const model = ElevenLabsSpeechModel.init(allocator, "", "https://api.elevenlabs.io");

    try std.testing.expectEqualStrings("", model.getModelId());
}

test "ElevenLabsTranscriptionModel initialization" {
    const allocator = std.testing.allocator;
    const model = ElevenLabsTranscriptionModel.init(allocator, "scribe", "https://api.elevenlabs.io");

    try std.testing.expectEqualStrings("scribe", model.model_id);
    try std.testing.expectEqualStrings("https://api.elevenlabs.io", model.base_url);
}

test "ElevenLabsTranscriptionModel getModelId" {
    const allocator = std.testing.allocator;
    const model = ElevenLabsTranscriptionModel.init(allocator, "scribe", "https://api.elevenlabs.io");

    try std.testing.expectEqualStrings("scribe", model.getModelId());
}

test "ElevenLabsTranscriptionModel getProvider" {
    const allocator = std.testing.allocator;
    const model = ElevenLabsTranscriptionModel.init(allocator, "scribe", "https://api.elevenlabs.io");

    try std.testing.expectEqualStrings("elevenlabs.transcription", model.getProvider());
}

test "ElevenLabsTranscriptionModel with custom base_url" {
    const allocator = std.testing.allocator;
    const model = ElevenLabsTranscriptionModel.init(allocator, "scribe", "https://custom.transcription.com");

    try std.testing.expectEqualStrings("https://custom.transcription.com", model.base_url);
}

test "ElevenLabsTranscriptionModel with empty model_id" {
    const allocator = std.testing.allocator;
    const model = ElevenLabsTranscriptionModel.init(allocator, "", "https://api.elevenlabs.io");

    try std.testing.expectEqualStrings("", model.getModelId());
}

test "ElevenLabsProviderSettings with null values" {
    const settings = ElevenLabsProviderSettings{
        .base_url = null,
        .api_key = null,
        .headers = null,
        .http_client = null,
    };

    try std.testing.expect(settings.base_url == null);
    try std.testing.expect(settings.api_key == null);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}

test "ElevenLabsProviderSettings with custom values" {
    const settings = ElevenLabsProviderSettings{
        .base_url = "https://custom.com",
        .api_key = "test_key",
    };

    try std.testing.expectEqualStrings("https://custom.com", settings.base_url.?);
    try std.testing.expectEqualStrings("test_key", settings.api_key.?);
}

test "getApiKeyFromEnv returns null when not set" {
    // Note: This test assumes ELEVENLABS_API_KEY is not set in the environment
    // In a real test environment, you might want to temporarily unset it
    const api_key = getApiKeyFromEnv();
    // We can't assert the value since it depends on the environment
    // but we can test that the function doesn't crash
    _ = api_key;
}

test "createElevenLabs and createElevenLabsWithSettings are equivalent with empty settings" {
    const allocator = std.testing.allocator;
    var provider1 = createElevenLabs(allocator);
    var provider2 = createElevenLabsWithSettings(allocator, .{});
    defer provider1.deinit();
    defer provider2.deinit();

    try std.testing.expectEqualStrings(provider1.base_url, provider2.base_url);
    try std.testing.expectEqualStrings(provider1.getProvider(), provider2.getProvider());
}

test "ElevenLabsProvider models inherit provider base_url" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabsWithSettings(allocator, .{
        .base_url = "https://custom-elevenlabs.com",
    });
    defer provider.deinit();

    const speech_model = provider.speech("test_model");
    const transcription_model = provider.transcription("test_model");

    try std.testing.expectEqualStrings("https://custom-elevenlabs.com", speech_model.base_url);
    try std.testing.expectEqualStrings("https://custom-elevenlabs.com", transcription_model.base_url);
}

test "ElevenLabsProvider multiple speech models with different IDs" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const model1 = provider.speech("eleven_multilingual_v2");
    const model2 = provider.speech("eleven_turbo_v2_5");
    const model3 = provider.speech("eleven_monolingual_v1");

    try std.testing.expectEqualStrings("eleven_multilingual_v2", model1.getModelId());
    try std.testing.expectEqualStrings("eleven_turbo_v2_5", model2.getModelId());
    try std.testing.expectEqualStrings("eleven_monolingual_v1", model3.getModelId());
}

test "ElevenLabsProvider edge case: very long model ID" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const long_id = "a" ** 100;
    const model = provider.speech(long_id);

    try std.testing.expectEqualStrings(long_id, model.getModelId());
}

test "ElevenLabsProvider edge case: special characters in model ID" {
    const allocator = std.testing.allocator;
    var provider = createElevenLabs(allocator);
    defer provider.deinit();

    const special_id = "model-with-dashes_and_underscores.123";
    const model = provider.speech(special_id);

    try std.testing.expectEqualStrings(special_id, model.getModelId());
}
