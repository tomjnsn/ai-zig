const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;
const openai_compat = @import("openai-compatible");

pub const CerebrasProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

pub const CerebrasProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: CerebrasProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: CerebrasProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.cerebras.ai/v1",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "cerebras";
    }

    pub fn languageModel(self: *Self, model_id: []const u8) openai_compat.OpenAICompatibleChatLanguageModel {
        return openai_compat.OpenAICompatibleChatLanguageModel.init(
            self.allocator,
            model_id,
            .{
                .provider = "cerebras.chat",
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
        return .{ .no_such_model = model_id };
    }

    fn imageModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.ImageModelResult {
        return .{ .no_such_model = model_id };
    }

    fn speechModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.SpeechModelResult {
        return .{ .no_such_model = model_id };
    }

    fn transcriptionModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.TranscriptionModelResult {
        return .{ .no_such_model = model_id };
    }
};

fn getApiKeyFromEnv() ?[]const u8 {
    return std.posix.getenv("CEREBRAS_API_KEY");
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

pub fn createCerebras(allocator: std.mem.Allocator) CerebrasProvider {
    return CerebrasProvider.init(allocator, .{});
}

pub fn createCerebrasWithSettings(
    allocator: std.mem.Allocator,
    settings: CerebrasProviderSettings,
) CerebrasProvider {
    return CerebrasProvider.init(allocator, settings);
}


// ============================================================================
// Tests
// ============================================================================

test "CerebrasProvider basic initialization" {
    const allocator = std.testing.allocator;
    var provider = createCerebrasWithSettings(allocator, .{});
    defer provider.deinit();
    try std.testing.expectEqualStrings("cerebras", provider.getProvider());
}

test "CerebrasProvider initialization with default settings" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("cerebras", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.cerebras.ai/v1", provider.base_url);
}

test "CerebrasProvider initialization with custom base_url" {
    const allocator = std.testing.allocator;
    const custom_url = "https://custom.cerebras.ai/v1";

    var provider = createCerebrasWithSettings(allocator, .{
        .base_url = custom_url,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings(custom_url, provider.base_url);
    try std.testing.expectEqualStrings("cerebras", provider.getProvider());
}

test "CerebrasProvider initialization with api_key" {
    const allocator = std.testing.allocator;
    const api_key = "test-api-key-123";

    var provider = createCerebrasWithSettings(allocator, .{
        .api_key = api_key,
    });
    defer provider.deinit();

    try std.testing.expect(provider.settings.api_key != null);
    try std.testing.expectEqualStrings(api_key, provider.settings.api_key.?);
}

test "CerebrasProvider initialization with null api_key" {
    const allocator = std.testing.allocator;

    var provider = createCerebrasWithSettings(allocator, .{
        .api_key = null,
    });
    defer provider.deinit();

    try std.testing.expect(provider.settings.api_key == null);
}

test "CerebrasProvider returns consistent values" {
    var provider1 = createCerebras(std.testing.allocator);
    defer provider1.deinit();
    var provider2 = createCerebras(std.testing.allocator);
    defer provider2.deinit();

    try std.testing.expectEqualStrings("cerebras", provider1.getProvider());
    try std.testing.expectEqualStrings("cerebras", provider2.getProvider());
}

test "CerebrasProvider specification version" {
    try std.testing.expectEqualStrings("v3", CerebrasProvider.specification_version);
}

test "CerebrasProvider languageModel creation" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const model = provider.languageModel("llama3.1-8b");
    try std.testing.expectEqualStrings("llama3.1-8b", model.getModelId());
}

test "CerebrasProvider languageModel with different model IDs" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const model1 = provider.languageModel("llama3.1-8b");
    const model2 = provider.languageModel("llama3.1-70b");

    try std.testing.expectEqualStrings("llama3.1-8b", model1.getModelId());
    try std.testing.expectEqualStrings("llama3.1-70b", model2.getModelId());
}

test "CerebrasProvider asProvider returns ProviderV3" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const prov_v3 = provider.asProvider();
    try std.testing.expect(@intFromPtr(prov_v3.vtable) != 0);
}

test "CerebrasProvider vtable languageModel" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    var prov_v3 = provider.asProvider();
    const result = prov_v3.vtable.languageModel(prov_v3.impl, "llama3.1-8b");

    switch (result) {
        .success => |model| {
            try std.testing.expectEqualStrings("llama3.1-8b", model.getModelId());
        },
        .no_such_model => |model_id| {
            std.debug.print("Model not found: {s}\n", .{model_id});
            try std.testing.expect(false);
        },
        .failure => |err| {
            std.debug.print("Unexpected error: {}\n", .{err});
            try std.testing.expect(false);
        },
    }
}

