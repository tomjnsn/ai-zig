// Multi-Provider Example
//
// This example demonstrates how to use different AI providers
// with the Zig AI SDK. You can easily switch between providers
// while keeping the same high-level API.

const std = @import("std");
const ai = @import("ai");
const openai = @import("openai");
const anthropic = @import("anthropic");
const google = @import("google");
const groq = @import("groq");

/// Provider configuration
const ProviderInfo = struct {
    name: []const u8,
    model_id: []const u8,
    description: []const u8,
};

/// List of providers we'll demonstrate
const providers_info = [_]ProviderInfo{
    .{
        .name = "OpenAI",
        .model_id = "gpt-4o",
        .description = "GPT-4o - OpenAI's flagship multimodal model",
    },
    .{
        .name = "Anthropic",
        .model_id = "claude-sonnet-4-5",
        .description = "Claude Sonnet 4.5 - Anthropic's balanced model",
    },
    .{
        .name = "Google",
        .model_id = "gemini-2.0-flash",
        .description = "Gemini 2.0 Flash - Google's fast model",
    },
    .{
        .name = "Groq",
        .model_id = "llama-3.3-70b-versatile",
        .description = "Llama 3.3 70B - Fast inference on Groq",
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Multi-Provider Example\n", .{});
    std.debug.print("======================\n\n", .{});

    std.debug.print("Available providers:\n", .{});
    for (providers_info, 0..) |info, i| {
        std.debug.print("  {d}. {s} ({s})\n", .{ i + 1, info.name, info.model_id });
        std.debug.print("     {s}\n", .{info.description});
    }
    std.debug.print("\n", .{});

    // Demonstrate each provider
    const prompt = "What is 2 + 2? Reply with just the number.";

    // OpenAI
    std.debug.print("Using OpenAI (gpt-4o):\n", .{});
    std.debug.print("-----------------------\n", .{});
    {
        var provider = openai.createOpenAI(allocator);
        defer provider.deinit();

        var model = provider.languageModel("gpt-4o");
        std.debug.print("Provider: {s}\n", .{provider.getProvider()});
        std.debug.print("Model: {s}\n", .{model.getModelId()});
        std.debug.print("Prompt: {s}\n", .{prompt});

        // In a real scenario, you would call generateText or streamText here
        // const result = try ai.generateText(allocator, .{
        //     .model = &model,
        //     .prompt = prompt,
        // });
        // std.debug.print("Response: {s}\n", .{result.text});
    }
    std.debug.print("\n", .{});

    // Anthropic
    std.debug.print("Using Anthropic (claude-sonnet-4-5):\n", .{});
    std.debug.print("-------------------------------------\n", .{});
    {
        var provider = anthropic.createAnthropic(allocator);
        defer provider.deinit();

        var model = provider.languageModel("claude-sonnet-4-5");
        std.debug.print("Provider: {s}\n", .{provider.getProvider()});
        std.debug.print("Model: {s}\n", .{model.getModelId()});
        std.debug.print("Prompt: {s}\n", .{prompt});
    }
    std.debug.print("\n", .{});

    // Google
    std.debug.print("Using Google (gemini-2.0-flash):\n", .{});
    std.debug.print("---------------------------------\n", .{});
    {
        var provider = google.createGoogleGenerativeAI(allocator);
        defer provider.deinit();

        var model = provider.languageModel("gemini-2.0-flash");
        std.debug.print("Provider: {s}\n", .{provider.getProvider()});
        std.debug.print("Model: {s}\n", .{model.getModelId()});
        std.debug.print("Prompt: {s}\n", .{prompt});
    }
    std.debug.print("\n", .{});

    // Groq (fast inference)
    std.debug.print("Using Groq (llama-3.3-70b-versatile):\n", .{});
    std.debug.print("--------------------------------------\n", .{});
    {
        var provider = groq.createGroq(allocator);
        defer provider.deinit();

        var model = provider.languageModel("llama-3.3-70b-versatile");
        std.debug.print("Provider: {s}\n", .{provider.getProvider()});
        std.debug.print("Model: {s}\n", .{model.getModelId()});
        std.debug.print("Prompt: {s}\n", .{prompt});
    }
    std.debug.print("\n", .{});

    // Provider comparison
    std.debug.print("Provider Comparison:\n", .{});
    std.debug.print("====================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("| Provider   | Best For                              |\n", .{});
    std.debug.print("|------------|---------------------------------------|\n", .{});
    std.debug.print("| OpenAI     | General purpose, vision, audio        |\n", .{});
    std.debug.print("| Anthropic  | Long context, coding, analysis        |\n", .{});
    std.debug.print("| Google     | Multimodal, large context windows     |\n", .{});
    std.debug.print("| Groq       | Ultra-fast inference, open models     |\n", .{});
    std.debug.print("| DeepSeek   | Reasoning, coding, cost-effective     |\n", .{});
    std.debug.print("| Mistral    | European hosting, efficient models    |\n", .{});
    std.debug.print("| Together   | Open source models, fine-tuning       |\n", .{});
    std.debug.print("| Fireworks  | Fast inference, serverless            |\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example complete!\n", .{});
}
