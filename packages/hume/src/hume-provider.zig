const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;

pub const HumeProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

/// Hume Speech Model (Empathic Voice Interface)
pub const HumeSpeechModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    base_url: []const u8,
    settings: HumeProviderSettings,

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        base_url: []const u8,
        settings: HumeProviderSettings,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .base_url = base_url,
            .settings = settings,
        };
    }

    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "hume.speech";
    }

    /// Build request body for speech synthesis
    pub fn buildRequestBody(
        self: *const Self,
        text: []const u8,
        options: SpeechOptions,
    ) !std.json.Value {
        var obj = std.json.ObjectMap.init(self.allocator);

        try obj.put("text", std.json.Value{ .string = text });

        if (options.voice_id) |v| {
            try obj.put("voice_id", std.json.Value{ .string = v });
        }
        if (options.instant_mode) |im| {
            try obj.put("instant_mode", std.json.Value{ .bool = im });
        }
        if (options.description) |d| {
            try obj.put("description", std.json.Value{ .string = d });
        }

        // Prosody controls (emotion/expression)
        if (options.prosody) |p| {
            var prosody_obj = std.json.ObjectMap.init(self.allocator);
            if (p.speed) |s| {
                try prosody_obj.put("speed", std.json.Value{ .float = s });
            }
            if (p.pitch) |pt| {
                try prosody_obj.put("pitch", std.json.Value{ .float = pt });
            }
            if (p.volume) |v| {
                try prosody_obj.put("volume", std.json.Value{ .float = v });
            }
            try obj.put("prosody", std.json.Value{ .object = prosody_obj });
        }

        return std.json.Value{ .object = obj };
    }
};

pub const Prosody = struct {
    speed: ?f64 = null,
    pitch: ?f64 = null,
    volume: ?f64 = null,
};

pub const SpeechOptions = struct {
    voice_id: ?[]const u8 = null,
    instant_mode: ?bool = null,
    description: ?[]const u8 = null,
    prosody: ?Prosody = null,
};

/// Hume Expression Analysis Model
pub const HumeExpressionModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    base_url: []const u8,
    settings: HumeProviderSettings,

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        base_url: []const u8,
        settings: HumeProviderSettings,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .base_url = base_url,
            .settings = settings,
        };
    }

    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "hume.expression";
    }
};

pub const HumeProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: HumeProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: HumeProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.hume.ai",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "hume";
    }

    pub fn speechModel(self: *Self, model_id: []const u8) HumeSpeechModel {
        return HumeSpeechModel.init(self.allocator, model_id, self.base_url, self.settings);
    }

    pub fn speech(self: *Self, model_id: []const u8) HumeSpeechModel {
        return self.speechModel(model_id);
    }

    pub fn expressionModel(self: *Self, model_id: []const u8) HumeExpressionModel {
        return HumeExpressionModel.init(self.allocator, model_id, self.base_url, self.settings);
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
    return std.posix.getenv("HUME_API_KEY");
}

/// Get headers for API requests. Caller owns the returned HashMap.
pub fn getHeaders(allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    try headers.put("Content-Type", "application/json");

    if (getApiKeyFromEnv()) |api_key| {
        try headers.put("X-Hume-Api-Key", api_key);
    }

    return headers;
}

pub fn createHume(allocator: std.mem.Allocator) HumeProvider {
    return HumeProvider.init(allocator, .{});
}

pub fn createHumeWithSettings(
    allocator: std.mem.Allocator,
    settings: HumeProviderSettings,
) HumeProvider {
    return HumeProvider.init(allocator, settings);
}

// ============================================================================
// Unit Tests
// ============================================================================

test "HumeProvider basic" {
    const allocator = std.testing.allocator;
    var prov = createHumeWithSettings(allocator, .{});
    defer prov.deinit();
    try std.testing.expectEqualStrings("hume", prov.getProvider());
}

test "HumeProvider default base_url" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();
    try std.testing.expectEqualStrings("https://api.hume.ai", prov.base_url);
}

test "HumeProvider custom base_url" {
    const allocator = std.testing.allocator;
    var prov = createHumeWithSettings(allocator, .{
        .base_url = "https://custom.hume.ai/v2",
    });
    defer prov.deinit();
    try std.testing.expectEqualStrings("https://custom.hume.ai/v2", prov.base_url);
}

test "HumeProvider with custom api_key" {
    const allocator = std.testing.allocator;
    var prov = createHumeWithSettings(allocator, .{
        .api_key = "test-hume-key-12345",
    });
    defer prov.deinit();
    try std.testing.expectEqualStrings("hume", prov.getProvider());
    try std.testing.expectEqualStrings("https://api.hume.ai", prov.base_url);
}

