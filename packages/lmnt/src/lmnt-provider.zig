const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");

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