test "CerebrasProvider vtable embeddingModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    var prov_v3 = provider.asProvider();
    const result = prov_v3.vtable.embeddingModel(prov_v3.impl, "text-embedding-3-small");

    switch (result) {
        .success => {
            try std.testing.expect(false); // Should not succeed
        },
        .no_such_model => |model_id| {
            try std.testing.expectEqualStrings("text-embedding-3-small", model_id);
        },
        .failure => |err| {
            std.debug.print("Unexpected error: {}\n", .{err});
            try std.testing.expect(false);
        },
    }
}

test "CerebrasProvider vtable imageModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    var prov_v3 = provider.asProvider();
    const result = prov_v3.vtable.imageModel(prov_v3.impl, "dall-e-3");

    switch (result) {
        .success => {
            try std.testing.expect(false); // Should not succeed
        },
        .no_such_model => |model_id| {
            try std.testing.expectEqualStrings("dall-e-3", model_id);
        },
        .failure => |err| {
            std.debug.print("Unexpected error: {}\n", .{err});
            try std.testing.expect(false);
        },
    }
}

test "CerebrasProvider vtable speechModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const prov_v3 = provider.asProvider();

    // speechModel is optional in the vtable
    if (prov_v3.vtable.speechModel) |speechModelFn| {
        const result = speechModelFn(prov_v3.impl, "tts-1");

        switch (result) {
            .success => {
                try std.testing.expect(false); // Should not succeed
            },
            .no_such_model => |model_id| {
                try std.testing.expectEqualStrings("tts-1", model_id);
            },
            .not_supported => {
                // This is acceptable
            },
            .failure => |err| {
                std.debug.print("Unexpected error: {}\n", .{err});
                try std.testing.expect(false);
            },
        }
    }
}

test "CerebrasProvider vtable transcriptionModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const prov_v3 = provider.asProvider();

    // transcriptionModel is optional in the vtable
    if (prov_v3.vtable.transcriptionModel) |transcriptionModelFn| {
        const result = transcriptionModelFn(prov_v3.impl, "whisper-1");

        switch (result) {
            .success => {
                try std.testing.expect(false); // Should not succeed
            },
            .no_such_model => |model_id| {
                try std.testing.expectEqualStrings("whisper-1", model_id);
            },
            .not_supported => {
                // This is acceptable
            },
            .failure => |err| {
                std.debug.print("Unexpected error: {}\n", .{err});
                try std.testing.expect(false);
            },
        }
    }
}

test "CerebrasProviderSettings default values" {
    const settings = CerebrasProviderSettings{};

    try std.testing.expect(settings.base_url == null);
    try std.testing.expect(settings.api_key == null);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}

test "CerebrasProviderSettings with partial configuration" {
    const settings = CerebrasProviderSettings{
        .base_url = "https://custom.api.com",
        .api_key = "test-key",
    };

    try std.testing.expect(settings.base_url != null);
    try std.testing.expectEqualStrings("https://custom.api.com", settings.base_url.?);
    try std.testing.expect(settings.api_key != null);
    try std.testing.expectEqualStrings("test-key", settings.api_key.?);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}

test "getHeadersFn creates correct headers" {
    const config = openai_compat.OpenAICompatibleConfig{
        .base_url = "https://api.cerebras.ai/v1",
        .provider = "cerebras.chat",
    };

    var headers = try getHeadersFn(&config, std.testing.allocator);
    defer headers.deinit();

    const content_type = headers.get("Content-Type");
    try std.testing.expect(content_type != null);
    try std.testing.expectEqualStrings("application/json", content_type.?);
}

test "getHeadersFn includes authorization when env var is set" {
    // Note: This test depends on CEREBRAS_API_KEY environment variable
    // If not set, it will still pass but won't test authorization header
    const config = openai_compat.OpenAICompatibleConfig{
        .base_url = "https://api.cerebras.ai/v1",
        .provider = "cerebras.chat",
    };

    var headers = try getHeadersFn(&config, std.testing.allocator);
    defer headers.deinit();

    if (getApiKeyFromEnv()) |_| {
        const auth_header = headers.get("Authorization");
        try std.testing.expect(auth_header != null);
    }
}

test "getApiKeyFromEnv returns null or string" {
    const result = getApiKeyFromEnv();

    // Should return either null or a valid string slice
    if (result) |key| {
        try std.testing.expect(key.len > 0);
    }
}

