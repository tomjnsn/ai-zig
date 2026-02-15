const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;
const openai_compat = @import("openai-compatible");

pub const HuggingFaceProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

pub const HuggingFaceProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: HuggingFaceProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: HuggingFaceProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api-inference.huggingface.co",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "huggingface";
    }

    pub fn languageModel(self: *Self, model_id: []const u8) openai_compat.OpenAICompatibleChatLanguageModel {
        return openai_compat.OpenAICompatibleChatLanguageModel.init(
            self.allocator,
            model_id,
            .{
                .provider = "huggingface.chat",
                .base_url = self.base_url,
                .headers_fn = getHeadersFn,
                .http_client = self.settings.http_client,
            },
        );
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
    return std.posix.getenv("HUGGINGFACE_API_KEY");
}

/// Caller owns the returned HashMap and must call deinit() when done.
fn getHeadersFn(config: *const openai_compat.OpenAICompatibleConfig, allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    _ = config;
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();
    try headers.put("Content-Type", "application/json");

    if (getApiKeyFromEnv()) |api_key| {
        const auth_header = try std.fmt.allocPrint(
            allocator,
            "Bearer {s}",
            .{api_key},
        );
        try headers.put("Authorization", auth_header);
    }

    return headers;
}

pub fn createHuggingFace(allocator: std.mem.Allocator) HuggingFaceProvider {
    return HuggingFaceProvider.init(allocator, .{});
}

pub fn createHuggingFaceWithSettings(
    allocator: std.mem.Allocator,
    settings: HuggingFaceProviderSettings,
) HuggingFaceProvider {
    return HuggingFaceProvider.init(allocator, settings);
}


test "HuggingFaceProvider basic initialization" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("huggingface", provider.getProvider());
    try std.testing.expectEqualStrings("https://api-inference.huggingface.co", provider.base_url);
}

test "HuggingFaceProvider with empty settings" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFaceWithSettings(allocator, .{});
    defer provider.deinit();

    try std.testing.expectEqualStrings("huggingface", provider.getProvider());
    try std.testing.expectEqualStrings("https://api-inference.huggingface.co", provider.base_url);
}

test "HuggingFaceProvider with custom base_url" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFaceWithSettings(allocator, .{
        .base_url = "https://custom.hf-endpoint.com",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://custom.hf-endpoint.com", provider.base_url);
}

test "HuggingFaceProvider with custom api_key" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFaceWithSettings(allocator, .{
        .api_key = "test-api-key-123",
    });
    defer provider.deinit();

    try std.testing.expect(provider.settings.api_key != null);
    try std.testing.expectEqualStrings("test-api-key-123", provider.settings.api_key.?);
}

test "HuggingFaceProvider specification version" {
    try std.testing.expectEqualStrings("v3", HuggingFaceProvider.specification_version);
}

test "HuggingFaceProvider languageModel creation" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);
    defer provider.deinit();

    const model = provider.languageModel("meta-llama/Meta-Llama-3-70B-Instruct");
    try std.testing.expectEqualStrings("meta-llama/Meta-Llama-3-70B-Instruct", model.getModelId());
}

test "HuggingFaceProvider languageModel with different models" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);
    defer provider.deinit();

    const models = [_][]const u8{
        "mistralai/Mistral-7B-Instruct-v0.2",
        "meta-llama/Llama-2-7b-chat-hf",
        "tiiuae/falcon-7b-instruct",
    };

    for (models) |model_id| {
        const model = provider.languageModel(model_id);
        try std.testing.expectEqualStrings(model_id, model.getModelId());
    }
}

test "HuggingFaceProvider asProvider vtable" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);
    defer provider.deinit();

    const provider_wrapper = provider.asProvider();
    try std.testing.expect(@intFromPtr(provider_wrapper.vtable.languageModel) != 0);
    try std.testing.expect(@intFromPtr(provider_wrapper.vtable.embeddingModel) != 0);
    try std.testing.expect(@intFromPtr(provider_wrapper.vtable.imageModel) != 0);
    // speechModel and transcriptionModel are optional
}

