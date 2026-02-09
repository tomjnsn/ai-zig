const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;

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
            try obj.put("width", std.json.Value{ .integer = try provider_utils.safeCast(i64, w) });
        }
        if (options.height) |h| {
            try obj.put("height", std.json.Value{ .integer = try provider_utils.safeCast(i64, h) });
        }
        if (options.seed) |s| {
            try obj.put("seed", std.json.Value{ .integer = try provider_utils.safeCast(i64, s) });
        }
        if (options.steps) |st| {
            try obj.put("steps", std.json.Value{ .integer = try provider_utils.safeCast(i64, st) });
        }
        if (options.guidance) |g| {
            try obj.put("guidance", std.json.Value{ .float = g });
        }
        if (options.safety_tolerance) |st| {
            try obj.put("safety_tolerance", std.json.Value{ .integer = try provider_utils.safeCast(i64, st) });
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

test "BlackForestLabsProvider default base_url" {
    const allocator = std.testing.allocator;
    var prov = createBlackForestLabs(allocator);
    defer prov.deinit();
    try std.testing.expectEqualStrings("https://api.bfl.ml", prov.base_url);
}

test "BlackForestLabsProvider custom base_url" {
    const allocator = std.testing.allocator;
    var prov = createBlackForestLabsWithSettings(allocator, .{
        .base_url = "https://custom.bfl.example.com",
    });
    defer prov.deinit();
    try std.testing.expectEqualStrings("https://custom.bfl.example.com", prov.base_url);
}

test "BlackForestLabsProvider specification_version" {
    try std.testing.expectEqualStrings("v3", BlackForestLabsProvider.specification_version);
}

test "BlackForestLabsProvider imageModel returns correct model" {
    const allocator = std.testing.allocator;
    var prov = createBlackForestLabs(allocator);
    defer prov.deinit();
    const model = prov.imageModel(ImageModels.flux_pro_1_1);
    try std.testing.expectEqualStrings("flux-pro-1.1", model.getModelId());
    try std.testing.expectEqualStrings("black-forest-labs.image", model.getProvider());
}

test "BlackForestLabsProvider image alias returns same as imageModel" {
    const allocator = std.testing.allocator;
    var prov = createBlackForestLabs(allocator);
    defer prov.deinit();
    const model = prov.image(ImageModels.flux_dev);
    try std.testing.expectEqualStrings("flux-dev", model.getModelId());
    try std.testing.expectEqualStrings("black-forest-labs.image", model.getProvider());
}

test "BlackForestLabsProvider imageModel inherits base_url" {
    const allocator = std.testing.allocator;
    var prov = createBlackForestLabsWithSettings(allocator, .{
        .base_url = "https://custom.bfl.example.com",
    });
    defer prov.deinit();
    const model = prov.imageModel(ImageModels.flux_schnell);
    try std.testing.expectEqualStrings("https://custom.bfl.example.com", model.base_url);
}

test "BlackForestLabsProvider vtable returns NoSuchModel for unsupported model types" {
    const allocator = std.testing.allocator;
    var prov = createBlackForestLabs(allocator);
    defer prov.deinit();
    const prov_v3 = prov.asProvider();

    // Language model not supported
    const lm = prov_v3.languageModel("some-model");
    try std.testing.expect(lm == .failure);

    // Embedding model not supported
    const em = prov_v3.embeddingModel("some-model");
    try std.testing.expect(em == .failure);

    // Image model vtable stub also returns NoSuchModel
    const im = prov_v3.imageModel("some-model");
    try std.testing.expect(im == .failure);

    // Speech model not supported
    const sm = prov_v3.speechModel("some-model");
    try std.testing.expect(sm == .failure);

    // Transcription model not supported
    const tm = prov_v3.transcriptionModel("some-model");
    try std.testing.expect(tm == .failure);
}

// -- ImageModels constants tests --

test "ImageModels constants" {
    try std.testing.expectEqualStrings("flux-pro-1.1", ImageModels.flux_pro_1_1);
    try std.testing.expectEqualStrings("flux-pro-1.1-ultra", ImageModels.flux_pro_1_1_ultra);
    try std.testing.expectEqualStrings("flux-pro", ImageModels.flux_pro);
    try std.testing.expectEqualStrings("flux-dev", ImageModels.flux_dev);
    try std.testing.expectEqualStrings("flux-schnell", ImageModels.flux_schnell);
    try std.testing.expectEqualStrings("flux-kontext-pro", ImageModels.flux_kontext_pro);
    try std.testing.expectEqualStrings("flux-kontext-max", ImageModels.flux_kontext_max);
}

// -- BlackForestLabsImageModel tests --

test "BlackForestLabsImageModel getModelId" {
    const allocator = std.testing.allocator;
    const model = BlackForestLabsImageModel.init(allocator, "flux-pro-1.1", "https://api.bfl.ml", .{});
    try std.testing.expectEqualStrings("flux-pro-1.1", model.getModelId());
}

test "BlackForestLabsImageModel getProvider" {
    const allocator = std.testing.allocator;
    const model = BlackForestLabsImageModel.init(allocator, "flux-dev", "https://api.bfl.ml", .{});
    try std.testing.expectEqualStrings("black-forest-labs.image", model.getProvider());
}

test "BlackForestLabsImageModel maxImagesPerCall returns 1" {
    const allocator = std.testing.allocator;
    const model = BlackForestLabsImageModel.init(allocator, "flux-schnell", "https://api.bfl.ml", .{});
    try std.testing.expectEqual(@as(usize, 1), model.maxImagesPerCall());
}

test "BlackForestLabsImageModel buildRequestBody prompt only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = BlackForestLabsImageModel.init(allocator, "flux-pro", "https://api.bfl.ml", .{});
    const result = try model.buildRequestBody("A beautiful sunset", .{});
    const obj = result.object;

    try std.testing.expectEqualStrings("A beautiful sunset", obj.get("prompt").?.string);
    // No optional fields should be present
    try std.testing.expect(obj.get("width") == null);
    try std.testing.expect(obj.get("height") == null);
    try std.testing.expect(obj.get("seed") == null);
    try std.testing.expect(obj.get("steps") == null);
    try std.testing.expect(obj.get("guidance") == null);
    try std.testing.expect(obj.get("safety_tolerance") == null);
    try std.testing.expect(obj.get("output_format") == null);
    try std.testing.expect(obj.get("raw") == null);
    try std.testing.expect(obj.get("aspect_ratio") == null);
}

