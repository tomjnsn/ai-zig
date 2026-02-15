const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;
const openai_compat = @import("openai-compatible");

pub const DeepInfraProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

pub const DeepInfraProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: DeepInfraProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: DeepInfraProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.deepinfra.com/v1/openai",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "deepinfra";
    }

    pub fn languageModel(self: *Self, model_id: []const u8) openai_compat.OpenAICompatibleChatLanguageModel {
        return openai_compat.OpenAICompatibleChatLanguageModel.init(
            self.allocator,
            model_id,
            .{
                .provider = "deepinfra.chat",
                .base_url = self.base_url,
                .headers_fn = getHeadersFn,
                .http_client = self.settings.http_client,
            },
        );
    }

    pub fn embeddingModel(self: *Self, model_id: []const u8) openai_compat.OpenAICompatibleEmbeddingModel {
        return openai_compat.OpenAICompatibleEmbeddingModel.init(
            self.allocator,
            model_id,
            .{
                .provider = "deepinfra.embedding",
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

    fn embeddingModelVtable(impl: *anyopaque, model_id: []const u8) provider_v3.EmbeddingModelResult {
        const self: *Self = @ptrCast(@alignCast(impl));
        var model = self.embeddingModel(model_id);
        return .{ .success = model.asEmbeddingModel() };
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
    return std.posix.getenv("DEEPINFRA_API_KEY");
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

pub fn createDeepInfra(allocator: std.mem.Allocator) DeepInfraProvider {
    return DeepInfraProvider.init(allocator, .{});
}

pub fn createDeepInfraWithSettings(
    allocator: std.mem.Allocator,
    settings: DeepInfraProviderSettings,
) DeepInfraProvider {
    return DeepInfraProvider.init(allocator, settings);
}


// ============================================================================
// Tests
// ============================================================================

test "DeepInfraProvider basic initialization" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("deepinfra", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.deepinfra.com/v1/openai", provider.base_url);
}

test "DeepInfraProvider with custom base_url" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfraWithSettings(allocator, .{
        .base_url = "https://custom.deepinfra.com/v1",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("deepinfra", provider.getProvider());
    try std.testing.expectEqualStrings("https://custom.deepinfra.com/v1", provider.base_url);
}

test "DeepInfraProvider with custom api_key" {
    const allocator = std.testing.allocator;
    const custom_api_key = "test-api-key-123";

    var provider = createDeepInfraWithSettings(allocator, .{
        .api_key = custom_api_key,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("deepinfra", provider.getProvider());
    try std.testing.expectEqual(custom_api_key, provider.settings.api_key.?);
}

test "DeepInfraProvider with all custom settings" {
    const allocator = std.testing.allocator;

    var custom_headers = std.StringHashMap([]const u8).init(allocator);
    defer custom_headers.deinit();
    try custom_headers.put("X-Custom-Header", "custom-value");

    var provider = createDeepInfraWithSettings(allocator, .{
        .base_url = "https://custom.deepinfra.com/v1",
        .api_key = "custom-key",
        .headers = custom_headers,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://custom.deepinfra.com/v1", provider.base_url);
    try std.testing.expectEqualStrings("custom-key", provider.settings.api_key.?);
}

test "DeepInfraProvider specification version" {
    try std.testing.expectEqualStrings("v3", DeepInfraProvider.specification_version);
}

test "DeepInfraProvider languageModel creation" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    const model = provider.languageModel("meta-llama/Meta-Llama-3.1-8B-Instruct");
    try std.testing.expectEqualStrings("meta-llama/Meta-Llama-3.1-8B-Instruct", model.getModelId());
}

test "DeepInfraProvider languageModel with different model IDs" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    // Test with various DeepInfra model IDs
    const model_ids = [_][]const u8{
        "meta-llama/Meta-Llama-3.1-8B-Instruct",
        "mistralai/Mixtral-8x7B-Instruct-v0.1",
        "microsoft/WizardLM-2-8x22B",
    };

    for (model_ids) |model_id| {
        const model = provider.languageModel(model_id);
        try std.testing.expectEqualStrings(model_id, model.getModelId());
    }
}

test "DeepInfraProvider embeddingModel creation" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    const model = provider.embeddingModel("BAAI/bge-large-en-v1.5");
    try std.testing.expectEqualStrings("BAAI/bge-large-en-v1.5", model.getModelId());
}

test "DeepInfraProvider embeddingModel with different model IDs" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    const model_ids = [_][]const u8{
        "BAAI/bge-large-en-v1.5",
        "sentence-transformers/all-MiniLM-L6-v2",
        "thenlper/gte-large",
    };

    for (model_ids) |model_id| {
        const model = provider.embeddingModel(model_id);
        try std.testing.expectEqualStrings(model_id, model.getModelId());
    }
}

test "DeepInfraProvider asProvider conversion" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    const prov = provider.asProvider();
    try std.testing.expect(prov.vtable == &DeepInfraProvider.vtable);
}

test "DeepInfraProvider vtable languageModel" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    const prov = provider.asProvider();
    const result = prov.vtable.languageModel(prov.impl, "meta-llama/Meta-Llama-3.1-8B-Instruct");

    switch (result) {
        .success => {},
        .failure, .no_such_model => try std.testing.expect(false),
    }
}

test "DeepInfraProvider vtable embeddingModel" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    const prov = provider.asProvider();
    const result = prov.vtable.embeddingModel(prov.impl, "BAAI/bge-large-en-v1.5");

    switch (result) {
        .success => {},
        .failure, .no_such_model => try std.testing.expect(false),
    }
}

test "DeepInfraProvider vtable imageModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    const prov = provider.asProvider();
    const result = prov.vtable.imageModel(prov.impl, "some-image-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }
}

test "DeepInfraProvider vtable speechModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    const prov = provider.asProvider();
    const result = prov.speechModel("some-speech-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model, .not_supported => {},
    }
}

test "DeepInfraProvider vtable transcriptionModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    const prov = provider.asProvider();
    const result = prov.transcriptionModel("some-transcription-model");

    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model, .not_supported => {},
    }
}