test "HuggingFaceProvider languageModelVtable returns ok" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);
    defer provider.deinit();

    const provider_impl: *anyopaque = &provider;
    const result = HuggingFaceProvider.languageModelVtable(provider_impl, "test-model");

    try std.testing.expect(result == .success);
}

test "HuggingFaceProvider embeddingModelVtable returns error" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);
    defer provider.deinit();

    const provider_impl: *anyopaque = &provider;
    const result = HuggingFaceProvider.embeddingModelVtable(provider_impl, "test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }
}

test "HuggingFaceProvider imageModelVtable returns error" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);
    defer provider.deinit();

    const provider_impl: *anyopaque = &provider;
    const result = HuggingFaceProvider.imageModelVtable(provider_impl, "test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }
}

test "HuggingFaceProvider speechModelVtable returns error" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);
    defer provider.deinit();

    const prov = provider.asProvider();
    const result = prov.speechModel("test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model, .not_supported => {},
    }
}

test "HuggingFaceProvider transcriptionModelVtable returns error" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);
    defer provider.deinit();

    const prov = provider.asProvider();
    const result = prov.transcriptionModel("test-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model, .not_supported => {},
    }
}

test "getHeadersFn creates Content-Type header" {
    const config = openai_compat.OpenAICompatibleConfig{
        .base_url = "https://test.com",
    };

    var headers = try getHeadersFn(&config, std.testing.allocator);
    defer headers.deinit();

    const content_type = headers.get("Content-Type");
    try std.testing.expect(content_type != null);
    try std.testing.expectEqualStrings("application/json", content_type.?);
}

test "getHeadersFn without API key in environment" {
    const config = openai_compat.OpenAICompatibleConfig{
        .base_url = "https://test.com",
    };

    var headers = try getHeadersFn(&config, std.testing.allocator);
    defer headers.deinit();

    // Should always have Content-Type
    try std.testing.expect(headers.get("Content-Type") != null);

    // Authorization header depends on environment variable
    // We can't reliably test this without mocking environment
}

test "HuggingFaceProviderSettings default values" {
    const settings = HuggingFaceProviderSettings{};

    try std.testing.expect(settings.base_url == null);
    try std.testing.expect(settings.api_key == null);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}

test "HuggingFaceProviderSettings with all fields" {
    const allocator = std.testing.allocator;
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();

    const settings = HuggingFaceProviderSettings{
        .base_url = "https://custom.hf.co",
        .api_key = "test-key",
        .headers = headers,
        .http_client = null,
    };

    try std.testing.expect(settings.base_url != null);
    try std.testing.expectEqualStrings("https://custom.hf.co", settings.base_url.?);
    try std.testing.expect(settings.api_key != null);
    try std.testing.expectEqualStrings("test-key", settings.api_key.?);
}

test "createHuggingFace uses default settings" {
    const allocator = std.testing.allocator;
    var provider1 = createHuggingFace(allocator);
    defer provider1.deinit();

    var provider2 = createHuggingFaceWithSettings(allocator, .{});
    defer provider2.deinit();

    // Both should have same default base_url
    try std.testing.expectEqualStrings(provider1.base_url, provider2.base_url);
}

test "HuggingFaceProvider with multiple custom settings" {
    const allocator = std.testing.allocator;

    var provider = createHuggingFaceWithSettings(allocator, .{
        .base_url = "https://my-inference-endpoint.com/v1",
        .api_key = "hf_test_key_12345",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://my-inference-endpoint.com/v1", provider.base_url);
    try std.testing.expect(provider.settings.api_key != null);
    try std.testing.expectEqualStrings("hf_test_key_12345", provider.settings.api_key.?);
}

test "HuggingFaceProvider languageModel with custom base_url" {
    const allocator = std.testing.allocator;

    var provider = createHuggingFaceWithSettings(allocator, .{
        .base_url = "https://custom-endpoint.hf.co",
    });
    defer provider.deinit();

    const model = provider.languageModel("custom-model");
    try std.testing.expectEqualStrings("custom-model", model.getModelId());
    // The model should be configured with the custom base_url
}

test "HuggingFaceProvider edge case: empty model_id" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);
    defer provider.deinit();

    const model = provider.languageModel("");
    try std.testing.expectEqualStrings("", model.getModelId());
}

