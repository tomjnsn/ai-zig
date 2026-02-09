const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");

pub const BlackForestLabsProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

/// Black Forest Labs Image Model IDs
pub const ImageModels = struct {
    pub const flux_pro_1_1 = "flux-pro-1.1";
    pub const flux_pro_1_1_ultra = "flux-pro-1.1-ultra";
    pub const flux_pro = "flux-pro";
    pub const flux_dev = "flux-dev";
    pub const flux_schnell = "flux-schnell";
    pub const flux_kontext_pro = "flux-kontext-pro";
    pub const flux_kontext_max = "flux-kontext-max";
};

/// Black Forest Labs Image Model
pub const BlackForestLabsImageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    base_url: []const u8,
    settings: BlackForestLabsProviderSettings,

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        base_url: []const u8,
        settings: BlackForestLabsProviderSettings,
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
        return "black-forest-labs.image";
    }

    pub fn maxImagesPerCall(self: *const Self) usize {
        _ = self;
        return 1; // BFL generates one image at a time
    }

    /// Build request body for image generation
    pub fn buildRequestBody(
        self: *const Self,
        prompt: []const u8,
        options: ImageGenerationOptions,
    ) !std.json.Value {
        var obj = std.json.ObjectMap.init(self.allocator);

        try obj.put("prompt", std.json.Value{ .string = prompt });

        if (options.width) |w| {
            try obj.put("width", std.json.Value{ .integer = @intCast(w) });
        }
        if (options.height) |h| {
            try obj.put("height", std.json.Value{ .integer = @intCast(h) });
        }
        if (options.seed) |s| {
            try obj.put("seed", std.json.Value{ .integer = @intCast(s) });
        }
        if (options.steps) |st| {
            try obj.put("steps", std.json.Value{ .integer = @intCast(st) });
        }
        if (options.guidance) |g| {
            try obj.put("guidance", std.json.Value{ .float = g });
        }
        if (options.safety_tolerance) |st| {
            try obj.put("safety_tolerance", std.json.Value{ .integer = @intCast(st) });
        }
        if (options.output_format) |of| {
            try obj.put("output_format", std.json.Value{ .string = of });
        }
        if (options.raw) |r| {
            try obj.put("raw", std.json.Value{ .bool = r });
        }
        if (options.aspect_ratio) |ar| {
            try obj.put("aspect_ratio", std.json.Value{ .string = ar });
        }

        return std.json.Value{ .object = obj };
    }
};

pub const ImageGenerationOptions = struct {
    width: ?u32 = null,
    height: ?u32 = null,
    seed: ?u64 = null,
    steps: ?u32 = null,
    guidance: ?f64 = null,
    safety_tolerance: ?u32 = null,
    output_format: ?[]const u8 = null,
    raw: ?bool = null,
    aspect_ratio: ?[]const u8 = null,
};

pub const BlackForestLabsProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: BlackForestLabsProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: BlackForestLabsProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.bfl.ml",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "black-forest-labs";
    }

    pub fn imageModel(self: *Self, model_id: []const u8) BlackForestLabsImageModel {
        return BlackForestLabsImageModel.init(self.allocator, model_id, self.base_url, self.settings);
    }

    pub fn image(self: *Self, model_id: []const u8) BlackForestLabsImageModel {
        return self.imageModel(model_id);
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
    return std.posix.getenv("BFL_API_KEY");
}

/// Get headers for API requests. Caller owns the returned HashMap.
pub fn getHeaders(allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    try headers.put("Content-Type", "application/json");

    if (getApiKeyFromEnv()) |api_key| {
        try headers.put("x-key", api_key);
    }

    return headers;
}

pub fn createBlackForestLabs(allocator: std.mem.Allocator) BlackForestLabsProvider {
    return BlackForestLabsProvider.init(allocator, .{});
}

pub fn createBlackForestLabsWithSettings(
    allocator: std.mem.Allocator,
    settings: BlackForestLabsProviderSettings,
) BlackForestLabsProvider {
    return BlackForestLabsProvider.init(allocator, settings);
}

test "BlackForestLabsProvider basic" {
    const allocator = std.testing.allocator;
    var prov = createBlackForestLabsWithSettings(allocator, .{});
    defer prov.deinit();
    try std.testing.expectEqualStrings("black-forest-labs", prov.getProvider());
}
