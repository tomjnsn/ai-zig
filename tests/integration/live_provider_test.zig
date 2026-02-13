const std = @import("std");
const testing = std.testing;
const ai = @import("ai");
const provider_types = @import("provider");
const provider_utils = @import("provider-utils");
const GenerateTextError = ai.generate_text.GenerateTextError;
const StreamTextError = ai.generate_text.StreamTextError;
const StreamPart = ai.StreamPart;
const StreamCallbacks = ai.StreamCallbacks;

// Provider imports
const openai = @import("openai");
const azure = @import("azure");
const anthropic = @import("anthropic");
const google = @import("google");
const xai = @import("xai");

// ============================================================================
// Helpers
// ============================================================================

fn getEnv(name: []const u8) ?[]const u8 {
    const val = std.posix.getenv(name) orelse return null;
    if (val.len == 0) return null;
    return val;
}

/// Test context for collecting streaming results
const StreamTestCtx = struct {
    text_buf: std.ArrayList(u8) = std.ArrayList(u8).empty,
    error_count: u32 = 0,
    finished: bool = false,
    completed: bool = false,
    alloc: std.mem.Allocator,

    fn onPart(part: StreamPart, ctx_raw: ?*anyopaque) void {
        if (ctx_raw) |p| {
            const self: *StreamTestCtx = @ptrCast(@alignCast(p));
            switch (part) {
                .text_delta => |d| {
                    self.text_buf.appendSlice(self.alloc, d.text) catch {};
                },
                .finish => {
                    self.finished = true;
                },
                else => {},
            }
        }
    }

    fn onError(_: anyerror, ctx_raw: ?*anyopaque) void {
        if (ctx_raw) |p| {
            const self: *StreamTestCtx = @ptrCast(@alignCast(p));
            self.error_count += 1;
        }
    }

    fn onComplete(ctx_raw: ?*anyopaque) void {
        if (ctx_raw) |p| {
            const self: *StreamTestCtx = @ptrCast(@alignCast(p));
            self.completed = true;
        }
    }

    fn callbacks(self: *StreamTestCtx) StreamCallbacks {
        return .{
            .on_part = onPart,
            .on_error = onError,
            .on_complete = onComplete,
            .context = @ptrCast(self),
        };
    }

    fn deinit(self: *StreamTestCtx) void {
        self.text_buf.deinit(self.alloc);
    }
};

// ============================================================================
// OpenAI
// ============================================================================

