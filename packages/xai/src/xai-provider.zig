const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;
const openai_compat = @import("openai-compatible");

pub const XaiProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

pub const XaiProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: XaiProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: XaiProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.x.ai/v1",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "xai";
    }

    pub fn languageModel(self: *Self, model_id: []const u8) openai_compat.OpenAICompatibleChatLanguageModel {
        return openai_compat.OpenAICompatibleChatLanguageModel.init(
            self.allocator,
            model_id,
            .{
                .provider = "xai.chat",
                .base_url = self.base_url,
                .api_key = self.settings.api_key,
                .headers_fn = getHeadersFn,
                .http_client = self.settings.http_client,
            },
        );
    }

    pub fn chat(self: *Self, model_id: []const u8) openai_compat.OpenAICompatibleChatLanguageModel {
        return self.languageModel(model_id);
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
    return std.posix.getenv("XAI_API_KEY");
}

/// Caller owns the returned HashMap and must call deinit() when done.
fn getHeadersFn(config: *const openai_compat.OpenAICompatibleConfig, allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();
    try headers.put("Content-Type", "application/json");

    const api_key = config.api_key orelse getApiKeyFromEnv();
    if (api_key) |key| {
        const auth_header = try std.fmt.allocPrint(
            allocator,
            "Bearer {s}",
            .{key},
        );
        try headers.put("Authorization", auth_header);
    }

    return headers;
}

pub fn createXai(allocator: std.mem.Allocator) XaiProvider {
    return XaiProvider.init(allocator, .{});
}

pub fn createXaiWithSettings(
    allocator: std.mem.Allocator,
    settings: XaiProviderSettings,
) XaiProvider {
    return XaiProvider.init(allocator, settings);
}


// ============================================================================
// Unit Tests
// ============================================================================

test "XaiProvider basic initialization" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("xai", provider.getProvider());
}

test "XaiProvider init with default settings" {
    const allocator = std.testing.allocator;
    var provider = XaiProvider.init(allocator, .{});
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://api.x.ai/v1", provider.base_url);
    try std.testing.expectEqualStrings("xai", provider.getProvider());
}

test "XaiProvider init with custom base_url" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.xai.api.com/v2";

    var provider = createXaiWithSettings(allocator, .{
        .base_url = custom_url,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings(custom_url, provider.base_url);
}

test "XaiProvider init with null base_url uses default" {
    const allocator = std.testing.allocator;

    var provider = createXaiWithSettings(allocator, .{
        .base_url = null,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://api.x.ai/v1", provider.base_url);
}

test "XaiProvider specification_version" {
    try std.testing.expectEqualStrings("v3", XaiProvider.specification_version);
}

test "XaiProvider getProvider returns xai" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    const provider_name = provider.getProvider();
    try std.testing.expectEqualStrings("xai", provider_name);
}

test "XaiProvider languageModel creates model with correct id" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    const model_id = "grok-2";
    const model = provider.languageModel(model_id);

    try std.testing.expectEqualStrings(model_id, model.getModelId());
}

test "XaiProvider languageModel with different model ids" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    const test_cases = [_][]const u8{
        "grok-2",
        "grok-2-mini",
        "grok-vision",
    };

    for (test_cases) |model_id| {
        const model = provider.languageModel(model_id);
        try std.testing.expectEqualStrings(model_id, model.getModelId());
    }
}

test "XaiProvider chat is alias for languageModel" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    const model_id = "grok-2";
    const chat_model = provider.chat(model_id);
    const lang_model = provider.languageModel(model_id);

    try std.testing.expectEqualStrings(chat_model.getModelId(), lang_model.getModelId());
    try std.testing.expectEqualStrings(model_id, chat_model.getModelId());
}

test "XaiProvider asProvider returns ProviderV3" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    try std.testing.expect(@intFromPtr(pv3.vtable) != 0);
}

test "XaiProvider asProvider languageModel success" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    var pv3 = provider.asProvider();
    const result = pv3.vtable.languageModel(pv3.impl, "grok-2");

    switch (result) {
        .success => |model| {
            try std.testing.expect(@intFromPtr(model.vtable) != 0);
        },
        .failure, .no_such_model => |err| {
            std.debug.print("Unexpected error: {any}\n", .{err});
            try std.testing.expect(false);
        },
    }
}