test "HuggingFaceProvider edge case: very long model_id" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);
    defer provider.deinit();

    const long_model_id = "organization/very-long-model-name-with-many-hyphens-and-version-numbers-v1.2.3-beta";
    const model = provider.languageModel(long_model_id);
    try std.testing.expectEqualStrings(long_model_id, model.getModelId());
}

test "HuggingFaceProvider edge case: model_id with special characters" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);
    defer provider.deinit();

    const model_id = "org/model_v2.0-beta+20240101";
    const model = provider.languageModel(model_id);
    try std.testing.expectEqualStrings(model_id, model.getModelId());
}

test "HuggingFaceProvider multiple providers with different settings" {
    const allocator = std.testing.allocator;

    var provider1 = createHuggingFaceWithSettings(allocator, .{
        .base_url = "https://endpoint1.hf.co",
    });
    defer provider1.deinit();

    var provider2 = createHuggingFaceWithSettings(allocator, .{
        .base_url = "https://endpoint2.hf.co",
    });
    defer provider2.deinit();

    // Providers should maintain their own settings
    try std.testing.expectEqualStrings("https://endpoint1.hf.co", provider1.base_url);
    try std.testing.expectEqualStrings("https://endpoint2.hf.co", provider2.base_url);
}

test "HuggingFaceProvider init preserves allocator" {
    const allocator = std.testing.allocator;
    const settings = HuggingFaceProviderSettings{};

    const provider = HuggingFaceProvider.init(allocator, settings);

    // Verify allocator is preserved
    try std.testing.expect(provider.allocator.ptr == allocator.ptr);
}

test "HuggingFaceProvider deinit is safe to call" {
    const allocator = std.testing.allocator;
    var provider = createHuggingFace(allocator);

    // Should not crash or leak
    provider.deinit();
    provider.deinit(); // Safe to call multiple times
}

test "huggingface provider returns consistent values" {
    var provider1 = createHuggingFace(std.testing.allocator);
    defer provider1.deinit();
    var provider2 = createHuggingFace(std.testing.allocator);
    defer provider2.deinit();

    // Both providers should have the same provider name
    try std.testing.expectEqualStrings("huggingface", provider1.getProvider());
    try std.testing.expectEqualStrings("huggingface", provider2.getProvider());
}

// ============================================================================
// Behavioral Tests (MockHttpClient)
// ============================================================================