test "live: OpenAI generateText" {
    const api_key = getEnv("OPENAI_API_KEY") orelse return;
    const allocator = testing.allocator;

    var http_client = provider_utils.createStdHttpClient(allocator);
    defer http_client.deinit();

    var provider = openai.createOpenAIWithSettings(allocator, .{
        .api_key = api_key,
        .http_client = http_client.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("gpt-4o-mini");
    var lm = model.asLanguageModel();
    var result = try ai.generateText(allocator, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
    });
    defer result.deinit(allocator);

    try testing.expect(result.text.len > 0);
    try testing.expect(result.finish_reason == .stop);
    try testing.expect(result.usage.input_tokens != null);
    try testing.expect(result.usage.output_tokens != null);
}

test "live: OpenAI error diagnostic on invalid key" {
    const allocator = testing.allocator;
    _ = getEnv("OPENAI_API_KEY") orelse return;

    var http_client = provider_utils.createStdHttpClient(allocator);
    defer http_client.deinit();

    var provider = openai.createOpenAIWithSettings(allocator, .{
        .api_key = "sk-invalid-key-for-testing",
        .http_client = http_client.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("gpt-4o-mini");
    var lm = model.asLanguageModel();
    var diag: provider_types.ErrorDiagnostic = .{};

    const result = ai.generateText(allocator, .{
        .model = &lm,
        .prompt = "Hello",
        .error_diagnostic = &diag,
    });

    try testing.expectError(GenerateTextError.ModelError, result);
    try testing.expect(diag.kind == .authentication);
    try testing.expect(diag.message() != null);
    try testing.expect(diag.status_code != null);
}

test "live: OpenAI streamText" {
    const api_key = getEnv("OPENAI_API_KEY") orelse return;

    // Arena for all streaming allocations (providers leak through HTTP client)
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var http_client = provider_utils.createStdHttpClient(alloc);
    var provider = openai.createOpenAIWithSettings(alloc, .{
        .api_key = api_key,
        .http_client = http_client.asInterface(),
    });

    var model = provider.languageModel("gpt-4o-mini");
    var lm = model.asLanguageModel();

    var ctx = StreamTestCtx{ .alloc = alloc };

    const stream_result = ai.streamText(alloc, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
        .callbacks = ctx.callbacks(),
    }) catch |err| {
        std.debug.print("OpenAI streamText error: {}\n", .{err});
        return err;
    };

    try testing.expect(ctx.completed);
    try testing.expect(ctx.text_buf.items.len > 0);
    try testing.expect(ctx.error_count == 0);
    try testing.expect(stream_result.getText().len > 0);
}

// ============================================================================
// Azure OpenAI
// ============================================================================

test "live: Azure generateText" {
    const api_key = getEnv("AZURE_API_KEY") orelse return;
    const resource_name = getEnv("AZURE_RESOURCE_NAME") orelse return;
    const deployment_name = getEnv("AZURE_DEPLOYMENT_NAME") orelse return;
    const allocator = testing.allocator;

    var http_client = provider_utils.createStdHttpClient(allocator);
    defer http_client.deinit();

    var provider = azure.createAzureWithSettings(allocator, .{
        .api_key = api_key,
        .resource_name = resource_name,
        .http_client = http_client.asInterface(),
    });
    defer provider.deinit();

    var model = provider.chat(deployment_name);
    var lm = model.asLanguageModel();
    var result = try ai.generateText(allocator, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
    });
    defer result.deinit(allocator);

    try testing.expect(result.text.len > 0);
    try testing.expect(result.finish_reason == .stop);
    try testing.expect(result.usage.input_tokens != null);
    try testing.expect(result.usage.output_tokens != null);
}

test "live: Azure error diagnostic on invalid key" {
    const allocator = testing.allocator;
    _ = getEnv("AZURE_API_KEY") orelse return;
    const resource_name = getEnv("AZURE_RESOURCE_NAME") orelse return;
    const deployment_name = getEnv("AZURE_DEPLOYMENT_NAME") orelse return;

    var http_client = provider_utils.createStdHttpClient(allocator);
    defer http_client.deinit();

    var provider = azure.createAzureWithSettings(allocator, .{
        .api_key = "invalid-azure-key",
        .resource_name = resource_name,
        .http_client = http_client.asInterface(),
    });
    defer provider.deinit();

    var model = provider.chat(deployment_name);
    var lm = model.asLanguageModel();
    var diag: provider_types.ErrorDiagnostic = .{};

    const result = ai.generateText(allocator, .{
        .model = &lm,
        .prompt = "Hello",
        .error_diagnostic = &diag,
    });

    try testing.expectError(GenerateTextError.ModelError, result);
    try testing.expect(diag.kind == .authentication or diag.kind == .invalid_request);
    try testing.expect(diag.message() != null);
    try testing.expect(diag.status_code != null);
}

test "live: Azure streamText" {
    const api_key = getEnv("AZURE_API_KEY") orelse return;
    const resource_name = getEnv("AZURE_RESOURCE_NAME") orelse return;
    const deployment_name = getEnv("AZURE_DEPLOYMENT_NAME") orelse return;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var http_client = provider_utils.createStdHttpClient(alloc);
    var provider = azure.createAzureWithSettings(alloc, .{
        .api_key = api_key,
        .resource_name = resource_name,
        .http_client = http_client.asInterface(),
    });

    var model = provider.chat(deployment_name);
    var lm = model.asLanguageModel();

    var ctx = StreamTestCtx{ .alloc = alloc };

    const stream_result = ai.streamText(alloc, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
        .callbacks = ctx.callbacks(),
    }) catch |err| {
        std.debug.print("Azure streamText error: {}\n", .{err});
        return err;
    };

    try testing.expect(ctx.completed);
    try testing.expect(ctx.text_buf.items.len > 0);
    try testing.expect(ctx.error_count == 0);
    try testing.expect(stream_result.getText().len > 0);
}

