const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");

const config_mod = @import("deepseek-config.zig");
const chat_model = @import("deepseek-chat-language-model.zig");

/// DeepSeek Provider settings
pub const DeepSeekProviderSettings = struct {
    /// Base URL for API calls
    base_url: ?[]const u8 = null,

    /// API key
    api_key: ?[]const u8 = null,

    /// Custom headers
    headers: ?std.StringHashMap([]const u8) = null,

    /// HTTP client
    http_client: ?provider_utils.HttpClient = null,
};

/// DeepSeek Provider
pub const DeepSeekProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: DeepSeekProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    /// Create a new DeepSeek provider
    pub fn init(allocator: std.mem.Allocator, settings: DeepSeekProviderSettings) Self {
        const base_url = settings.base_url orelse "https://api.deepseek.com";

        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = base_url,
        };
    }

    /// Deinitialize the provider
    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Get the provider name
    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "deepseek";
    }

    /// Create a language model
    pub fn languageModel(self: *Self, model_id: []const u8) chat_model.DeepSeekChatLanguageModel {
        return chat_model.DeepSeekChatLanguageModel.init(
            self.allocator,
            model_id,
            self.buildConfig("deepseek.chat"),
        );
    }

    /// Create a language model (alias)
    pub fn chat(self: *Self, model_id: []const u8) chat_model.DeepSeekChatLanguageModel {
        return self.languageModel(model_id);
    }

    /// Build config for models
    fn buildConfig(self: *Self, provider_name: []const u8) config_mod.DeepSeekConfig {
        return .{
            .provider = provider_name,
            .base_url = self.base_url,
            .headers_fn = getHeadersFn,
            .http_client = self.settings.http_client,
        };
    }

    /// Convert to ProviderV3 interface
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

    fn languageModelVtable(impl: *anyopaque, model_id: []const u8) provider_v3.LanguageModelResult {
        const self: *Self = @ptrCast(@alignCast(impl));
        var model = self.languageModel(model_id);
        return .{ .success = model.asLanguageModel() };
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
    return std.posix.getenv("DEEPSEEK_API_KEY");
}

/// Caller owns the returned HashMap and must call deinit() when done.
fn getHeadersFn(config: *const config_mod.DeepSeekConfig, allocator: std.mem.Allocator) std.StringHashMap([]const u8) {
    _ = config;
    var headers = std.StringHashMap([]const u8).init(allocator);

    headers.put("Content-Type", "application/json") catch {};

    if (getApiKeyFromEnv()) |api_key| {
        const auth_header = std.fmt.allocPrint(
            allocator,
            "Bearer {s}",
            .{api_key},
        ) catch return headers;
        headers.put("Authorization", auth_header) catch {};
    }

    return headers;
}

pub fn createDeepSeek(allocator: std.mem.Allocator) DeepSeekProvider {
    return DeepSeekProvider.init(allocator, .{});
}

pub fn createDeepSeekWithSettings(
    allocator: std.mem.Allocator,
    settings: DeepSeekProviderSettings,
) DeepSeekProvider {
    return DeepSeekProvider.init(allocator, settings);
}


test "DeepSeekProvider basic" {
    const allocator = std.testing.allocator;

    var provider = createDeepSeekWithSettings(allocator, .{});
    defer provider.deinit();

    try std.testing.expectEqualStrings("deepseek", provider.getProvider());
}

test "DeepSeekProvider language model" {
    const allocator = std.testing.allocator;

    var provider = createDeepSeekWithSettings(allocator, .{});
    defer provider.deinit();

    const model = provider.languageModel("deepseek-chat");
    try std.testing.expectEqualStrings("deepseek-chat", model.getModelId());
}
