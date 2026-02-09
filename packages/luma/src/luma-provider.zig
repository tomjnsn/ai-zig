const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;

pub const LumaProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

/// Luma Image Model (Dream Machine)
pub const LumaImageModel = struct {
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
        return "luma.image";
    }
};

pub const LumaProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: LumaProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: LumaProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.lumalabs.ai",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "luma";
    }

    pub fn imageModel(self: *Self, model_id: []const u8) LumaImageModel {
        return LumaImageModel.init(self.allocator, model_id, self.base_url);
    }

    pub fn image(self: *Self, model_id: []const u8) LumaImageModel {
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
    return std.posix.getenv("LUMA_API_KEY");
}

/// Get headers for API requests. Caller owns the returned HashMap.
pub fn getHeaders(allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    try headers.put("Content-Type", "application/json");

    if (getApiKeyFromEnv()) |api_key| {
        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
        try headers.put("Authorization", auth_header);
    }

    return headers;
}

pub fn createLuma(allocator: std.mem.Allocator) LumaProvider {
    return LumaProvider.init(allocator, .{});
}

pub fn createLumaWithSettings(
    allocator: std.mem.Allocator,
    settings: LumaProviderSettings,
) LumaProvider {
    return LumaProvider.init(allocator, settings);
}

test "LumaProvider basic" {
    const allocator = std.testing.allocator;
    var prov = createLumaWithSettings(allocator, .{});
    defer prov.deinit();
    try std.testing.expectEqualStrings("luma", prov.getProvider());
}

test "LumaProvider uses default base URL" {
    const allocator = std.testing.allocator;
    var prov = createLuma(allocator);
    defer prov.deinit();
    try std.testing.expectEqualStrings("https://api.lumalabs.ai", prov.base_url);
}

test "LumaProvider uses custom base URL" {
    const allocator = std.testing.allocator;
    var prov = createLumaWithSettings(allocator, .{
        .base_url = "https://custom.luma.test",
    });
    defer prov.deinit();
    try std.testing.expectEqualStrings("https://custom.luma.test", prov.base_url);
}

test "LumaProvider specification version" {
    try std.testing.expectEqualStrings("v3", LumaProvider.specification_version);
}

test "LumaProvider creates image model with correct model ID" {
    const allocator = std.testing.allocator;
    var prov = createLuma(allocator);
    defer prov.deinit();
    const model = prov.imageModel("photon-1");
    try std.testing.expectEqualStrings("photon-1", model.getModelId());
}

test "LumaProvider creates image model with correct provider" {
    const allocator = std.testing.allocator;
    var prov = createLuma(allocator);
    defer prov.deinit();
    const model = prov.imageModel("photon-1");
    try std.testing.expectEqualStrings("luma.image", model.getProvider());
}

test "LumaProvider image model inherits base URL" {
    const allocator = std.testing.allocator;
    var prov = createLumaWithSettings(allocator, .{
        .base_url = "https://custom.luma.test",
    });
    defer prov.deinit();
    const model = prov.imageModel("photon-1");
    try std.testing.expectEqualStrings("https://custom.luma.test", model.base_url);
}

test "LumaProvider image() is alias for imageModel()" {
    const allocator = std.testing.allocator;
    var prov = createLuma(allocator);
    defer prov.deinit();
    const model1 = prov.imageModel("photon-1");
    const model2 = prov.image("photon-1");
    try std.testing.expectEqualStrings(model1.getModelId(), model2.getModelId());
    try std.testing.expectEqualStrings(model1.getProvider(), model2.getProvider());
    try std.testing.expectEqualStrings(model1.base_url, model2.base_url);
}

test "LumaProvider createLuma is equivalent to createLumaWithSettings with defaults" {
    const allocator = std.testing.allocator;
    var prov1 = createLuma(allocator);
    defer prov1.deinit();
    var prov2 = createLumaWithSettings(allocator, .{});
    defer prov2.deinit();
    try std.testing.expectEqualStrings(prov1.base_url, prov2.base_url);
    try std.testing.expectEqualStrings(prov1.getProvider(), prov2.getProvider());
}

test "LumaImageModel init sets fields correctly" {
    const allocator = std.testing.allocator;
    const model = LumaImageModel.init(allocator, "photon-flash-1", "https://api.lumalabs.ai");
    try std.testing.expectEqualStrings("photon-flash-1", model.model_id);
    try std.testing.expectEqualStrings("https://api.lumalabs.ai", model.base_url);
    try std.testing.expectEqualStrings("luma.image", model.getProvider());
}

test "LumaProvider settings stores api_key" {
    const allocator = std.testing.allocator;
    var prov = createLumaWithSettings(allocator, .{
        .api_key = "test-key-123",
    });
    defer prov.deinit();
    try std.testing.expectEqualStrings("test-key-123", prov.settings.api_key.?);
}

test "LumaProvider settings default api_key is null" {
    const allocator = std.testing.allocator;
    var prov = createLuma(allocator);
    defer prov.deinit();
    try std.testing.expect(prov.settings.api_key == null);
}

test "LumaProvider settings default headers is null" {
    const allocator = std.testing.allocator;
    var prov = createLuma(allocator);
    defer prov.deinit();
    try std.testing.expect(prov.settings.headers == null);
}

test "LumaProvider settings default http_client is null" {
    const allocator = std.testing.allocator;
    var prov = createLuma(allocator);
    defer prov.deinit();
    try std.testing.expect(prov.settings.http_client == null);
}
