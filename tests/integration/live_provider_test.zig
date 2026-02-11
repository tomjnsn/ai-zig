const std = @import("std");
const testing = std.testing;
const ai = @import("ai");
const provider_types = @import("provider");
const provider_utils = @import("provider-utils");
const GenerateTextError = ai.generate_text.GenerateTextError;

// Provider imports
const openai = @import("openai");
const azure = @import("azure");
const xai = @import("xai");

// NOTE: Anthropic, Google, and Google Vertex are excluded from live tests
// because their vtable code paths contain latent compilation bugs:
// - Anthropic: serializeRequest uses non-existent std.json.stringify,
//   JsonValue/[]const u8 type mismatch, missing postStream method
// - Google: std.json.stringify usage, std.json.Value vs JsonValue mismatch
// - Google Vertex: reuses Google language model, inherits same issues
// These need separate fixes to their serialization/streaming code.

// ============================================================================
// Helpers
// ============================================================================

fn getEnv(name: []const u8) ?[]const u8 {
    const val = std.posix.getenv(name) orelse return null;
    if (val.len == 0) return null;
    return val;
}

/// Stream context that collects text deltas and tracks completion.
const StreamTestCtx = struct {
    text: std.ArrayList(u8),
    completed: bool = false,
    had_error: bool = false,

    fn init(_: std.mem.Allocator) StreamTestCtx {
        return .{ .text = std.ArrayList(u8).empty, .completed = false, .had_error = false };
    }

    fn deinit(self: *StreamTestCtx, allocator: std.mem.Allocator) void {
        self.text.deinit(allocator);
    }

    fn onPart(part: ai.StreamPart, ctx: ?*anyopaque) void {
        const self: *StreamTestCtx = @ptrCast(@alignCast(ctx.?));
        switch (part) {
            .text_delta => |delta| {
                self.text.appendSlice(testing.allocator, delta.text) catch {};
            },
            .finish => {
                self.completed = true;
            },
            else => {},
        }
    }

    fn onError(_: anyerror, ctx: ?*anyopaque) void {
        const self: *StreamTestCtx = @ptrCast(@alignCast(ctx.?));
        self.had_error = true;
    }

    fn onComplete(ctx: ?*anyopaque) void {
        const self: *StreamTestCtx = @ptrCast(@alignCast(ctx.?));
        self.completed = true;
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

test "live: OpenAI streamText" {
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

    var ctx = StreamTestCtx.init(allocator);
    defer ctx.deinit(allocator);

    var stream_result = try ai.streamText(allocator, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
        .callbacks = .{
            .on_part = StreamTestCtx.onPart,
            .on_error = StreamTestCtx.onError,
            .on_complete = StreamTestCtx.onComplete,
            .context = @ptrCast(&ctx),
        },
    });
    defer {
        stream_result.deinit();
        allocator.destroy(stream_result);
    }

    try testing.expect(ctx.completed);
    try testing.expect(ctx.text.items.len > 0);
    try testing.expect(!ctx.had_error);
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

test "live: Azure streamText" {
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

    var ctx = StreamTestCtx.init(allocator);
    defer ctx.deinit(allocator);

    var stream_result = try ai.streamText(allocator, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
        .callbacks = .{
            .on_part = StreamTestCtx.onPart,
            .on_error = StreamTestCtx.onError,
            .on_complete = StreamTestCtx.onComplete,
            .context = @ptrCast(&ctx),
        },
    });
    defer {
        stream_result.deinit();
        allocator.destroy(stream_result);
    }

    try testing.expect(ctx.completed);
    try testing.expect(ctx.text.items.len > 0);
    try testing.expect(!ctx.had_error);
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

// ============================================================================
// xAI
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

    var model = provider.languageModel("grok-2");
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

test "live: xAI streamText" {
    const api_key = getEnv("XAI_API_KEY") orelse return;
    const allocator = testing.allocator;

    var http_client = provider_utils.createStdHttpClient(allocator);
    defer http_client.deinit();

    var provider = xai.createXaiWithSettings(allocator, .{
        .api_key = api_key,
        .http_client = http_client.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("grok-2");
    var lm = model.asLanguageModel();

    var ctx = StreamTestCtx.init(allocator);
    defer ctx.deinit(allocator);

    var stream_result = try ai.streamText(allocator, .{
        .model = &lm,
        .prompt = "Say hello in one word.",
        .callbacks = .{
            .on_part = StreamTestCtx.onPart,
            .on_error = StreamTestCtx.onError,
            .on_complete = StreamTestCtx.onComplete,
            .context = @ptrCast(&ctx),
        },
    });
    defer {
        stream_result.deinit();
        allocator.destroy(stream_result);
    }

    try testing.expect(ctx.completed);
    try testing.expect(ctx.text.items.len > 0);
    try testing.expect(!ctx.had_error);
}

test "live: xAI error diagnostic on invalid key" {
    const allocator = testing.allocator;
    _ = getEnv("XAI_API_KEY") orelse return;

    var http_client = provider_utils.createStdHttpClient(allocator);
    defer http_client.deinit();

    var provider = xai.createXaiWithSettings(allocator, .{
        .api_key = "xai-invalid-key",
        .http_client = http_client.asInterface(),
    });
    defer provider.deinit();

    var model = provider.languageModel("grok-2");
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