test "BlackForestLabsImageModel buildRequestBody with width and height" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = BlackForestLabsImageModel.init(allocator, "flux-pro", "https://api.bfl.ml", .{});
    const result = try model.buildRequestBody("A cat", .{
        .width = 1024,
        .height = 768,
    });
    const obj = result.object;

    try std.testing.expectEqualStrings("A cat", obj.get("prompt").?.string);
    try std.testing.expectEqual(@as(i64, 1024), obj.get("width").?.integer);
    try std.testing.expectEqual(@as(i64, 768), obj.get("height").?.integer);
}

test "BlackForestLabsImageModel buildRequestBody with seed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = BlackForestLabsImageModel.init(allocator, "flux-dev", "https://api.bfl.ml", .{});
    const result = try model.buildRequestBody("A dog", .{
        .seed = 42,
    });
    const obj = result.object;

    try std.testing.expectEqual(@as(i64, 42), obj.get("seed").?.integer);
}

test "BlackForestLabsImageModel buildRequestBody with steps and guidance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = BlackForestLabsImageModel.init(allocator, "flux-dev", "https://api.bfl.ml", .{});
    const result = try model.buildRequestBody("A landscape", .{
        .steps = 30,
        .guidance = 7.5,
    });
    const obj = result.object;

    try std.testing.expectEqual(@as(i64, 30), obj.get("steps").?.integer);
    try std.testing.expectEqual(@as(f64, 7.5), obj.get("guidance").?.float);
}