test "HumeProvider with all custom settings" {
    const allocator = std.testing.allocator;
    var prov = createHumeWithSettings(allocator, .{
        .base_url = "https://custom.hume.ai",
        .api_key = "my-key",
        .headers = null,
        .http_client = null,
    });
    defer prov.deinit();
    try std.testing.expectEqualStrings("hume", prov.getProvider());
    try std.testing.expectEqualStrings("https://custom.hume.ai", prov.base_url);
}

test "HumeProvider specification_version" {
    try std.testing.expectEqualStrings("v3", HumeProvider.specification_version);
}

test "HumeProvider deinit is safe to call multiple times" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    prov.deinit();
    prov.deinit();
}

test "HumeProvider getProvider is const" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();
    const const_prov: *const HumeProvider = &prov;
    try std.testing.expectEqualStrings("hume", const_prov.getProvider());
}

test "HumeProviderSettings default values" {
    const settings: HumeProviderSettings = .{};
    try std.testing.expect(settings.base_url == null);
    try std.testing.expect(settings.api_key == null);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}

test "HumeProviderSettings custom values" {
    const settings: HumeProviderSettings = .{
        .base_url = "https://custom.hume.ai",
        .api_key = "test-key-456",
    };
    try std.testing.expectEqualStrings("https://custom.hume.ai", settings.base_url.?);
    try std.testing.expectEqualStrings("test-key-456", settings.api_key.?);
}

// --- Speech Model Tests ---

test "HumeSpeechModel creation via provider" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();

    const model = prov.speechModel("evi-2");
    try std.testing.expectEqualStrings("evi-2", model.getModelId());
    try std.testing.expectEqualStrings("hume.speech", model.getProvider());
    try std.testing.expectEqualStrings("https://api.hume.ai", model.base_url);
}

test "HumeSpeechModel creation via speech alias" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();

    const model = prov.speech("evi-2");
    try std.testing.expectEqualStrings("evi-2", model.getModelId());
    try std.testing.expectEqualStrings("hume.speech", model.getProvider());
}

test "HumeSpeechModel preserves custom base_url" {
    const allocator = std.testing.allocator;
    var prov = createHumeWithSettings(allocator, .{
        .base_url = "https://custom.hume.ai",
    });
    defer prov.deinit();

    const model = prov.speechModel("evi-2");
    try std.testing.expectEqualStrings("https://custom.hume.ai", model.base_url);
}

test "HumeSpeechModel direct init" {
    const allocator = std.testing.allocator;
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});
    try std.testing.expectEqualStrings("evi-2", model.getModelId());
    try std.testing.expectEqualStrings("hume.speech", model.getProvider());
}

test "HumeSpeechModel buildRequestBody with text only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});

    const result = try model.buildRequestBody("Hello world", .{});

    try std.testing.expectEqualStrings("Hello world", result.object.get("text").?.string);
    // No optional fields should be present
    try std.testing.expect(result.object.get("voice_id") == null);
    try std.testing.expect(result.object.get("instant_mode") == null);
    try std.testing.expect(result.object.get("description") == null);
    try std.testing.expect(result.object.get("prosody") == null);
}

test "HumeSpeechModel buildRequestBody with voice_id" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});

    const result = try model.buildRequestBody("Say something", .{
        .voice_id = "voice-abc-123",
    });

    try std.testing.expectEqualStrings("Say something", result.object.get("text").?.string);
    try std.testing.expectEqualStrings("voice-abc-123", result.object.get("voice_id").?.string);
}

test "HumeSpeechModel buildRequestBody with instant_mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});

    const result = try model.buildRequestBody("Quick response", .{
        .instant_mode = true,
    });

    try std.testing.expectEqualStrings("Quick response", result.object.get("text").?.string);
    try std.testing.expect(result.object.get("instant_mode").?.bool == true);
}

test "HumeSpeechModel buildRequestBody with instant_mode false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});

    const result = try model.buildRequestBody("Normal response", .{
        .instant_mode = false,
    });

    try std.testing.expect(result.object.get("instant_mode").?.bool == false);
}

test "HumeSpeechModel buildRequestBody with description" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});

    const result = try model.buildRequestBody("Described speech", .{
        .description = "A warm and friendly voice",
    });

    try std.testing.expectEqualStrings("Described speech", result.object.get("text").?.string);
    try std.testing.expectEqualStrings("A warm and friendly voice", result.object.get("description").?.string);
}