test "XaiProvider asProvider embeddingModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    var pv3 = provider.asProvider();
    const result = pv3.vtable.embeddingModel(pv3.impl, "test-model");

    switch (result) {
        .success => {
            try std.testing.expect(false); // Should not succeed
        },
        .failure => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
        .no_such_model => {
            // Expected
        },
    }
}

test "XaiProvider asProvider imageModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    var pv3 = provider.asProvider();
    const result = pv3.vtable.imageModel(pv3.impl, "test-model");

    switch (result) {
        .success => {
            try std.testing.expect(false); // Should not succeed
        },
        .failure => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
        .no_such_model => {
            // Expected
        },
    }
}

test "XaiProvider asProvider speechModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    const result = pv3.speechModel("test-model");

    switch (result) {
        .success => {
            try std.testing.expect(false); // Should not succeed
        },
        .failure => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
        .no_such_model => {
            // Expected
        },
        .not_supported => {
            // Also valid - provider may not support speech
        },
    }
}

test "XaiProvider asProvider transcriptionModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    const pv3 = provider.asProvider();
    const result = pv3.transcriptionModel("test-model");

    switch (result) {
        .success => {
            try std.testing.expect(false); // Should not succeed
        },
        .failure => |err| {
            try std.testing.expectEqual(error.NoSuchModel, err);
        },
        .no_such_model => {
            // Expected
        },
        .not_supported => {
            // Also valid - provider may not support transcription
        },
    }
}

test "XaiProviderSettings default values" {
    const settings = XaiProviderSettings{};

    try std.testing.expectEqual(@as(?[]const u8, null), settings.base_url);
    try std.testing.expectEqual(@as(?[]const u8, null), settings.api_key);
    try std.testing.expectEqual(@as(?std.StringHashMap([]const u8), null), settings.headers);
    try std.testing.expect(settings.http_client == null);
}

test "XaiProviderSettings with custom values" {
    const allocator = std.testing.allocator;
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    try headers.put("X-Custom-Header", "value");

    const settings = XaiProviderSettings{
        .base_url = "https://custom.url",
        .api_key = "test-key",
        .headers = headers,
    };

    try std.testing.expectEqualStrings("https://custom.url", settings.base_url.?);
    try std.testing.expectEqualStrings("test-key", settings.api_key.?);
    try std.testing.expect(settings.headers != null);
}

test "createXai function creates provider" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("xai", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.x.ai/v1", provider.base_url);
}

test "createXaiWithSettings function creates provider with settings" {
    const allocator = std.testing.allocator;
    const settings = XaiProviderSettings{
        .base_url = "https://test.url",
    };

    var provider = createXaiWithSettings(allocator, settings);
    defer provider.deinit();

    try std.testing.expectEqualStrings("xai", provider.getProvider());
    try std.testing.expectEqualStrings("https://test.url", provider.base_url);
}

test "XaiProvider multiple models from same provider" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    const model1 = provider.languageModel("grok-2");
    const model2 = provider.languageModel("grok-2-mini");
    const model3 = provider.chat("grok-vision");

    try std.testing.expectEqualStrings("grok-2", model1.getModelId());
    try std.testing.expectEqualStrings("grok-2-mini", model2.getModelId());
    try std.testing.expectEqualStrings("grok-vision", model3.getModelId());
}

test "XaiProvider settings are stored correctly" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.api.com";
    const custom_key = "sk-test-key";

    const settings = XaiProviderSettings{
        .base_url = custom_url,
        .api_key = custom_key,
    };

    var provider = createXaiWithSettings(allocator, settings);
    defer provider.deinit();

    try std.testing.expectEqualStrings(custom_url, provider.settings.base_url.?);
    try std.testing.expectEqualStrings(custom_key, provider.settings.api_key.?);
}

test "XaiProvider empty model id" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    const model = provider.languageModel("");
    try std.testing.expectEqualStrings("", model.getModelId());
}

test "XaiProvider model with special characters in id" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    const model_id = "grok-2-preview-2024";
    const model = provider.languageModel(model_id);
    try std.testing.expectEqualStrings(model_id, model.getModelId());
}

test "getHeadersFn creates headers with Content-Type" {
    const config = openai_compat.OpenAICompatibleConfig{
        .provider = "xai.chat",
        .base_url = "https://api.x.ai/v1",
        .headers_fn = getHeadersFn,
        .http_client = null,
    };

    var headers = try getHeadersFn(&config, std.testing.allocator);
    defer headers.deinit();

    const content_type = headers.get("Content-Type");
    try std.testing.expect(content_type != null);
    try std.testing.expectEqualStrings("application/json", content_type.?);
}

