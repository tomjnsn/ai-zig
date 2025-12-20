const std = @import("std");

/// Root build file for the Zig AI SDK
/// This builds all packages and their tests
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Provider package (core types and interfaces)
    const provider_mod = b.addModule("provider", .{
        .root_source_file = b.path("packages/provider/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Provider utils package
    const provider_utils_mod = b.addModule("provider-utils", .{
        .root_source_file = b.path("packages/provider-utils/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    provider_utils_mod.addImport("provider", provider_mod);

    // AI package (high-level API)
    const ai_mod = b.addModule("ai", .{
        .root_source_file = b.path("packages/ai/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    ai_mod.addImport("provider", provider_mod);
    ai_mod.addImport("provider-utils", provider_utils_mod);

    // OpenAI provider
    const openai_mod = b.addModule("openai", .{
        .root_source_file = b.path("packages/openai/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    openai_mod.addImport("provider", provider_mod);
    openai_mod.addImport("provider-utils", provider_utils_mod);

    // Anthropic provider
    const anthropic_mod = b.addModule("anthropic", .{
        .root_source_file = b.path("packages/anthropic/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    anthropic_mod.addImport("provider", provider_mod);
    anthropic_mod.addImport("provider-utils", provider_utils_mod);

    // Google provider
    const google_mod = b.addModule("google", .{
        .root_source_file = b.path("packages/google/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    google_mod.addImport("provider", provider_mod);
    google_mod.addImport("provider-utils", provider_utils_mod);

    // Google Vertex provider
    const google_vertex_mod = b.addModule("google-vertex", .{
        .root_source_file = b.path("packages/google-vertex/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    google_vertex_mod.addImport("provider", provider_mod);
    google_vertex_mod.addImport("provider-utils", provider_utils_mod);

    // Azure provider
    const azure_mod = b.addModule("azure", .{
        .root_source_file = b.path("packages/azure/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    azure_mod.addImport("provider", provider_mod);
    azure_mod.addImport("provider-utils", provider_utils_mod);

    // Amazon Bedrock provider
    const bedrock_mod = b.addModule("amazon-bedrock", .{
        .root_source_file = b.path("packages/amazon-bedrock/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    bedrock_mod.addImport("provider", provider_mod);
    bedrock_mod.addImport("provider-utils", provider_utils_mod);

    // Mistral provider
    const mistral_mod = b.addModule("mistral", .{
        .root_source_file = b.path("packages/mistral/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    mistral_mod.addImport("provider", provider_mod);
    mistral_mod.addImport("provider-utils", provider_utils_mod);

    // Cohere provider
    const cohere_mod = b.addModule("cohere", .{
        .root_source_file = b.path("packages/cohere/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    cohere_mod.addImport("provider", provider_mod);
    cohere_mod.addImport("provider-utils", provider_utils_mod);

    // Groq provider
    const groq_mod = b.addModule("groq", .{
        .root_source_file = b.path("packages/groq/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    groq_mod.addImport("provider", provider_mod);
    groq_mod.addImport("provider-utils", provider_utils_mod);

    // DeepSeek provider
    const deepseek_mod = b.addModule("deepseek", .{
        .root_source_file = b.path("packages/deepseek/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    deepseek_mod.addImport("provider", provider_mod);
    deepseek_mod.addImport("provider-utils", provider_utils_mod);

    // OpenAI Compatible provider (needed by xAI, Perplexity, etc.)
    const openai_compatible_mod = b.addModule("openai-compatible", .{
        .root_source_file = b.path("packages/openai-compatible/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    openai_compatible_mod.addImport("provider", provider_mod);
    openai_compatible_mod.addImport("provider-utils", provider_utils_mod);

    // xAI provider
    const xai_mod = b.addModule("xai", .{
        .root_source_file = b.path("packages/xai/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    xai_mod.addImport("provider", provider_mod);
    xai_mod.addImport("provider-utils", provider_utils_mod);
    xai_mod.addImport("openai-compatible", openai_compatible_mod);

    // Perplexity provider
    const perplexity_mod = b.addModule("perplexity", .{
        .root_source_file = b.path("packages/perplexity/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    perplexity_mod.addImport("provider", provider_mod);
    perplexity_mod.addImport("provider-utils", provider_utils_mod);
    perplexity_mod.addImport("openai-compatible", openai_compatible_mod);

    // Together AI provider
    const togetherai_mod = b.addModule("togetherai", .{
        .root_source_file = b.path("packages/togetherai/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    togetherai_mod.addImport("provider", provider_mod);
    togetherai_mod.addImport("provider-utils", provider_utils_mod);

    // Fireworks provider
    const fireworks_mod = b.addModule("fireworks", .{
        .root_source_file = b.path("packages/fireworks/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    fireworks_mod.addImport("provider", provider_mod);
    fireworks_mod.addImport("provider-utils", provider_utils_mod);
    fireworks_mod.addImport("openai-compatible", openai_compatible_mod);

    // Cerebras provider
    const cerebras_mod = b.addModule("cerebras", .{
        .root_source_file = b.path("packages/cerebras/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    cerebras_mod.addImport("provider", provider_mod);
    cerebras_mod.addImport("provider-utils", provider_utils_mod);
    cerebras_mod.addImport("openai-compatible", openai_compatible_mod);

    // DeepInfra provider
    const deepinfra_mod = b.addModule("deepinfra", .{
        .root_source_file = b.path("packages/deepinfra/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    deepinfra_mod.addImport("provider", provider_mod);
    deepinfra_mod.addImport("provider-utils", provider_utils_mod);
    deepinfra_mod.addImport("openai-compatible", openai_compatible_mod);

    // Replicate provider
    const replicate_mod = b.addModule("replicate", .{
        .root_source_file = b.path("packages/replicate/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    replicate_mod.addImport("provider", provider_mod);
    replicate_mod.addImport("provider-utils", provider_utils_mod);

    // HuggingFace provider
    const huggingface_mod = b.addModule("huggingface", .{
        .root_source_file = b.path("packages/huggingface/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    huggingface_mod.addImport("provider", provider_mod);
    huggingface_mod.addImport("provider-utils", provider_utils_mod);
    huggingface_mod.addImport("openai-compatible", openai_compatible_mod);

    // ElevenLabs provider
    const elevenlabs_mod = b.addModule("elevenlabs", .{
        .root_source_file = b.path("packages/elevenlabs/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    elevenlabs_mod.addImport("provider", provider_mod);
    elevenlabs_mod.addImport("provider-utils", provider_utils_mod);

    // Fal provider
    const fal_mod = b.addModule("fal", .{
        .root_source_file = b.path("packages/fal/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    fal_mod.addImport("provider", provider_mod);
    fal_mod.addImport("provider-utils", provider_utils_mod);

    // Luma provider
    const luma_mod = b.addModule("luma", .{
        .root_source_file = b.path("packages/luma/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    luma_mod.addImport("provider", provider_mod);
    luma_mod.addImport("provider-utils", provider_utils_mod);

    // Black Forest Labs provider
    const bfl_mod = b.addModule("black-forest-labs", .{
        .root_source_file = b.path("packages/black-forest-labs/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    bfl_mod.addImport("provider", provider_mod);
    bfl_mod.addImport("provider-utils", provider_utils_mod);

    // LMNT provider
    const lmnt_mod = b.addModule("lmnt", .{
        .root_source_file = b.path("packages/lmnt/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    lmnt_mod.addImport("provider", provider_mod);
    lmnt_mod.addImport("provider-utils", provider_utils_mod);

    // Hume provider
    const hume_mod = b.addModule("hume", .{
        .root_source_file = b.path("packages/hume/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    hume_mod.addImport("provider", provider_mod);
    hume_mod.addImport("provider-utils", provider_utils_mod);

    // AssemblyAI provider
    const assemblyai_mod = b.addModule("assemblyai", .{
        .root_source_file = b.path("packages/assemblyai/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    assemblyai_mod.addImport("provider", provider_mod);
    assemblyai_mod.addImport("provider-utils", provider_utils_mod);

    // Deepgram provider
    const deepgram_mod = b.addModule("deepgram", .{
        .root_source_file = b.path("packages/deepgram/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    deepgram_mod.addImport("provider", provider_mod);
    deepgram_mod.addImport("provider-utils", provider_utils_mod);

    // Gladia provider
    const gladia_mod = b.addModule("gladia", .{
        .root_source_file = b.path("packages/gladia/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    gladia_mod.addImport("provider", provider_mod);
    gladia_mod.addImport("provider-utils", provider_utils_mod);

    // Rev AI provider
    const revai_mod = b.addModule("revai", .{
        .root_source_file = b.path("packages/revai/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    revai_mod.addImport("provider", provider_mod);
    revai_mod.addImport("provider-utils", provider_utils_mod);

    // Test step
    const test_step = b.step("test", "Run unit tests");

    // Provider tests
    const provider_tests = b.addTest(.{
        .root_source_file = b.path("packages/provider/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(provider_tests).step);

    // AI package tests
    const ai_tests = b.addTest(.{
        .root_source_file = b.path("packages/ai/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    ai_tests.root_module.addImport("provider", provider_mod);
    test_step.dependOn(&b.addRunArtifact(ai_tests).step);

    // OpenAI tests
    const openai_tests = b.addTest(.{
        .root_source_file = b.path("packages/openai/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    openai_tests.root_module.addImport("provider", provider_mod);
    openai_tests.root_module.addImport("provider-utils", provider_utils_mod);
    test_step.dependOn(&b.addRunArtifact(openai_tests).step);

    // Anthropic tests
    const anthropic_tests = b.addTest(.{
        .root_source_file = b.path("packages/anthropic/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    anthropic_tests.root_module.addImport("provider", provider_mod);
    anthropic_tests.root_module.addImport("provider-utils", provider_utils_mod);
    test_step.dependOn(&b.addRunArtifact(anthropic_tests).step);

    // xAI tests
    const xai_tests = b.addTest(.{
        .root_source_file = b.path("packages/xai/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    xai_tests.root_module.addImport("provider", provider_mod);
    xai_tests.root_module.addImport("provider-utils", provider_utils_mod);
    xai_tests.root_module.addImport("openai-compatible", openai_compatible_mod);
    test_step.dependOn(&b.addRunArtifact(xai_tests).step);

    // Perplexity tests
    const perplexity_tests = b.addTest(.{
        .root_source_file = b.path("packages/perplexity/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    perplexity_tests.root_module.addImport("provider", provider_mod);
    perplexity_tests.root_module.addImport("provider-utils", provider_utils_mod);
    perplexity_tests.root_module.addImport("openai-compatible", openai_compatible_mod);
    test_step.dependOn(&b.addRunArtifact(perplexity_tests).step);

    // Fireworks tests
    const fireworks_tests = b.addTest(.{
        .root_source_file = b.path("packages/fireworks/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    fireworks_tests.root_module.addImport("provider", provider_mod);
    fireworks_tests.root_module.addImport("provider-utils", provider_utils_mod);
    fireworks_tests.root_module.addImport("openai-compatible", openai_compatible_mod);
    test_step.dependOn(&b.addRunArtifact(fireworks_tests).step);

    // HuggingFace tests
    const huggingface_tests = b.addTest(.{
        .root_source_file = b.path("packages/huggingface/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    huggingface_tests.root_module.addImport("provider", provider_mod);
    huggingface_tests.root_module.addImport("provider-utils", provider_utils_mod);
    huggingface_tests.root_module.addImport("openai-compatible", openai_compatible_mod);
    test_step.dependOn(&b.addRunArtifact(huggingface_tests).step);

    // ElevenLabs tests
    const elevenlabs_tests = b.addTest(.{
        .root_source_file = b.path("packages/elevenlabs/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    elevenlabs_tests.root_module.addImport("provider", provider_mod);
    elevenlabs_tests.root_module.addImport("provider-utils", provider_utils_mod);
    test_step.dependOn(&b.addRunArtifact(elevenlabs_tests).step);

    // Deepgram tests
    const deepgram_tests = b.addTest(.{
        .root_source_file = b.path("packages/deepgram/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    deepgram_tests.root_module.addImport("provider", provider_mod);
    deepgram_tests.root_module.addImport("provider-utils", provider_utils_mod);
    test_step.dependOn(&b.addRunArtifact(deepgram_tests).step);


    // Cerebras tests
    const cerebras_tests = b.addTest(.{
        .root_source_file = b.path("packages/cerebras/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    cerebras_tests.root_module.addImport("provider", provider_mod);
    cerebras_tests.root_module.addImport("provider-utils", provider_utils_mod);
    cerebras_tests.root_module.addImport("openai-compatible", openai_compatible_mod);
    test_step.dependOn(&b.addRunArtifact(cerebras_tests).step);
    // DeepInfra tests
    const deepinfra_tests = b.addTest(.{
        .root_source_file = b.path("packages/deepinfra/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    deepinfra_tests.root_module.addImport("provider", provider_mod);
    deepinfra_tests.root_module.addImport("provider-utils", provider_utils_mod);
    deepinfra_tests.root_module.addImport("openai-compatible", openai_compatible_mod);
    test_step.dependOn(&b.addRunArtifact(deepinfra_tests).step);

    // Replicate tests
    const replicate_tests = b.addTest(.{
        .root_source_file = b.path("packages/replicate/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    replicate_tests.root_module.addImport("provider", provider_mod);
    replicate_tests.root_module.addImport("provider-utils", provider_utils_mod);
    test_step.dependOn(&b.addRunArtifact(replicate_tests).step);

    // Example executable
    const example = b.addExecutable(.{
        .name = "ai-example",
        .root_source_file = b.path("examples/simple.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("ai", ai_mod);
    example.root_module.addImport("openai", openai_mod);

    const run_example = b.addRunArtifact(example);
    const run_step = b.step("run-example", "Run the example");
    run_step.dependOn(&run_example.step);

    b.installArtifact(example);
}
