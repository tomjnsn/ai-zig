const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;

pub const FalProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

/// Fal Image Model
pub const FalImageModel = struct {
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
        return "fal.image";
    }
};

/// Fal Speech Model
pub const FalSpeechModel = struct {
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
        return "fal.speech";
    }
};

/// Fal Transcription Model
pub const FalTranscriptionModel = struct {
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
        return "fal.transcription";
    }
};

pub const FalProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: FalProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: FalProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://fal.run",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "fal";
    }

    pub fn imageModel(self: *Self, model_id: []const u8) FalImageModel {
        return FalImageModel.init(self.allocator, model_id, self.base_url);
    }

    pub fn image(self: *Self, model_id: []const u8) FalImageModel {
        return self.imageModel(model_id);
    }

    pub fn speechModel(self: *Self, model_id: []const u8) FalSpeechModel {
        return FalSpeechModel.init(self.allocator, model_id, self.base_url);
    }

    pub fn speech(self: *Self, model_id: []const u8) FalSpeechModel {
        return self.speechModel(model_id);
    }

    pub fn transcriptionModel(self: *Self, model_id: []const u8) FalTranscriptionModel {
        return FalTranscriptionModel.init(self.allocator, model_id, self.base_url);
    }

    pub fn transcription(self: *Self, model_id: []const u8) FalTranscriptionModel {
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
    return std.posix.getenv("FAL_API_KEY") orelse std.posix.getenv("FAL_KEY");
}

/// Get headers for API requests. Caller owns the returned HashMap.
pub fn getHeaders(allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    try headers.put("Content-Type", "application/json");

    if (getApiKeyFromEnv()) |api_key| {
        const auth_header = try std.fmt.allocPrint(allocator, "Key {s}", .{api_key});
        try headers.put("Authorization", auth_header);
    }

    return headers;
}

pub fn createFal(allocator: std.mem.Allocator) FalProvider {
    return FalProvider.init(allocator, .{});
}

pub fn createFalWithSettings(
    allocator: std.mem.Allocator,
    settings: FalProviderSettings,
) FalProvider {
    return FalProvider.init(allocator, settings);
}

test "FalProvider basic" {
    const allocator = std.testing.allocator;
    var provider = createFalWithSettings(allocator, .{});
    defer provider.deinit();
    try std.testing.expectEqualStrings("fal", provider.getProvider());
}

test "FalProvider default base_url" {
    const allocator = std.testing.allocator;
    var provider = createFal(allocator);
    defer provider.deinit();
    try std.testing.expectEqualStrings("https://fal.run", provider.base_url);
}

test "FalProvider custom base_url" {
    const allocator = std.testing.allocator;
    var provider = createFalWithSettings(allocator, .{
        .base_url = "https://custom.fal.run",
    });
    defer provider.deinit();
    try std.testing.expectEqualStrings("https://custom.fal.run", provider.base_url);
}

test "FalProvider specification_version" {
    try std.testing.expectEqualStrings("v3", FalProvider.specification_version);
}

test "FalProvider createFal convenience function" {
    const allocator = std.testing.allocator;
    var provider = createFal(allocator);
    defer provider.deinit();
    try std.testing.expectEqualStrings("fal", provider.getProvider());
    try std.testing.expectEqualStrings("https://fal.run", provider.base_url);
}

// FalImageModel tests

test "FalImageModel creation and properties" {
    const allocator = std.testing.allocator;
    var provider = createFal(allocator);
    defer provider.deinit();

    const model = provider.imageModel("fal-ai/flux/dev");
    try std.testing.expectEqualStrings("fal-ai/flux/dev", model.getModelId());
    try std.testing.expectEqualStrings("fal.image", model.getProvider());
}

test "FalImageModel via image alias" {
    const allocator = std.testing.allocator;
    var provider = createFal(allocator);
    defer provider.deinit();

    const model = provider.image("fal-ai/stable-diffusion-xl");
    try std.testing.expectEqualStrings("fal-ai/stable-diffusion-xl", model.getModelId());
    try std.testing.expectEqualStrings("fal.image", model.getProvider());
}

test "FalImageModel inherits base_url from provider" {
    const allocator = std.testing.allocator;
    var provider = createFalWithSettings(allocator, .{
        .base_url = "https://custom.fal.run",
    });
    defer provider.deinit();

    const model = provider.imageModel("fal-ai/flux/dev");
    try std.testing.expectEqualStrings("https://custom.fal.run", model.base_url);
}

test "FalImageModel direct init" {
    const allocator = std.testing.allocator;
    const model = FalImageModel.init(allocator, "test-model", "https://example.com");
    try std.testing.expectEqualStrings("test-model", model.getModelId());
    try std.testing.expectEqualStrings("fal.image", model.getProvider());
    try std.testing.expectEqualStrings("https://example.com", model.base_url);
}

// FalSpeechModel tests

test "FalSpeechModel creation and properties" {
    const allocator = std.testing.allocator;
    var provider = createFal(allocator);
    defer provider.deinit();

    const model = provider.speechModel("fal-ai/tts");
    try std.testing.expectEqualStrings("fal-ai/tts", model.getModelId());
    try std.testing.expectEqualStrings("fal.speech", model.getProvider());
}

