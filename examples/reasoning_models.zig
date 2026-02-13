// Reasoning Models Example
//
// This example demonstrates how to use reasoning/thinking models
// with the Zig AI SDK. These models perform extended internal reasoning
// before generating their final responses.

const std = @import("std");
const ai = @import("ai");
const openai = @import("openai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Reasoning Models Example\n", .{});
    std.debug.print("========================\n\n", .{});

    // Create providers (not used for actual calls, just for demonstration)
    var openai_provider = openai.createOpenAI(allocator);
    defer openai_provider.deinit();

    // Example 1: What are Reasoning Models?
    std.debug.print("1. What are Reasoning Models?\n", .{});
    std.debug.print("------------------------------\n", .{});
    std.debug.print("Reasoning models perform extended internal 'thinking' before responding.\n", .{});
    std.debug.print("They generate reasoning tokens that help them work through complex problems,\n", .{});
    std.debug.print("then produce a final answer based on that reasoning process.\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Key characteristics:\n", .{});
    std.debug.print("  - Generate internal reasoning/thinking tokens\n", .{});
    std.debug.print("  - Reasoning is separate from the final response\n", .{});
    std.debug.print("  - Better at complex problem-solving and math\n", .{});
    std.debug.print("  - Can show their 'work' via reasoning text\n", .{});
    std.debug.print("\n", .{});

    // Example 2: Available Reasoning Models
    std.debug.print("2. Available Reasoning Models\n", .{});
    std.debug.print("------------------------------\n", .{});
    std.debug.print("OpenAI:\n", .{});
    std.debug.print("  - o1 series: o1, o1-2024-12-17\n", .{});
    std.debug.print("  - o3 series: o3, o3-mini, o3-2025-04-16, o3-mini-2025-01-31\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("DeepSeek:\n", .{});
    std.debug.print("  - deepseek-reasoner: Full reasoning model\n", .{});
    std.debug.print("  - deepseek-chat: Standard chat (non-reasoning)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Groq (via model hosting):\n", .{});
    std.debug.print("  - deepseek-r1-distill-llama-70b: DeepSeek R1 distilled to Llama\n", .{});
    std.debug.print("  - deepseek-r1-distill-qwen-32b: DeepSeek R1 distilled to Qwen\n", .{});
    std.debug.print("  - qwen-qwq-32b: Qwen's reasoning model (QwQ)\n", .{});
    std.debug.print("\n", .{});

    // Example 3: Using OpenAI o1/o3 Models
    std.debug.print("3. Using OpenAI o1/o3 Models\n", .{});
    std.debug.print("-----------------------------\n", .{});
    std.debug.print("OpenAI's reasoning models automatically generate reasoning tokens:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var provider = openai.createOpenAI(allocator);\n", .{});
    std.debug.print("  defer provider.deinit();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var model = provider.languageModel(\"o3-mini\");\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const result = try ai.generateText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"Solve: If x + 5 = 12, what is x?\",\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("  defer result.deinit();\n", .{});
    std.debug.print("\n", .{});

    // Example 4: Accessing Reasoning Text
    std.debug.print("6. Accessing Reasoning Text\n", .{});
    std.debug.print("----------------------------\n", .{});
    std.debug.print("After generation, you can access the reasoning process:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const result = try ai.generateText(allocator, .{{ ... }});\n", .{});
    std.debug.print("  defer result.deinit();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Get the final response\n", .{});
    std.debug.print("  const response = result.text;\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Get the reasoning/thinking tokens (may be null)\n", .{});
    std.debug.print("  if (result.reasoning_text) |reasoning| {{\n", .{});
    std.debug.print("      std.debug.print(\"Reasoning:\\n{{s}}\\n\", .{{reasoning}});\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Check token usage\n", .{});
    std.debug.print("  std.debug.print(\"Reasoning tokens: {{d}}\\n\", .{{result.usage.reasoning_tokens}});\n", .{});
    std.debug.print("  std.debug.print(\"Completion tokens: {{d}}\\n\", .{{result.usage.completion_tokens}});\n", .{});
    std.debug.print("\n", .{});

    // Example 7: Streaming Reasoning Deltas
    std.debug.print("7. Streaming Reasoning Deltas\n", .{});
    std.debug.print("------------------------------\n", .{});
    std.debug.print("When streaming, reasoning tokens arrive as reasoning_delta events:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  fn onStreamPart(part: ai.StreamPart, ctx: ?*anyopaque) void {{\n", .{});
    std.debug.print("      _ = ctx;\n", .{});
    std.debug.print("      switch (part) {{\n", .{});
    std.debug.print("          .reasoning_delta => |delta| {{\n", .{});
    std.debug.print("              // Handle reasoning tokens as they stream\n", .{});
    std.debug.print("              std.debug.print(\"[Thinking: {{s}}]\", .{{delta.text}});\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("          .text_delta => |delta| {{\n", .{});
    std.debug.print("              // Handle final response tokens\n", .{});
    std.debug.print("              std.debug.print(\"{{s}}\", .{{delta.text}});\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("          .finish => |finish| {{\n", .{});
    std.debug.print("              std.debug.print(\"\\nDone: {{s}}\\n\", .{{@tagName(finish.finish_reason)}});\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("          else => {{}},\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const callbacks = ai.StreamCallbacks{{\n", .{});
    std.debug.print("      .on_part = onStreamPart,\n", .{});
    std.debug.print("      .on_error = onStreamError,\n", .{});
    std.debug.print("      .on_complete = onStreamComplete,\n", .{});
    std.debug.print("      .context = null,\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var result = try ai.streamText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"Complex problem...\",\n", .{});
    std.debug.print("      .callbacks = callbacks,\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("\n", .{});

    // Example 8: Simulated Reasoning Flow
    std.debug.print("8. Simulated Reasoning Flow\n", .{});
    std.debug.print("----------------------------\n", .{});
    std.debug.print("Here's what a reasoning model's output might look like:\n", .{});
    std.debug.print("\n", .{});

    // Simulate reasoning tokens
    const reasoning = "Let me think through this step by step...\n1. The user is asking about x + 5 = 12\n2. To solve for x, I need to isolate it\n3. Subtracting 5 from both sides: x = 12 - 5\n4. Therefore x = 7";
    std.debug.print("[REASONING]\n{s}\n\n", .{reasoning});

    // Simulate response tokens
    const response = "To solve x + 5 = 12, I'll subtract 5 from both sides:\n\nx + 5 - 5 = 12 - 5\nx = 7\n\nThe answer is x = 7.";
    std.debug.print("[RESPONSE]\n{s}\n\n", .{response});

    // Example 9: Checking Reasoning Support
    std.debug.print("9. Checking Reasoning Support\n", .{});
    std.debug.print("------------------------------\n", .{});
    std.debug.print("You can check if a model supports reasoning:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // OpenAI models\n", .{});
    std.debug.print("  const is_reasoning_openai = openai.isReasoningModel(\"o3-mini\");\n", .{});
    std.debug.print("  // Returns: true for o1/o3 series\n", .{});
    std.debug.print("\n", .{});
    // Demonstrate the actual functions
    std.debug.print("Testing reasoning detection:\n", .{});
    std.debug.print("  openai.isReasoningModel(\"o3-mini\"): {}\n", .{openai.isReasoningModel("o3-mini")});
    std.debug.print("  openai.isReasoningModel(\"gpt-4o\"): {}\n", .{openai.isReasoningModel("gpt-4o")});
    std.debug.print("\n", .{});

    // Example 10: Best Practices
    std.debug.print("10. Best Practices for Reasoning Models\n", .{});
    std.debug.print("----------------------------------------\n", .{});
    std.debug.print("  - Use reasoning models for complex problems (math, logic, analysis)\n", .{});
    std.debug.print("  - Regular models may be better for simple chat/generation\n", .{});
    std.debug.print("  - Reasoning tokens count toward token usage and cost\n", .{});
    std.debug.print("  - Stream reasoning_delta to show thinking progress to users\n", .{});
    std.debug.print("  - Check reasoning_text in results to understand the model's process\n", .{});
    std.debug.print("  - Use .hidden reasoning format if you don't need to see the thinking\n", .{});
    std.debug.print("  - Adjust reasoning_effort based on problem complexity\n", .{});
    std.debug.print("  - Consider reasoning token usage when estimating costs\n", .{});
    std.debug.print("\n", .{});

    // Example 11: Use Cases
    std.debug.print("11. Ideal Use Cases\n", .{});
    std.debug.print("-------------------\n", .{});
    std.debug.print("Reasoning models excel at:\n", .{});
    std.debug.print("  - Complex mathematical problems\n", .{});
    std.debug.print("  - Logic puzzles and reasoning tasks\n", .{});
    std.debug.print("  - Code debugging and analysis\n", .{});
    std.debug.print("  - Multi-step problem solving\n", .{});
    std.debug.print("  - Scientific explanations\n", .{});
    std.debug.print("  - Competitive programming\n", .{});
    std.debug.print("  - Theorem proving\n", .{});
    std.debug.print("  - Complex data analysis\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Regular models are better for:\n", .{});
    std.debug.print("  - Simple chat conversations\n", .{});
    std.debug.print("  - Creative writing\n", .{});
    std.debug.print("  - Quick factual questions\n", .{});
    std.debug.print("  - Content generation\n", .{});
    std.debug.print("  - Translation tasks\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example complete!\n", .{});
}
