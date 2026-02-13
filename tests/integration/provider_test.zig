const std = @import("std");
const testing = std.testing;

// Integration tests for AI SDK providers
// These tests verify that provider implementations follow the expected interface

test "OpenAI provider interface" {
    const allocator = testing.allocator;

    const openai = @import("openai");
    var provider = openai.createOpenAI(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("openai", provider.getProvider());

    var model = provider.languageModel("gpt-4o");
    try testing.expectEqualStrings("gpt-4o", model.getModelId());
    try testing.expectEqualStrings("openai.chat", model.getProvider());
}

test "Anthropic provider interface" {
    const allocator = testing.allocator;

    const anthropic = @import("anthropic");
    var provider = anthropic.createAnthropic(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("anthropic.messages", provider.getProvider());

    var model = provider.languageModel("claude-sonnet-4-20250514");
    try testing.expectEqualStrings("claude-sonnet-4-20250514", model.getModelId());
}

test "Google provider interface" {
    const allocator = testing.allocator;

    const google = @import("google");
    var provider = google.createGoogleGenerativeAI(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("google.generative-ai", provider.getProvider());

    var model = provider.languageModel("gemini-2.0-flash");
    try testing.expectEqualStrings("gemini-2.0-flash", model.getModelId());
}

test "xAI provider interface" {
    const allocator = testing.allocator;

    const xai = @import("xai");
    var provider = xai.createXai(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("xai", provider.getProvider());
}

test "Perplexity provider interface" {
    const allocator = testing.allocator;

    const perplexity = @import("perplexity");
    var provider = perplexity.createPerplexity(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("perplexity", provider.getProvider());
}

test "Together AI provider interface" {
    const allocator = testing.allocator;

    const togetherai = @import("togetherai");
    var provider = togetherai.createTogetherAI(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("togetherai", provider.getProvider());
}

test "Fireworks provider interface" {
    const allocator = testing.allocator;

    const fireworks = @import("fireworks");
    var provider = fireworks.createFireworks(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("fireworks", provider.getProvider());
}

test "Azure provider interface" {
    const allocator = testing.allocator;

    const azure = @import("azure");
    var provider = azure.createAzure(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("azure", provider.getProvider());
}

test "Cerebras provider interface" {
    const allocator = testing.allocator;

    const cerebras = @import("cerebras");
    var provider = cerebras.createCerebras(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("cerebras", provider.getProvider());
}

test "HuggingFace provider interface" {
    const allocator = testing.allocator;

    const huggingface = @import("huggingface");
    var provider = huggingface.createHuggingFace(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("huggingface", provider.getProvider());
}

test "DeepInfra provider interface" {
    const allocator = testing.allocator;

    const deepinfra = @import("deepinfra");
    var provider = deepinfra.createDeepInfra(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("deepinfra", provider.getProvider());
}
