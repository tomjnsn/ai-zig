const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");

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
pub fn getHeaders(allocator: std.mem.Allocator) std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    headers.put("Content-Type", "application/json") catch {};

    if (getApiKeyFromEnv()) |api_key| {
        headers.put("X-Hume-Api-Key", api_key) catch {};
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

test "HumeProvider basic" {
    const allocator = std.testing.allocator;
    var prov = createHumeWithSettings(allocator, .{});
    defer prov.deinit();
    try std.testing.expectEqualStrings("hume", prov.getProvider());
}