// ============================================================================
// Anthropic
// ============================================================================

test "live: Anthropic generateText" {
    const api_key = getEnv("ANTHROPIC_API_KEY") orelse return;
    const allocator = testing.allocator;

    var http_client = provider_utils.createStdHttpClient(allocator);
    defer http_client.deinit();

    var provider = anthropic.createAnthropicWithSettings(allocator, .{
        .api_key = api_key,
        .http_client = http_client.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("claude-sonnet-4-5-20250929");
    var lm = model.asLanguageModel();
    var result = try ai.generateText(allocator, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
    });
    defer result.deinit(allocator);

    try testing.expect(result.text.len > 0);
    try testing.expect(result.finish_reason == .stop);
    try testing.expect(result.usage.input_tokens != null);
    try testing.expect(result.usage.output_tokens != null);
}

test "live: Anthropic error diagnostic on invalid key" {
    const allocator = testing.allocator;
    _ = getEnv("ANTHROPIC_API_KEY") orelse return;

    var http_client = provider_utils.createStdHttpClient(allocator);
    defer http_client.deinit();

    var provider = anthropic.createAnthropicWithSettings(allocator, .{
        .api_key = "sk-ant-invalid-key-for-testing",
        .http_client = http_client.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("claude-sonnet-4-5-20250929");
    var lm = model.asLanguageModel();
    var diag: provider_types.ErrorDiagnostic = .{};

    const result = ai.generateText(allocator, .{
        .model = &lm,
        .prompt = "Hello",
        .error_diagnostic = &diag,
    });

    try testing.expectError(GenerateTextError.ModelError, result);
    try testing.expect(diag.kind == .authentication);
    try testing.expect(diag.message() != null);
    try testing.expect(diag.status_code != null);
}

test "live: Anthropic streamText" {
    const api_key = getEnv("ANTHROPIC_API_KEY") orelse return;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var http_client = provider_utils.createStdHttpClient(alloc);
    var provider = anthropic.createAnthropicWithSettings(alloc, .{
        .api_key = api_key,
        .http_client = http_client.asInterface(),
    });

    var model = provider.languageModel("claude-sonnet-4-5-20250929");
    var lm = model.asLanguageModel();

    var ctx = StreamTestCtx{ .alloc = alloc };

    const stream_result = ai.streamText(alloc, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
        .callbacks = ctx.callbacks(),
    }) catch |err| {
        std.debug.print("Anthropic streamText error: {}\n", .{err});
        return err;
    };

    try testing.expect(ctx.completed);
    try testing.expect(ctx.text_buf.items.len > 0);
    try testing.expect(ctx.error_count == 0);
    try testing.expect(stream_result.getText().len > 0);
}

// ============================================================================
// Google Generative AI
// ============================================================================

test "live: Google generateText" {
    const api_key = getEnv("GOOGLE_GENERATIVE_AI_API_KEY") orelse return;
    const allocator = testing.allocator;

    var http_client = provider_utils.createStdHttpClient(allocator);
    defer http_client.deinit();

    var provider = google.createGoogleGenerativeAIWithSettings(allocator, .{
        .api_key = api_key,
        .http_client = http_client.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("gemini-2.0-flash");
    var lm = model.asLanguageModel();
    var result = try ai.generateText(allocator, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
    });
    defer result.deinit(allocator);

    try testing.expect(result.text.len > 0);
    try testing.expect(result.finish_reason == .stop);
    try testing.expect(result.usage.input_tokens != null);
    try testing.expect(result.usage.output_tokens != null);
}

test "live: Google error diagnostic on invalid key" {
    const allocator = testing.allocator;
    _ = getEnv("GOOGLE_GENERATIVE_AI_API_KEY") orelse return;

    var http_client = provider_utils.createStdHttpClient(allocator);
    defer http_client.deinit();

    var provider = google.createGoogleGenerativeAIWithSettings(allocator, .{
        .api_key = "invalid-google-key",
        .http_client = http_client.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("gemini-2.0-flash");
    var lm = model.asLanguageModel();
    var diag: provider_types.ErrorDiagnostic = .{};

    const result = ai.generateText(allocator, .{
        .model = &lm,
        .prompt = "Hello",
        .error_diagnostic = &diag,
    });

    try testing.expectError(GenerateTextError.ModelError, result);
    try testing.expect(diag.kind == .authentication or diag.kind == .invalid_request);
    try testing.expect(diag.message() != null);
    try testing.expect(diag.status_code != null);
}

test "live: Google streamText" {
    const api_key = getEnv("GOOGLE_GENERATIVE_AI_API_KEY") orelse return;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var http_client = provider_utils.createStdHttpClient(alloc);
    var provider = google.createGoogleGenerativeAIWithSettings(alloc, .{
        .api_key = api_key,
        .http_client = http_client.asInterface(),
    });

    var model = provider.languageModel("gemini-2.0-flash");
    var lm = model.asLanguageModel();

    var ctx = StreamTestCtx{ .alloc = alloc };

    const stream_result = ai.streamText(alloc, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
        .callbacks = ctx.callbacks(),
    }) catch |err| {
        std.debug.print("Google streamText error: {}\n", .{err});
        return err;
    };

    try testing.expect(ctx.completed);
    try testing.expect(ctx.text_buf.items.len > 0);
    try testing.expect(ctx.error_count == 0);
    try testing.expect(stream_result.getText().len > 0);
}

// ============================================================================
// xAI (Grok)
// ============================================================================

test "live: xAI generateText" {
    const api_key = getEnv("XAI_API_KEY") orelse return;
    const allocator = testing.allocator;

    var http_client = provider_utils.createStdHttpClient(allocator);
    defer http_client.deinit();

    var provider = xai.createXaiWithSettings(allocator, .{
        .api_key = api_key,
        .http_client = http_client.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("grok-3-mini-fast");
    var lm = model.asLanguageModel();
    var result = try ai.generateText(allocator, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
    });
    defer result.deinit(allocator);

    try testing.expect(result.text.len > 0);
    try testing.expect(result.finish_reason == .stop);
    try testing.expect(result.usage.input_tokens != null);
    try testing.expect(result.usage.output_tokens != null);
}

test "live: xAI error diagnostic on invalid key" {
    const allocator = testing.allocator;
    _ = getEnv("XAI_API_KEY") orelse return;

    var http_client = provider_utils.createStdHttpClient(allocator);
    defer http_client.deinit();

    var provider = xai.createXaiWithSettings(allocator, .{
        .api_key = "xai-invalid-key-for-testing",
        .http_client = http_client.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("grok-3-mini-fast");
    var lm = model.asLanguageModel();
    var diag: provider_types.ErrorDiagnostic = .{};

    const result = ai.generateText(allocator, .{
        .model = &lm,
        .prompt = "Hello",
        .error_diagnostic = &diag,
    });

    try testing.expectError(GenerateTextError.ModelError, result);
    // xAI returns HTTP 400 (not 401) for invalid keys
    try testing.expect(diag.kind == .authentication or diag.kind == .invalid_request);
    try testing.expect(diag.message() != null);
    try testing.expect(diag.status_code != null);
}

test "live: xAI streamText" {
    const api_key = getEnv("XAI_API_KEY") orelse return;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var http_client = provider_utils.createStdHttpClient(alloc);
    var provider = xai.createXaiWithSettings(alloc, .{
        .api_key = api_key,
        .http_client = http_client.asInterface(),
    });

    var model = provider.languageModel("grok-3-mini-fast");
    var lm = model.asLanguageModel();

    var ctx = StreamTestCtx{ .alloc = alloc };

    const stream_result = ai.streamText(alloc, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
        .callbacks = ctx.callbacks(),
    }) catch |err| {
        std.debug.print("xAI streamText error: {}\n", .{err});
        return err;
    };

    try testing.expect(ctx.completed);
    try testing.expect(ctx.text_buf.items.len > 0);
    try testing.expect(ctx.error_count == 0);
    try testing.expect(stream_result.getText().len > 0);
}
