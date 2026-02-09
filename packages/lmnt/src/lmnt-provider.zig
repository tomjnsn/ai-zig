const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;

pub const LmntProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

/// LMNT Speech Model IDs
pub const SpeechModels = struct {
    pub const aurora = "aurora";
    pub const blizzard = "blizzard";
};

/// LMNT Speech Model
pub const LmntSpeechModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    base_url: []const u8,
    settings: LmntProviderSettings,

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        base_url: []const u8,
        settings: LmntProviderSettings,
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
        return "lmnt.speech";
    }

    /// Build request body for speech synthesis
    pub fn buildRequestBody(
        self: *const Self,
        text: []const u8,
        options: SpeechOptions,
    ) !std.json.Value {
        var obj = std.json.ObjectMap.init(self.allocator);

        try obj.put("text", std.json.Value{ .string = text });
        try obj.put("voice", std.json.Value{ .string = options.voice orelse "lily" });

        if (options.speed) |s| {
            try obj.put("speed", std.json.Value{ .float = s });
        }
        if (options.format) |f| {
            try obj.put("format", std.json.Value{ .string = f });
        }
        if (options.sample_rate) |sr| {
            try obj.put("sample_rate", std.json.Value{ .integer = try provider_utils.safeCast(i64, sr) });
        }
        if (options.length) |l| {
            try obj.put("length", std.json.Value{ .float = l });
        }
        if (options.return_durations) |rd| {
            try obj.put("return_durations", std.json.Value{ .bool = rd });
        }

        return std.json.Value{ .object = obj };
    }
};

pub const SpeechOptions = struct {
    voice: ?[]const u8 = null,
    speed: ?f64 = null,
    format: ?[]const u8 = null, // "mp3", "wav", "aac"
    sample_rate: ?u32 = null,
    length: ?f64 = null,
    return_durations: ?bool = null,
};

pub const LmntProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: LmntProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: LmntProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.lmnt.com",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "lmnt";
    }

    pub fn speechModel(self: *Self, model_id: []const u8) LmntSpeechModel {
        return LmntSpeechModel.init(self.allocator, model_id, self.base_url, self.settings);
    }

    pub fn speech(self: *Self, model_id: []const u8) LmntSpeechModel {
        return self.speechModel(model_id);
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
    return std.posix.getenv("LMNT_API_KEY");
}

/// Get headers for API requests. Caller owns the returned HashMap.
pub fn getHeaders(allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    try headers.put("Content-Type", "application/json");

    if (getApiKeyFromEnv()) |api_key| {
        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
        try headers.put("X-API-Key", auth_header);
    }

    return headers;
}

pub fn createLmnt(allocator: std.mem.Allocator) LmntProvider {
    return LmntProvider.init(allocator, .{});
}

pub fn createLmntWithSettings(
    allocator: std.mem.Allocator,
    settings: LmntProviderSettings,
) LmntProvider {
    return LmntProvider.init(allocator, settings);
}

test "LmntProvider basic" {
    const allocator = std.testing.allocator;
    var prov = createLmntWithSettings(allocator, .{});
    defer prov.deinit();
    try std.testing.expectEqualStrings("lmnt", prov.getProvider());
}

test "LmntProvider uses default base URL" {
    const allocator = std.testing.allocator;
    var prov = createLmnt(allocator);
    defer prov.deinit();
    try std.testing.expectEqualStrings("https://api.lmnt.com", prov.base_url);
}

test "LmntProvider uses custom base URL" {
    const allocator = std.testing.allocator;
    var prov = createLmntWithSettings(allocator, .{
        .base_url = "https://custom.lmnt.test",
    });
    defer prov.deinit();
    try std.testing.expectEqualStrings("https://custom.lmnt.test", prov.base_url);
}

test "LmntProvider specification version" {
    try std.testing.expectEqualStrings("v3", LmntProvider.specification_version);
}

test "LmntProvider creates speech model with correct model ID" {
    const allocator = std.testing.allocator;
    var prov = createLmnt(allocator);
    defer prov.deinit();
    const model = prov.speechModel("aurora");
    try std.testing.expectEqualStrings("aurora", model.getModelId());
}

test "LmntProvider creates speech model with correct provider" {
    const allocator = std.testing.allocator;
    var prov = createLmnt(allocator);
    defer prov.deinit();
    const model = prov.speechModel("aurora");
    try std.testing.expectEqualStrings("lmnt.speech", model.getProvider());
}

test "LmntProvider speech model inherits base URL" {
    const allocator = std.testing.allocator;
    var prov = createLmntWithSettings(allocator, .{
        .base_url = "https://custom.lmnt.test",
    });
    defer prov.deinit();
    const model = prov.speechModel("aurora");
    try std.testing.expectEqualStrings("https://custom.lmnt.test", model.base_url);
}

test "LmntProvider speech() is alias for speechModel()" {
    const allocator = std.testing.allocator;
    var prov = createLmnt(allocator);
    defer prov.deinit();
    const model1 = prov.speechModel("aurora");
    const model2 = prov.speech("aurora");
    try std.testing.expectEqualStrings(model1.getModelId(), model2.getModelId());
    try std.testing.expectEqualStrings(model1.getProvider(), model2.getProvider());
    try std.testing.expectEqualStrings(model1.base_url, model2.base_url);
}

