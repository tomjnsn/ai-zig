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
    google_vertex_mod.addImport("google", google_mod);

    // Azure provider
    const azure_mod = b.addModule("azure", .{
        .root_source_file = b.path("packages/azure/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    azure_mod.addImport("provider", provider_mod);
    azure_mod.addImport("provider-utils", provider_utils_mod);
    azure_mod.addImport("openai", openai_mod);

    // OpenAI Compatible provider (base for xAI, Perplexity, etc.)
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
    togetherai_mod.addImport("openai-compatible", openai_compatible_mod);

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

    // HuggingFace provider
    const huggingface_mod = b.addModule("huggingface", .{
        .root_source_file = b.path("packages/huggingface/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    huggingface_mod.addImport("provider", provider_mod);
    huggingface_mod.addImport("provider-utils", provider_utils_mod);
    huggingface_mod.addImport("openai-compatible", openai_compatible_mod);

    // Test step
    const test_step = b.step("test", "Run unit tests");

    // Helper function to create test with modules
    const TestConfig = struct {
        path: []const u8,
        imports: []const struct { name: []const u8, mod: *std.Build.Module },
    };

    const test_configs = [_]TestConfig{
        .{ .path = "packages/provider/src/index.zig", .imports = &.{} },
        .{ .path = "packages/provider-utils/src/index.zig", .imports = &.{.{ .name = "provider", .mod = provider_mod }} },
        .{ .path = "packages/ai/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod } } },
        .{ .path = "packages/openai/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod } } },
        .{ .path = "packages/anthropic/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod } } },
        .{ .path = "packages/google/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod } } },
        .{ .path = "packages/google-vertex/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod }, .{ .name = "google", .mod = google_mod } } },
        .{ .path = "packages/openai-compatible/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod } } },
        .{ .path = "packages/xai/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod }, .{ .name = "openai-compatible", .mod = openai_compatible_mod } } },
        .{ .path = "packages/perplexity/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod }, .{ .name = "openai-compatible", .mod = openai_compatible_mod } } },
        .{ .path = "packages/togetherai/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod }, .{ .name = "openai-compatible", .mod = openai_compatible_mod } } },
        .{ .path = "packages/fireworks/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod }, .{ .name = "openai-compatible", .mod = openai_compatible_mod } } },
        .{ .path = "packages/cerebras/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod }, .{ .name = "openai-compatible", .mod = openai_compatible_mod } } },
        .{ .path = "packages/deepinfra/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod }, .{ .name = "openai-compatible", .mod = openai_compatible_mod } } },
        .{ .path = "packages/huggingface/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod }, .{ .name = "openai-compatible", .mod = openai_compatible_mod } } },
        .{ .path = "packages/azure/src/index.zig", .imports = &.{ .{ .name = "provider", .mod = provider_mod }, .{ .name = "provider-utils", .mod = provider_utils_mod }, .{ .name = "openai", .mod = openai_mod } } },
        // Integration tests
        .{ .path = "tests/integration/provider_test.zig", .imports = &.{
            .{ .name = "provider", .mod = provider_mod },
            .{ .name = "provider-utils", .mod = provider_utils_mod },
            .{ .name = "ai", .mod = ai_mod },
            .{ .name = "openai", .mod = openai_mod },
            .{ .name = "anthropic", .mod = anthropic_mod },
            .{ .name = "google", .mod = google_mod },
            .{ .name = "azure", .mod = azure_mod },
            .{ .name = "xai", .mod = xai_mod },
            .{ .name = "perplexity", .mod = perplexity_mod },
            .{ .name = "togetherai", .mod = togetherai_mod },
            .{ .name = "fireworks", .mod = fireworks_mod },
            .{ .name = "cerebras", .mod = cerebras_mod },
            .{ .name = "huggingface", .mod = huggingface_mod },
            .{ .name = "deepinfra", .mod = deepinfra_mod },
        } },
        .{ .path = "tests/integration/similarity_test.zig", .imports = &.{
            .{ .name = "ai", .mod = ai_mod },
        } },
        .{ .path = "tests/integration/tool_test.zig", .imports = &.{
            .{ .name = "ai", .mod = ai_mod },
        } },
    };

    for (test_configs) |config| {
        const tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(config.path),
                .target = target,
                .optimize = optimize,
            }),
            .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
        });
        for (config.imports) |imp| {
            tests.root_module.addImport(imp.name, imp.mod);
        }
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }

    // Live provider integration tests (requires API keys)
    const test_live_step = b.step("test-live", "Run live provider integration tests (requires API keys)");
    const live_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/live_provider_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    live_tests.root_module.addImport("ai", ai_mod);
    live_tests.root_module.addImport("provider", provider_mod);
    live_tests.root_module.addImport("provider-utils", provider_utils_mod);
    live_tests.root_module.addImport("openai", openai_mod);
    live_tests.root_module.addImport("azure", azure_mod);
    live_tests.root_module.addImport("anthropic", anthropic_mod);
    live_tests.root_module.addImport("google", google_mod);
    live_tests.root_module.addImport("xai", xai_mod);
    live_tests.root_module.addImport("openai-compatible", openai_compatible_mod);
    test_live_step.dependOn(&b.addRunArtifact(live_tests).step);

    // Example executable
    const example = b.addExecutable(.{
        .name = "ai-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/simple.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    example.root_module.addImport("ai", ai_mod);
    example.root_module.addImport("openai", openai_mod);

    const run_example = b.addRunArtifact(example);
    const run_step = b.step("run-example", "Run the example");
    run_step.dependOn(&run_example.step);

    b.installArtifact(example);

    // Image generation example
    const image_gen_example = b.addExecutable(.{
        .name = "image-generation-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/image_generation.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    image_gen_example.root_module.addImport("ai", ai_mod);
    image_gen_example.root_module.addImport("openai", openai_mod);

    const run_image_gen_example = b.addRunArtifact(image_gen_example);
    const run_image_gen_step = b.step("run-image-generation", "Run the image generation example");
    run_image_gen_step.dependOn(&run_image_gen_example.step);

    b.installArtifact(image_gen_example);
}