test "DeepInfraProviderSettings defaults" {
    const settings = DeepInfraProviderSettings{};

    try std.testing.expectEqual(@as(?[]const u8, null), settings.base_url);
    try std.testing.expectEqual(@as(?[]const u8, null), settings.api_key);
    try std.testing.expectEqual(@as(?std.StringHashMap([]const u8), null), settings.headers);
    try std.testing.expect(settings.http_client == null);
}

test "DeepInfraProviderSettings with custom values" {
    const allocator = std.testing.allocator;

    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();

    const settings = DeepInfraProviderSettings{
        .base_url = "https://custom.deepinfra.com",
        .api_key = "test-key",
        .headers = headers,
    };

    try std.testing.expectEqualStrings("https://custom.deepinfra.com", settings.base_url.?);
    try std.testing.expectEqualStrings("test-key", settings.api_key.?);
}

test "createDeepInfra uses default settings" {
    const allocator = std.testing.allocator;
    const provider = createDeepInfra(allocator);

    try std.testing.expectEqualStrings("https://api.deepinfra.com/v1/openai", provider.base_url);
}

test "createDeepInfraWithSettings applies custom settings" {
    const allocator = std.testing.allocator;
    const provider = createDeepInfraWithSettings(allocator, .{
        .base_url = "https://test.com",
    });

    try std.testing.expectEqualStrings("https://test.com", provider.base_url);
}

test "deepinfra provider returns valid provider" {
    var provider = createDeepInfra(std.testing.allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("deepinfra", provider.getProvider());
}

test "deepinfra providers have consistent values" {
    var provider1 = createDeepInfra(std.testing.allocator);
    defer provider1.deinit();
    var provider2 = createDeepInfra(std.testing.allocator);
    defer provider2.deinit();

    try std.testing.expectEqualStrings(provider1.getProvider(), provider2.getProvider());
}

test "getHeadersFn creates headers with content type" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    const config = openai_compat.OpenAICompatibleConfig{
        .provider = "deepinfra.chat",
        .base_url = provider.base_url,
        .headers_fn = getHeadersFn,
    };

    var headers = try getHeadersFn(&config, std.testing.allocator);
    defer {
        // Only free the Authorization header if present (it's heap-allocated)
        // Content-Type value is a string literal and shouldn't be freed
        if (headers.get("Authorization")) |auth_value| {
            std.testing.allocator.free(auth_value);
        }
        headers.deinit();
    }

    // Should always have Content-Type header
    const content_type = headers.get("Content-Type");
    try std.testing.expect(content_type != null);
    try std.testing.expectEqualStrings("application/json", content_type.?);
}