test "HuggingFace doGenerate succeeds via mock HTTP" {
    const allocator = std.testing.allocator;
    const lm = @import("provider").language_model;

    var mock = provider_utils.MockHttpClient.init(allocator);
    defer mock.deinit();

    mock.setResponse(.{
        .status_code = 200,
        .body =
            \\{"id":"chatcmpl-1","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"Hello from HuggingFace"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":3,"total_tokens":8}}
        ,
    });

    var provider = createHuggingFaceWithSettings(allocator, .{
        .api_key = "test-key",
        .http_client = mock.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("mistralai/Mistral-7B-Instruct-v0.2");

    const msg = try lm.userTextMessage(allocator, "Hello");
    defer allocator.free(msg.content.user);

    var lm_model = model.asLanguageModel();
    const CallbackCtx = struct { result: ?lm.LanguageModelV3.GenerateResult = null };
    var cb_ctx = CallbackCtx{};

    lm_model.doGenerate(
        .{ .prompt = &.{msg} },
        allocator,
        struct {
            fn onResult(ctx: ?*anyopaque, result: lm.LanguageModelV3.GenerateResult) void {
                const c: *CallbackCtx = @ptrCast(@alignCast(ctx.?));
                c.result = result;
            }
        }.onResult,
        @as(?*anyopaque, @ptrCast(&cb_ctx)),
    );

    try std.testing.expect(cb_ctx.result != null);
    switch (cb_ctx.result.?) {
        .success => |success| {
            try std.testing.expect(success.content.len > 0);
            switch (success.content[0]) {
                .text => |text| {
                    try std.testing.expectEqualStrings("Hello from HuggingFace", text.text);
                    allocator.free(text.text);
                },
                else => try std.testing.expect(false),
            }
            allocator.free(success.content);
            if (success.response) |resp| {
                if (resp.metadata.id) |id| allocator.free(id);
                if (resp.metadata.model_id) |mid| allocator.free(mid);
            }
        },
        .failure => try std.testing.expect(false),
    }

    try std.testing.expectEqual(@as(usize, 1), mock.requestCount());
}

test "HuggingFace ErrorDiagnostic on HTTP 429 rate limit" {
    const allocator = std.testing.allocator;
    const ErrorDiagnostic = @import("provider").ErrorDiagnostic;
    const lm = @import("provider").language_model;

    var mock = provider_utils.MockHttpClient.init(allocator);
    defer mock.deinit();

    mock.setResponse(.{
        .status_code = 429,
        .body = "{\"error\":{\"message\":\"Rate limit exceeded\",\"type\":\"rate_limit_error\"}}",
    });

    var provider = createHuggingFaceWithSettings(allocator, .{
        .api_key = "test-key",
        .http_client = mock.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("mistralai/Mistral-7B-Instruct-v0.2");

    const msg = try lm.userTextMessage(allocator, "Hello");
    defer allocator.free(msg.content.user);

    var diag: ErrorDiagnostic = .{};
    var lm_model = model.asLanguageModel();
    const CallbackCtx = struct { result: ?lm.LanguageModelV3.GenerateResult = null };
    var cb_ctx = CallbackCtx{};

    lm_model.doGenerate(
        .{ .prompt = &.{msg}, .error_diagnostic = &diag },
        allocator,
        struct {
            fn onResult(ctx: ?*anyopaque, result: lm.LanguageModelV3.GenerateResult) void {
                const c: *CallbackCtx = @ptrCast(@alignCast(ctx.?));
                c.result = result;
            }
        }.onResult,
        @as(?*anyopaque, @ptrCast(&cb_ctx)),
    );

    try std.testing.expect(cb_ctx.result != null);
    switch (cb_ctx.result.?) {
        .failure => {},
        .success => try std.testing.expect(false),
    }

    try std.testing.expectEqual(@as(?u16, 429), diag.status_code);
    try std.testing.expect(diag.kind == .rate_limit);
    try std.testing.expect(diag.is_retryable);
    try std.testing.expectEqualStrings("huggingface.chat", diag.provider.?);
    try std.testing.expectEqualStrings("Rate limit exceeded", diag.message().?);
}

test "HuggingFace ErrorDiagnostic on network error" {
    const allocator = std.testing.allocator;
    const ErrorDiagnostic = @import("provider").ErrorDiagnostic;
    const lm = @import("provider").language_model;

    var mock = provider_utils.MockHttpClient.init(allocator);
    defer mock.deinit();

    mock.setError(.{
        .kind = .connection_failed,
        .message = "Connection refused",
    });

    var provider = createHuggingFaceWithSettings(allocator, .{
        .api_key = "test-key",
        .http_client = mock.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("mistralai/Mistral-7B-Instruct-v0.2");

    const msg = try lm.userTextMessage(allocator, "Hello");
    defer allocator.free(msg.content.user);

    var diag: ErrorDiagnostic = .{};
    var lm_model = model.asLanguageModel();
    const CallbackCtx = struct { result: ?lm.LanguageModelV3.GenerateResult = null };
    var cb_ctx = CallbackCtx{};

    lm_model.doGenerate(
        .{ .prompt = &.{msg}, .error_diagnostic = &diag },
        allocator,
        struct {
            fn onResult(ctx: ?*anyopaque, result: lm.LanguageModelV3.GenerateResult) void {
                const c: *CallbackCtx = @ptrCast(@alignCast(ctx.?));
                c.result = result;
            }
        }.onResult,
        @as(?*anyopaque, @ptrCast(&cb_ctx)),
    );

    try std.testing.expect(diag.kind == .network);
    try std.testing.expectEqualStrings("Connection refused", diag.message().?);
    try std.testing.expectEqualStrings("huggingface.chat", diag.provider.?);
}