test "HumeSpeechModel buildRequestBody with prosody speed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});

    const result = try model.buildRequestBody("Fast speech", .{
        .prosody = .{ .speed = 1.5 },
    });

    const prosody = result.object.get("prosody").?.object;
    try std.testing.expectEqual(@as(f64, 1.5), prosody.get("speed").?.float);
    try std.testing.expect(prosody.get("pitch") == null);
    try std.testing.expect(prosody.get("volume") == null);
}

test "HumeSpeechModel buildRequestBody with prosody pitch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});

    const result = try model.buildRequestBody("High pitch", .{
        .prosody = .{ .pitch = 2.0 },
    });

    const prosody = result.object.get("prosody").?.object;
    try std.testing.expectEqual(@as(f64, 2.0), prosody.get("pitch").?.float);
    try std.testing.expect(prosody.get("speed") == null);
    try std.testing.expect(prosody.get("volume") == null);
}

test "HumeSpeechModel buildRequestBody with prosody volume" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});

    const result = try model.buildRequestBody("Loud speech", .{
        .prosody = .{ .volume = 0.8 },
    });

    const prosody = result.object.get("prosody").?.object;
    try std.testing.expectEqual(@as(f64, 0.8), prosody.get("volume").?.float);
    try std.testing.expect(prosody.get("speed") == null);
    try std.testing.expect(prosody.get("pitch") == null);
}

test "HumeSpeechModel buildRequestBody with all prosody controls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});

    const result = try model.buildRequestBody("Full prosody", .{
        .prosody = .{
            .speed = 1.2,
            .pitch = 0.9,
            .volume = 0.7,
        },
    });

    const prosody = result.object.get("prosody").?.object;
    try std.testing.expectEqual(@as(f64, 1.2), prosody.get("speed").?.float);
    try std.testing.expectEqual(@as(f64, 0.9), prosody.get("pitch").?.float);
    try std.testing.expectEqual(@as(f64, 0.7), prosody.get("volume").?.float);
}

test "HumeSpeechModel buildRequestBody with all options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});

    const result = try model.buildRequestBody("Complete request", .{
        .voice_id = "voice-xyz",
        .instant_mode = true,
        .description = "Excited and energetic",
        .prosody = .{
            .speed = 1.1,
            .pitch = 1.3,
            .volume = 0.9,
        },
    });

    try std.testing.expectEqualStrings("Complete request", result.object.get("text").?.string);
    try std.testing.expectEqualStrings("voice-xyz", result.object.get("voice_id").?.string);
    try std.testing.expect(result.object.get("instant_mode").?.bool == true);
    try std.testing.expectEqualStrings("Excited and energetic", result.object.get("description").?.string);

    const prosody = result.object.get("prosody").?.object;
    try std.testing.expectEqual(@as(f64, 1.1), prosody.get("speed").?.float);
    try std.testing.expectEqual(@as(f64, 1.3), prosody.get("pitch").?.float);
    try std.testing.expectEqual(@as(f64, 0.9), prosody.get("volume").?.float);
}

test "HumeSpeechModel buildRequestBody with empty prosody" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});

    const result = try model.buildRequestBody("Empty prosody", .{
        .prosody = .{},
    });

    // Prosody object should exist but have no fields set
    const prosody = result.object.get("prosody").?.object;
    try std.testing.expect(prosody.get("speed") == null);
    try std.testing.expect(prosody.get("pitch") == null);
    try std.testing.expect(prosody.get("volume") == null);
}

// --- Expression Model Tests ---

test "HumeExpressionModel creation via provider" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();

    const model = prov.expressionModel("face-v1");
    try std.testing.expectEqualStrings("face-v1", model.getModelId());
    try std.testing.expectEqualStrings("hume.expression", model.getProvider());
    try std.testing.expectEqualStrings("https://api.hume.ai", model.base_url);
}

test "HumeExpressionModel preserves custom base_url" {
    const allocator = std.testing.allocator;
    var prov = createHumeWithSettings(allocator, .{
        .base_url = "https://custom.hume.ai",
    });
    defer prov.deinit();

    const model = prov.expressionModel("face-v1");
    try std.testing.expectEqualStrings("https://custom.hume.ai", model.base_url);
}

test "HumeExpressionModel direct init" {
    const allocator = std.testing.allocator;
    const model = HumeExpressionModel.init(allocator, "prosody-v1", "https://api.hume.ai", .{});
    try std.testing.expectEqualStrings("prosody-v1", model.getModelId());
    try std.testing.expectEqualStrings("hume.expression", model.getProvider());
}

// --- Prosody / SpeechOptions Default Value Tests ---

