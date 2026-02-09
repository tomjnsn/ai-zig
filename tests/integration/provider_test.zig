const std = @import("std");
const testing = std.testing;

// Integration tests for AI SDK providers
// These tests verify that provider implementations follow the expected interface
//
// Note: Some providers (deepseek, amazon-bedrock, deepinfra, fal, luma,
// black-forest-labs, lmnt, hume, assemblyai, gladia, revai, google-vertex)
// use relative path imports (../../provider/src/...) which prevent them from
// being compiled in a separate test binary. They are tested through their own
// index.zig compilation units in build.zig instead.

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

test "Mistral provider interface" {
    const allocator = testing.allocator;

    const mistral = @import("mistral");
    var provider = mistral.createMistral(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("mistral", provider.getProvider());

    var model = provider.languageModel("mistral-large-latest");
    try testing.expectEqualStrings("mistral-large-latest", model.getModelId());
}

test "Cohere provider interface" {
    const allocator = testing.allocator;

    const cohere = @import("cohere");
    var provider = cohere.createCohere(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("cohere", provider.getProvider());

    var model = provider.languageModel("command-r-plus");
    try testing.expectEqualStrings("command-r-plus", model.getModelId());
}

test "Groq provider interface" {
    const allocator = testing.allocator;

    const groq = @import("groq");
    var provider = groq.createGroq(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("groq", provider.getProvider());

    var model = provider.languageModel("llama-3.3-70b-versatile");
    try testing.expectEqualStrings("llama-3.3-70b-versatile", model.getModelId());
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

test "ElevenLabs provider interface" {
    const allocator = testing.allocator;

    const elevenlabs = @import("elevenlabs");
    var provider = elevenlabs.createElevenLabs(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("elevenlabs", provider.getProvider());
}

test "Deepgram provider interface" {
    const allocator = testing.allocator;

    const deepgram = @import("deepgram");
    var provider = deepgram.createDeepgram(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("deepgram", provider.getProvider());
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

test "Replicate provider interface" {
    const allocator = testing.allocator;

    const replicate = @import("replicate");
    var provider = replicate.createReplicate(allocator);
    defer provider.deinit();

    try testing.expectEqualStrings("replicate", provider.getProvider());
}