test "FalSpeechModel via speech alias" {
    const allocator = std.testing.allocator;
    var provider = createFal(allocator);
    defer provider.deinit();

    const model = provider.speech("fal-ai/tts-v2");
    try std.testing.expectEqualStrings("fal-ai/tts-v2", model.getModelId());
    try std.testing.expectEqualStrings("fal.speech", model.getProvider());
}

test "FalSpeechModel inherits base_url from provider" {
    const allocator = std.testing.allocator;
    var provider = createFalWithSettings(allocator, .{
        .base_url = "https://custom.fal.run",
    });
    defer provider.deinit();

    const model = provider.speechModel("fal-ai/tts");
    try std.testing.expectEqualStrings("https://custom.fal.run", model.base_url);
}

test "FalSpeechModel direct init" {
    const allocator = std.testing.allocator;
    const model = FalSpeechModel.init(allocator, "speech-model", "https://example.com");
    try std.testing.expectEqualStrings("speech-model", model.getModelId());
    try std.testing.expectEqualStrings("fal.speech", model.getProvider());
    try std.testing.expectEqualStrings("https://example.com", model.base_url);
}

// FalTranscriptionModel tests

test "FalTranscriptionModel creation and properties" {
    const allocator = std.testing.allocator;
    var provider = createFal(allocator);
    defer provider.deinit();

    const model = provider.transcriptionModel("fal-ai/whisper");
    try std.testing.expectEqualStrings("fal-ai/whisper", model.getModelId());
    try std.testing.expectEqualStrings("fal.transcription", model.getProvider());
}

test "FalTranscriptionModel via transcription alias" {
    const allocator = std.testing.allocator;
    var provider = createFal(allocator);
    defer provider.deinit();

    const model = provider.transcription("fal-ai/wizper");
    try std.testing.expectEqualStrings("fal-ai/wizper", model.getModelId());
    try std.testing.expectEqualStrings("fal.transcription", model.getProvider());
}

test "FalTranscriptionModel inherits base_url from provider" {
    const allocator = std.testing.allocator;
    var provider = createFalWithSettings(allocator, .{
        .base_url = "https://custom.fal.run",
    });
    defer provider.deinit();

    const model = provider.transcriptionModel("fal-ai/whisper");
    try std.testing.expectEqualStrings("https://custom.fal.run", model.base_url);
}

test "FalTranscriptionModel direct init" {
    const allocator = std.testing.allocator;
    const model = FalTranscriptionModel.init(allocator, "transcription-model", "https://example.com");
    try std.testing.expectEqualStrings("transcription-model", model.getModelId());
    try std.testing.expectEqualStrings("fal.transcription", model.getProvider());
    try std.testing.expectEqualStrings("https://example.com", model.base_url);
}

// getHeaders tests

test "getHeaders includes Content-Type" {
    const allocator = std.testing.allocator;
    var headers = try getHeaders(allocator);
    defer headers.deinit();

    try std.testing.expectEqualStrings("application/json", headers.get("Content-Type").?);
}

// asProvider vtable tests

test "FalProvider asProvider returns valid vtable" {
    const allocator = std.testing.allocator;
    var provider = createFal(allocator);
    defer provider.deinit();

    const p = provider.asProvider();
    // Language model should return failure since Fal doesn't support language models
    const lang_result = p.languageModel("some-model");
    try std.testing.expect(lang_result == .failure);

    // Embedding model should return failure
    const embed_result = p.embeddingModel("some-model");
    try std.testing.expect(embed_result == .failure);
}

// Multiple models from same provider

test "FalProvider creates independent models" {
    const allocator = std.testing.allocator;
    var provider = createFal(allocator);
    defer provider.deinit();

    const img1 = provider.imageModel("fal-ai/flux/dev");
    const img2 = provider.imageModel("fal-ai/flux/schnell");
    const speech1 = provider.speechModel("fal-ai/tts");
    const trans1 = provider.transcriptionModel("fal-ai/whisper");

    try std.testing.expectEqualStrings("fal-ai/flux/dev", img1.getModelId());
    try std.testing.expectEqualStrings("fal-ai/flux/schnell", img2.getModelId());
    try std.testing.expectEqualStrings("fal-ai/tts", speech1.getModelId());
    try std.testing.expectEqualStrings("fal-ai/whisper", trans1.getModelId());

    // Each model type has its own provider identifier
    try std.testing.expectEqualStrings("fal.image", img1.getProvider());
    try std.testing.expectEqualStrings("fal.image", img2.getProvider());
    try std.testing.expectEqualStrings("fal.speech", speech1.getProvider());
    try std.testing.expectEqualStrings("fal.transcription", trans1.getProvider());
}

// FalProviderSettings defaults

test "FalProviderSettings defaults are all null" {
    const settings = FalProviderSettings{};
    try std.testing.expect(settings.base_url == null);
    try std.testing.expect(settings.api_key == null);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}

test "FalProviderSettings with api_key" {
    const settings = FalProviderSettings{
        .api_key = "test-key-123",
    };
    try std.testing.expectEqualStrings("test-key-123", settings.api_key.?);
    try std.testing.expect(settings.base_url == null);
}
