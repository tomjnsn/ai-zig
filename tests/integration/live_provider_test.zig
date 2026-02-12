const std = @import("std");
const testing = std.testing;
const ai = @import("ai");
const provider_types = @import("provider");
const provider_utils = @import("provider-utils");
const GenerateTextError = ai.generate_text.GenerateTextError;

// Provider imports
const openai = @import("openai");
const azure = @import("azure");

// NOTE: Excluded providers:
// - xAI: openai-compatible doGenerate is a stub (#7), tests can't work
// - Anthropic, Google, Google Vertex: latent vtable compilation bugs
//
// NOTE: streamText tests omitted - doStreamVtable is a stub (#5)

// ============================================================================
// Helpers
// ============================================================================

fn getEnv(name: []const u8) ?[]const u8 {
    const val = std.posix.getenv(name) orelse return null;
    if (val.len == 0) return null;
    return val;
}

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