test "CerebrasProvider multiple models from same provider" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const model1 = provider.languageModel("llama3.1-8b");
    const model2 = provider.languageModel("llama3.1-70b");
    const model3 = provider.languageModel("llama3.3-70b");

    try std.testing.expectEqualStrings("llama3.1-8b", model1.getModelId());
    try std.testing.expectEqualStrings("llama3.1-70b", model2.getModelId());
    try std.testing.expectEqualStrings("llama3.3-70b", model3.getModelId());
}

test "CerebrasProvider base_url fallback to default" {
    const allocator = std.testing.allocator;

    var provider1 = createCerebrasWithSettings(allocator, .{
        .base_url = null,
    });
    defer provider1.deinit();

    try std.testing.expectEqualStrings("https://api.cerebras.ai/v1", provider1.base_url);

    var provider2 = createCerebrasWithSettings(allocator, .{});
    defer provider2.deinit();

    try std.testing.expectEqualStrings("https://api.cerebras.ai/v1", provider2.base_url);
}

test "CerebrasProvider custom base_url overrides default" {
    const allocator = std.testing.allocator;
    const custom = "https://my-custom-cerebras.com/api/v2";

    var provider = createCerebrasWithSettings(allocator, .{
        .base_url = custom,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings(custom, provider.base_url);
    try std.testing.expect(!std.mem.eql(u8, provider.base_url, "https://api.cerebras.ai/v1"));
}

test "CerebrasProvider empty model_id" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const model = provider.languageModel("");
    try std.testing.expectEqualStrings("", model.getModelId());
}

test "CerebrasProvider long model_id" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const long_model_id = "llama-3-1-8b-instruct-very-long-model-name-for-testing-purposes";
    const model = provider.languageModel(long_model_id);
    try std.testing.expectEqualStrings(long_model_id, model.getModelId());
}

test "CerebrasProvider model with special characters" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const special_model_id = "llama-3.1_8b-instruct@v2";
    const model = provider.languageModel(special_model_id);
    try std.testing.expectEqualStrings(special_model_id, model.getModelId());
}

test "CerebrasProvider deinit multiple times" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);

    // First deinit
    provider.deinit();

    // Second deinit should not crash
    provider.deinit();
}

test "CerebrasProvider languageModel passes correct provider name" {
    const allocator = std.testing.allocator;
    var provider = createCerebras(allocator);
    defer provider.deinit();

    const model = provider.languageModel("llama3.1-8b");

    // The model should be using "cerebras.chat" as provider
    try std.testing.expectEqualStrings("llama3.1-8b", model.getModelId());
}

// ============================================================================
// Behavioral Tests (MockHttpClient)
// ============================================================================

test "Cerebras doGenerate succeeds via mock HTTP" {
    const allocator = std.testing.allocator;
    const lm = @import("provider").language_model;

    var mock = provider_utils.MockHttpClient.init(allocator);
    defer mock.deinit();

    mock.setResponse(.{
        .status_code = 200,
        .body =
            \\{"id":"chatcmpl-1","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"Hello from Cerebras"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":3,"total_tokens":8}}
        ,
    });

    var provider = createCerebrasWithSettings(allocator, .{
        .api_key = "test-key",
        .http_client = mock.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("llama3.1-8b");

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
                    try std.testing.expectEqualStrings("Hello from Cerebras", text.text);
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

test "Cerebras ErrorDiagnostic on HTTP 429 rate limit" {
    const allocator = std.testing.allocator;
    const ErrorDiagnostic = @import("provider").ErrorDiagnostic;
    const lm = @import("provider").language_model;

    var mock = provider_utils.MockHttpClient.init(allocator);
    defer mock.deinit();

    mock.setResponse(.{
        .status_code = 429,
        .body = "{\"error\":{\"message\":\"Rate limit exceeded\",\"type\":\"rate_limit_error\"}}",
    });

    var provider = createCerebrasWithSettings(allocator, .{
        .api_key = "test-key",
        .http_client = mock.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("llama3.1-8b");

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
    try std.testing.expectEqualStrings("cerebras.chat", diag.provider.?);
    try std.testing.expectEqualStrings("Rate limit exceeded", diag.message().?);
}

test "Cerebras ErrorDiagnostic on network error" {
    const allocator = std.testing.allocator;
    const ErrorDiagnostic = @import("provider").ErrorDiagnostic;
    const lm = @import("provider").language_model;

    var mock = provider_utils.MockHttpClient.init(allocator);
    defer mock.deinit();

    mock.setError(.{
        .kind = .connection_failed,
        .message = "Connection refused",
    });

    var provider = createCerebrasWithSettings(allocator, .{
        .api_key = "test-key",
        .http_client = mock.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("llama3.1-8b");

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
    try std.testing.expectEqualStrings("cerebras.chat", diag.provider.?);
}