test "multiple providers with different settings" {
    const allocator = std.testing.allocator;

    var provider1 = createDeepInfraWithSettings(allocator, .{
        .base_url = "https://provider1.com",
    });
    defer provider1.deinit();

    var provider2 = createDeepInfraWithSettings(allocator, .{
        .base_url = "https://provider2.com",
    });
    defer provider2.deinit();

    try std.testing.expectEqualStrings("https://provider1.com", provider1.base_url);
    try std.testing.expectEqualStrings("https://provider2.com", provider2.base_url);
}

test "provider can create multiple models" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    const model1 = provider.languageModel("model-1");
    const model2 = provider.languageModel("model-2");
    const embed1 = provider.embeddingModel("embed-1");
    const embed2 = provider.embeddingModel("embed-2");

    try std.testing.expectEqualStrings("model-1", model1.getModelId());
    try std.testing.expectEqualStrings("model-2", model2.getModelId());
    try std.testing.expectEqualStrings("embed-1", embed1.getModelId());
    try std.testing.expectEqualStrings("embed-2", embed2.getModelId());
}

test "DeepInfraProvider deinit is idempotent" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);

    // Multiple calls to deinit should not cause issues
    provider.deinit();
    provider.deinit();
}

test "DeepInfraProvider with empty model ID" {
    const allocator = std.testing.allocator;
    var provider = createDeepInfra(allocator);
    defer provider.deinit();

    // Should handle empty model ID gracefully
    const model = provider.languageModel("");
    try std.testing.expectEqualStrings("", model.getModelId());
}

// ============================================================================
// Behavioral Tests (MockHttpClient)
// ============================================================================

test "DeepInfra doGenerate succeeds via mock HTTP" {
    const allocator = std.testing.allocator;
    const lm = @import("provider").language_model;

    var mock = provider_utils.MockHttpClient.init(allocator);
    defer mock.deinit();

    mock.setResponse(.{
        .status_code = 200,
        .body =
            \\{"id":"chatcmpl-1","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"Hello from DeepInfra"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":3,"total_tokens":8}}
        ,
    });

    var provider = createDeepInfraWithSettings(allocator, .{
        .api_key = "test-key",
        .http_client = mock.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("meta-llama/Meta-Llama-3-8B-Instruct");

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
                    try std.testing.expectEqualStrings("Hello from DeepInfra", text.text);
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

test "DeepInfra ErrorDiagnostic on HTTP 429 rate limit" {
    const allocator = std.testing.allocator;
    const ErrorDiagnostic = @import("provider").ErrorDiagnostic;
    const lm = @import("provider").language_model;

    var mock = provider_utils.MockHttpClient.init(allocator);
    defer mock.deinit();

    mock.setResponse(.{
        .status_code = 429,
        .body = "{\"error\":{\"message\":\"Rate limit exceeded\",\"type\":\"rate_limit_error\"}}",
    });

    var provider = createDeepInfraWithSettings(allocator, .{
        .api_key = "test-key",
        .http_client = mock.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("meta-llama/Meta-Llama-3-8B-Instruct");

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
    try std.testing.expectEqualStrings("deepinfra.chat", diag.provider.?);
    try std.testing.expectEqualStrings("Rate limit exceeded", diag.message().?);
}

test "DeepInfra ErrorDiagnostic on network error" {
    const allocator = std.testing.allocator;
    const ErrorDiagnostic = @import("provider").ErrorDiagnostic;
    const lm = @import("provider").language_model;

    var mock = provider_utils.MockHttpClient.init(allocator);
    defer mock.deinit();

    mock.setError(.{
        .kind = .connection_failed,
        .message = "Connection refused",
    });

    var provider = createDeepInfraWithSettings(allocator, .{
        .api_key = "test-key",
        .http_client = mock.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("meta-llama/Meta-Llama-3-8B-Instruct");

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
    try std.testing.expectEqualStrings("deepinfra.chat", diag.provider.?);
}
