const std = @import("std");
const provider_v3 = @import("provider").provider;
const lm = @import("provider").language_model;
const provider_utils = @import("provider-utils");

const config_mod = @import("anthropic-config.zig");
const messages_model = @import("anthropic-messages-language-model.zig");

/// Anthropic Provider settings
pub const AnthropicProviderSettings = struct {
    /// Base URL for the Anthropic API calls
    base_url: ?[]const u8 = null,

    /// API key for authenticating requests
    api_key: ?[]const u8 = null,

    /// Custom headers to include in the requests
    headers: ?std.StringHashMap([]const u8) = null,

    /// Provider name (overrides the `anthropic.messages` default name)
    name: ?[]const u8 = null,

    /// HTTP client for making requests
    http_client: ?provider_utils.HttpClient = null,

    /// ID generator function
    generate_id: ?*const fn () []const u8 = null,
};

/// Anthropic Provider
pub const AnthropicProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: AnthropicProviderSettings,
    config: config_mod.AnthropicConfig,

    pub const specification_version = "v3";

    /// Create a new Anthropic provider
    pub fn init(allocator: std.mem.Allocator, settings: AnthropicProviderSettings) Self {
        const base_url = settings.base_url orelse getBaseUrlFromEnv() orelse config_mod.default_base_url;
        const provider_name = settings.name orelse "anthropic.messages";

        return .{
            .allocator = allocator,
            .settings = settings,
            .config = .{
                .provider = provider_name,
                .base_url = base_url,
                .api_key = settings.api_key,
                .headers_fn = getHeadersFn,
                .http_client = settings.http_client,
                .generate_id = settings.generate_id,
            },
        };
    }

    /// Deinitialize the provider
    pub fn deinit(self: *Self) void {
        _ = self;
        // Clean up any allocated resources
    }

    /// Get the provider name
    pub fn getProvider(self: *const Self) []const u8 {
        return self.config.provider;
    }

    // -- Language Models --

    /// Create a messages language model
    pub fn messages(self: *Self, model_id: []const u8) messages_model.AnthropicMessagesLanguageModel {
        return messages_model.AnthropicMessagesLanguageModel.init(self.allocator, model_id, self.config);
    }

    /// Create a chat language model (alias for messages)
    pub fn chat(self: *Self, model_id: []const u8) messages_model.AnthropicMessagesLanguageModel {
        return self.messages(model_id);
    }

    /// Create a language model (alias for messages)
    pub fn languageModel(self: *Self, model_id: []const u8) messages_model.AnthropicMessagesLanguageModel {
        return self.messages(model_id);
    }

    // -- ProviderV3 Interface --

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
        var model = self.messages(model_id);
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

/// Get base URL from environment
fn getBaseUrlFromEnv() ?[]const u8 {
    return std.posix.getenv("ANTHROPIC_BASE_URL");
}

/// Get API key from environment
fn getApiKeyFromEnv() ?[]const u8 {
    return std.posix.getenv("ANTHROPIC_API_KEY");
}

/// Headers function for config
fn getHeadersFn(config: *const config_mod.AnthropicConfig, allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    // Add API key header (prefer config, fall back to env var)
    const api_key = config.api_key orelse getApiKeyFromEnv();
    if (api_key) |key| {
        try headers.put("x-api-key", key);
    }

    // Add Anthropic version header
    try headers.put("anthropic-version", config_mod.anthropic_version);

    // Add content-type
    try headers.put("Content-Type", "application/json");

    return headers;
}

/// Create a new Anthropic provider with default settings
pub fn createAnthropic(allocator: std.mem.Allocator) AnthropicProvider {
    return AnthropicProvider.init(allocator, .{});
}

/// Create a new Anthropic provider with custom settings
pub fn createAnthropicWithSettings(allocator: std.mem.Allocator, settings: AnthropicProviderSettings) AnthropicProvider {
    return AnthropicProvider.init(allocator, settings);
}

test "AnthropicProvider basic" {
    const allocator = std.testing.allocator;

    var provider = createAnthropic(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("anthropic.messages", provider.getProvider());
}

test "AnthropicProvider with custom settings" {
    const allocator = std.testing.allocator;

    var provider = createAnthropicWithSettings(allocator, .{
        .base_url = "https://custom.anthropic.com/v1",
        .name = "custom-anthropic",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("custom-anthropic", provider.getProvider());
}

test "AnthropicProvider messages model" {
    const allocator = std.testing.allocator;

    var provider = createAnthropic(allocator);
    defer provider.deinit();

    const model = provider.messages("claude-sonnet-4-5");
    try std.testing.expectEqualStrings("claude-sonnet-4-5", model.getModelId());
}