test "Prosody default values are all null" {
    const p: Prosody = .{};
    try std.testing.expect(p.speed == null);
    try std.testing.expect(p.pitch == null);
    try std.testing.expect(p.volume == null);
}

test "SpeechOptions default values are all null" {
    const opts: SpeechOptions = .{};
    try std.testing.expect(opts.voice_id == null);
    try std.testing.expect(opts.instant_mode == null);
    try std.testing.expect(opts.description == null);
    try std.testing.expect(opts.prosody == null);
}

// --- VTable / asProvider Tests ---

test "HumeProvider asProvider vtable returns failure for language model" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();

    const as_prov = prov.asProvider();
    const result = as_prov.languageModel("test-model");
    switch (result) {
        .success => return error.TestExpectedError,
        .failure => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
        .no_such_model => {},
    }
}

test "HumeProvider asProvider vtable returns failure for embedding model" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();

    const as_prov = prov.asProvider();
    const result = as_prov.embeddingModel("test-model");
    switch (result) {
        .success => return error.TestExpectedError,
        .failure => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
        .no_such_model => {},
    }
}

test "HumeProvider asProvider vtable returns failure for image model" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();

    const as_prov = prov.asProvider();
    const result = as_prov.imageModel("test-model");
    switch (result) {
        .success => return error.TestExpectedError,
        .failure => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
        .no_such_model => {},
    }
}

test "HumeProvider asProvider vtable returns failure for speech model" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();

    const as_prov = prov.asProvider();
    const result = as_prov.speechModel("test-model");
    switch (result) {
        .success => return error.TestExpectedError,
        .failure => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
        .no_such_model => {},
        .not_supported => {},
    }
}

test "HumeProvider asProvider vtable returns failure for transcription model" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();

    const as_prov = prov.asProvider();
    const result = as_prov.transcriptionModel("test-model");
    switch (result) {
        .success => return error.TestExpectedError,
        .failure => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
        .no_such_model => {},
        .not_supported => {},
    }
}

// --- Multiple model creation ---

test "HumeProvider multiple speech model creation" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();

    const model1 = prov.speechModel("evi-1");
    const model2 = prov.speechModel("evi-2");
    const model3 = prov.speech("evi-3");

    try std.testing.expectEqualStrings("evi-1", model1.getModelId());
    try std.testing.expectEqualStrings("evi-2", model2.getModelId());
    try std.testing.expectEqualStrings("evi-3", model3.getModelId());

    // All should share the same provider name
    try std.testing.expectEqualStrings("hume.speech", model1.getProvider());
    try std.testing.expectEqualStrings("hume.speech", model2.getProvider());
    try std.testing.expectEqualStrings("hume.speech", model3.getProvider());
}

test "HumeProvider multiple expression model creation" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();

    const model1 = prov.expressionModel("face-v1");
    const model2 = prov.expressionModel("prosody-v1");

    try std.testing.expectEqualStrings("face-v1", model1.getModelId());
    try std.testing.expectEqualStrings("prosody-v1", model2.getModelId());
    try std.testing.expectEqualStrings("hume.expression", model1.getProvider());
    try std.testing.expectEqualStrings("hume.expression", model2.getProvider());
}

// --- Edge case tests ---

test "HumeProvider edge case: empty model ID" {
    const allocator = std.testing.allocator;
    var prov = createHume(allocator);
    defer prov.deinit();

    const speech = prov.speechModel("");
    try std.testing.expectEqualStrings("", speech.getModelId());

    const expr = prov.expressionModel("");
    try std.testing.expectEqualStrings("", expr.getModelId());
}

test "HumeSpeechModel buildRequestBody with empty text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = HumeSpeechModel.init(allocator, "evi-2", "https://api.hume.ai", .{});

    const result = try model.buildRequestBody("", .{});

    try std.testing.expectEqualStrings("", result.object.get("text").?.string);
}

test "HumeProvider returns consistent values across instances" {
    const allocator = std.testing.allocator;
    var prov1 = createHume(allocator);
    defer prov1.deinit();
    var prov2 = createHume(allocator);
    defer prov2.deinit();

    try std.testing.expectEqualStrings(prov1.getProvider(), prov2.getProvider());
    try std.testing.expectEqualStrings(prov1.base_url, prov2.base_url);
}

test "getHeaders returns Content-Type" {
    const allocator = std.testing.allocator;
    var headers = try getHeaders(allocator);
    defer headers.deinit();

    const content_type = headers.get("Content-Type");
    try std.testing.expect(content_type != null);
    try std.testing.expectEqualStrings("application/json", content_type.?);
}