test "XaiProvider languageModel uses correct base_url" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.xai.com/v1";

    var provider = createXaiWithSettings(allocator, .{
        .base_url = custom_url,
    });
    defer provider.deinit();

    const model = provider.languageModel("grok-2");
    try std.testing.expectEqualStrings(custom_url, model.config.base_url);
}

test "XaiProvider languageModel uses correct provider name" {
    const allocator = std.testing.allocator;
    var provider = createXai(allocator);
    defer provider.deinit();

    const model = provider.languageModel("grok-2");
    try std.testing.expectEqualStrings("xai.chat", model.config.provider);
}

test "XaiProvider vtable is correctly initialized" {
    const vtable = XaiProvider.vtable;

    try std.testing.expect(@intFromPtr(vtable.languageModel) != 0);
    try std.testing.expect(@intFromPtr(vtable.embeddingModel) != 0);
    try std.testing.expect(@intFromPtr(vtable.imageModel) != 0);
    // speechModel and transcriptionModel are optional
}

test "xAI doGenerate succeeds via mock HTTP" {
    const allocator = std.testing.allocator;
    const lm = @import("provider").language_model;

    var mock = provider_utils.MockHttpClient.init(allocator);
    defer mock.deinit();

    mock.setResponse(.{
        .status_code = 200,
        .body =
            \\{"id":"chatcmpl-1","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"Hello from xAI"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":3,"total_tokens":8}}
        ,
    });

    var provider = createXaiWithSettings(allocator, .{
        .api_key = "xai-test-key",
        .http_client = mock.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("grok-2");

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

    // Verify successful response
    try std.testing.expect(cb_ctx.result != null);
    switch (cb_ctx.result.?) {
        .success => |success| {
            try std.testing.expect(success.content.len > 0);
            switch (success.content[0]) {
                .text => |text| {
                    try std.testing.expectEqualStrings("Hello from xAI", text.text);
                    allocator.free(text.text);
                },
                else => try std.testing.expect(false),
            }
            allocator.free(success.content);
            // Free response metadata strings
            if (success.response) |resp| {
                if (resp.metadata.id) |id| allocator.free(id);
                if (resp.metadata.model_id) |mid| allocator.free(mid);
            }
        },
        .failure => try std.testing.expect(false),
    }

    // Verify mock received exactly one request
    try std.testing.expectEqual(@as(usize, 1), mock.requestCount());
}

test "xAI ErrorDiagnostic on HTTP 429 rate limit" {
    const allocator = std.testing.allocator;
    const ErrorDiagnostic = @import("provider").ErrorDiagnostic;
    const lm = @import("provider").language_model;

    var mock = provider_utils.MockHttpClient.init(allocator);
    defer mock.deinit();

    mock.setResponse(.{
        .status_code = 429,
        .body = "{\"error\":{\"message\":\"Rate limit exceeded\",\"type\":\"rate_limit_error\"}}",
    });

    var provider = createXaiWithSettings(allocator, .{
        .api_key = "test-key",
        .http_client = mock.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("grok-2");

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

    // Should have failed
    try std.testing.expect(cb_ctx.result != null);
    switch (cb_ctx.result.?) {
        .failure => {},
        .success => try std.testing.expect(false),
    }

    // Diagnostic should be populated
    try std.testing.expectEqual(@as(?u16, 429), diag.status_code);
    try std.testing.expect(diag.kind == .rate_limit);
    try std.testing.expect(diag.is_retryable);
    try std.testing.expectEqualStrings("xai.chat", diag.provider.?);
    try std.testing.expectEqualStrings("Rate limit exceeded", diag.message().?);
}

test "xAI ErrorDiagnostic on network error" {
    const allocator = std.testing.allocator;
    const ErrorDiagnostic = @import("provider").ErrorDiagnostic;
    const lm = @import("provider").language_model;

    var mock = provider_utils.MockHttpClient.init(allocator);
    defer mock.deinit();

    mock.setError(.{
        .kind = .connection_failed,
        .message = "Connection refused",
    });

    var provider = createXaiWithSettings(allocator, .{
        .api_key = "test-key",
        .http_client = mock.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("grok-2");

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

    // Diagnostic should indicate network error
    try std.testing.expect(diag.kind == .network);
    try std.testing.expectEqualStrings("Connection refused", diag.message().?);
    try std.testing.expectEqualStrings("xai.chat", diag.provider.?);
}