test "BlackForestLabsImageModel buildRequestBody with safety_tolerance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = BlackForestLabsImageModel.init(allocator, "flux-pro", "https://api.bfl.ml", .{});
    const result = try model.buildRequestBody("Abstract art", .{
        .safety_tolerance = 2,
    });
    const obj = result.object;

    try std.testing.expectEqual(@as(i64, 2), obj.get("safety_tolerance").?.integer);
}

test "BlackForestLabsImageModel buildRequestBody with output_format" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = BlackForestLabsImageModel.init(allocator, "flux-pro", "https://api.bfl.ml", .{});
    const result = try model.buildRequestBody("A photo", .{
        .output_format = "png",
    });
    const obj = result.object;

    try std.testing.expectEqualStrings("png", obj.get("output_format").?.string);
}

test "BlackForestLabsImageModel buildRequestBody with raw flag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = BlackForestLabsImageModel.init(allocator, "flux-pro-1.1-ultra", "https://api.bfl.ml", .{});
    const result = try model.buildRequestBody("A raw photo", .{
        .raw = true,
    });
    const obj = result.object;

    try std.testing.expectEqual(true, obj.get("raw").?.bool);
}

test "BlackForestLabsImageModel buildRequestBody with aspect_ratio" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = BlackForestLabsImageModel.init(allocator, "flux-pro-1.1-ultra", "https://api.bfl.ml", .{});
    const result = try model.buildRequestBody("A wide photo", .{
        .aspect_ratio = "16:9",
    });
    const obj = result.object;

    try std.testing.expectEqualStrings("16:9", obj.get("aspect_ratio").?.string);
}

test "BlackForestLabsImageModel buildRequestBody with all options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const model = BlackForestLabsImageModel.init(allocator, "flux-pro-1.1", "https://api.bfl.ml", .{});
    const result = try model.buildRequestBody("A detailed scene", .{
        .width = 1920,
        .height = 1080,
        .seed = 12345,
        .steps = 50,
        .guidance = 8.0,
        .safety_tolerance = 3,
        .output_format = "jpeg",
        .raw = false,
        .aspect_ratio = "16:9",
    });
    const obj = result.object;

    try std.testing.expectEqualStrings("A detailed scene", obj.get("prompt").?.string);
    try std.testing.expectEqual(@as(i64, 1920), obj.get("width").?.integer);
    try std.testing.expectEqual(@as(i64, 1080), obj.get("height").?.integer);
    try std.testing.expectEqual(@as(i64, 12345), obj.get("seed").?.integer);
    try std.testing.expectEqual(@as(i64, 50), obj.get("steps").?.integer);
    try std.testing.expectEqual(@as(f64, 8.0), obj.get("guidance").?.float);
    try std.testing.expectEqual(@as(i64, 3), obj.get("safety_tolerance").?.integer);
    try std.testing.expectEqualStrings("jpeg", obj.get("output_format").?.string);
    try std.testing.expectEqual(false, obj.get("raw").?.bool);
    try std.testing.expectEqualStrings("16:9", obj.get("aspect_ratio").?.string);
}

// -- ImageGenerationOptions default values --

test "ImageGenerationOptions defaults to all null" {
    const opts = ImageGenerationOptions{};
    try std.testing.expect(opts.width == null);
    try std.testing.expect(opts.height == null);
    try std.testing.expect(opts.seed == null);
    try std.testing.expect(opts.steps == null);
    try std.testing.expect(opts.guidance == null);
    try std.testing.expect(opts.safety_tolerance == null);
    try std.testing.expect(opts.output_format == null);
    try std.testing.expect(opts.raw == null);
    try std.testing.expect(opts.aspect_ratio == null);
}

// -- getHeaders test (without env var) --

test "getHeaders includes Content-Type" {
    const allocator = std.testing.allocator;
    var headers = try getHeaders(allocator);
    defer headers.deinit();

    try std.testing.expectEqualStrings("application/json", headers.get("Content-Type").?);
}

// -- BlackForestLabsProviderSettings defaults --

test "BlackForestLabsProviderSettings defaults" {
    const settings = BlackForestLabsProviderSettings{};
    try std.testing.expect(settings.base_url == null);
    try std.testing.expect(settings.api_key == null);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}