test "LmntProvider createLmnt is equivalent to createLmntWithSettings with defaults" {
    const allocator = std.testing.allocator;
    var prov1 = createLmnt(allocator);
    defer prov1.deinit();
    var prov2 = createLmntWithSettings(allocator, .{});
    defer prov2.deinit();
    try std.testing.expectEqualStrings(prov1.base_url, prov2.base_url);
    try std.testing.expectEqualStrings(prov1.getProvider(), prov2.getProvider());
}

test "LmntProvider settings stores api_key" {
    const allocator = std.testing.allocator;
    var prov = createLmntWithSettings(allocator, .{
        .api_key = "test-key-123",
    });
    defer prov.deinit();
    try std.testing.expectEqualStrings("test-key-123", prov.settings.api_key.?);
}

test "LmntProvider settings default api_key is null" {
    const allocator = std.testing.allocator;
    var prov = createLmnt(allocator);
    defer prov.deinit();
    try std.testing.expect(prov.settings.api_key == null);
}

test "LmntProvider settings default headers is null" {
    const allocator = std.testing.allocator;
    var prov = createLmnt(allocator);
    defer prov.deinit();
    try std.testing.expect(prov.settings.headers == null);
}

test "LmntProvider settings default http_client is null" {
    const allocator = std.testing.allocator;
    var prov = createLmnt(allocator);
    defer prov.deinit();
    try std.testing.expect(prov.settings.http_client == null);
}

test "SpeechModels constants" {
    try std.testing.expectEqualStrings("aurora", SpeechModels.aurora);
    try std.testing.expectEqualStrings("blizzard", SpeechModels.blizzard);
}

test "LmntSpeechModel buildRequestBody with defaults" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var prov = createLmnt(allocator);
    defer prov.deinit();
    const model = prov.speechModel("aurora");
    const body = try model.buildRequestBody("Hello world", .{});
    const obj = body.object;
    try std.testing.expectEqualStrings("Hello world", obj.get("text").?.string);
    try std.testing.expectEqualStrings("lily", obj.get("voice").?.string);
    // optional fields should not be present
    try std.testing.expect(obj.get("speed") == null);
    try std.testing.expect(obj.get("format") == null);
    try std.testing.expect(obj.get("sample_rate") == null);
    try std.testing.expect(obj.get("length") == null);
    try std.testing.expect(obj.get("return_durations") == null);
}

test "LmntSpeechModel buildRequestBody with custom voice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var prov = createLmnt(allocator);
    defer prov.deinit();
    const model = prov.speechModel("aurora");
    const body = try model.buildRequestBody("Test text", .{
        .voice = "morgan",
    });
    const obj = body.object;
    try std.testing.expectEqualStrings("morgan", obj.get("voice").?.string);
}

test "LmntSpeechModel buildRequestBody with all options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var prov = createLmnt(allocator);
    defer prov.deinit();
    const model = prov.speechModel("aurora");
    const body = try model.buildRequestBody("Full options test", .{
        .voice = "cove",
        .speed = 1.5,
        .format = "mp3",
        .sample_rate = 24000,
        .length = 10.0,
        .return_durations = true,
    });
    const obj = body.object;
    try std.testing.expectEqualStrings("Full options test", obj.get("text").?.string);
    try std.testing.expectEqualStrings("cove", obj.get("voice").?.string);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), obj.get("speed").?.float, 0.001);
    try std.testing.expectEqualStrings("mp3", obj.get("format").?.string);
    try std.testing.expectEqual(@as(i64, 24000), obj.get("sample_rate").?.integer);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), obj.get("length").?.float, 0.001);
    try std.testing.expectEqual(true, obj.get("return_durations").?.bool);
}

test "LmntSpeechModel buildRequestBody with speed only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var prov = createLmnt(allocator);
    defer prov.deinit();
    const model = prov.speechModel("blizzard");
    const body = try model.buildRequestBody("Speed test", .{
        .speed = 0.8,
    });
    const obj = body.object;
    try std.testing.expectEqualStrings("Speed test", obj.get("text").?.string);
    try std.testing.expectEqualStrings("lily", obj.get("voice").?.string);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8), obj.get("speed").?.float, 0.001);
    try std.testing.expect(obj.get("format") == null);
}

test "LmntSpeechModel buildRequestBody with format wav" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var prov = createLmnt(allocator);
    defer prov.deinit();
    const model = prov.speechModel("aurora");
    const body = try model.buildRequestBody("Wav test", .{
        .format = "wav",
    });
    try std.testing.expectEqualStrings("wav", body.object.get("format").?.string);
}

test "LmntSpeechModel buildRequestBody with return_durations false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var prov = createLmnt(allocator);
    defer prov.deinit();
    const model = prov.speechModel("aurora");
    const body = try model.buildRequestBody("Duration test", .{
        .return_durations = false,
    });
    try std.testing.expectEqual(false, body.object.get("return_durations").?.bool);
}

test "LmntSpeechModel init sets fields correctly" {
    const allocator = std.testing.allocator;
    const model = LmntSpeechModel.init(allocator, "blizzard", "https://api.lmnt.com", .{});
    try std.testing.expectEqualStrings("blizzard", model.model_id);
    try std.testing.expectEqualStrings("https://api.lmnt.com", model.base_url);
    try std.testing.expectEqualStrings("lmnt.speech", model.getProvider());
}

test "SpeechOptions defaults are all null" {
    const opts = SpeechOptions{};
    try std.testing.expect(opts.voice == null);
    try std.testing.expect(opts.speed == null);
    try std.testing.expect(opts.format == null);
    try std.testing.expect(opts.sample_rate == null);
    try std.testing.expect(opts.length == null);
    try std.testing.expect(opts.return_durations == null);
}
