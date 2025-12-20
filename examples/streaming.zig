// Streaming Text Generation Example
//
// This example demonstrates how to use callback-based streaming
// for real-time text generation with the Zig AI SDK.

const std = @import("std");
const ai = @import("ai");
const openai = @import("openai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Streaming Text Generation Example\n", .{});
    std.debug.print("==================================\n\n", .{});

    // Create OpenAI provider
    var provider = openai.createOpenAI(allocator);
    defer provider.deinit();

    // Get a language model
    var model = provider.languageModel("gpt-4o");
    std.debug.print("Using model: {s}\n\n", .{model.getModelId()});

    // Example 1: Define streaming callbacks
    std.debug.print("1. Streaming Callbacks\n", .{});
    std.debug.print("-----------------------\n", .{});
    std.debug.print("Define callbacks to handle streaming events:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const callbacks = ai.StreamCallbacks{{\n", .{});
    std.debug.print("      .on_part = onStreamPart,\n", .{});
    std.debug.print("      .on_error = onStreamError,\n", .{});
    std.debug.print("      .on_complete = onStreamComplete,\n", .{});
    std.debug.print("      .context = null,  // Optional user context\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // Example 2: Stream part types
    std.debug.print("2. Stream Part Types\n", .{});
    std.debug.print("---------------------\n", .{});
    std.debug.print("The on_part callback receives different event types:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  .text_delta          - Incremental text chunks\n", .{});
    std.debug.print("  .reasoning_delta     - Reasoning tokens (for reasoning models)\n", .{});
    std.debug.print("  .tool_call_start     - Tool call initiated\n", .{});
    std.debug.print("  .tool_call_delta     - Tool call arguments streaming\n", .{});
    std.debug.print("  .tool_call_complete  - Tool call finished\n", .{});
    std.debug.print("  .tool_result         - Tool execution result\n", .{});
    std.debug.print("  .step_finish         - Step completed (in multi-step)\n", .{});
    std.debug.print("  .finish              - Stream finished\n", .{});
    std.debug.print("  .error               - Error occurred\n", .{});
    std.debug.print("\n", .{});

    // Example 3: Starting a stream
    std.debug.print("3. Starting a Stream\n", .{});
    std.debug.print("---------------------\n", .{});
    std.debug.print("Call streamText with callbacks:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var result = try ai.streamText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"Write a haiku about programming.\",\n", .{});
    std.debug.print("      .callbacks = callbacks,\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("  defer result.deinit();\n", .{});
    std.debug.print("\n", .{});

    // Example 4: Handling text deltas
    std.debug.print("4. Handling Text Deltas\n", .{});
    std.debug.print("------------------------\n", .{});
    std.debug.print("Process text as it streams:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  fn onStreamPart(part: ai.StreamPart, ctx: ?*anyopaque) void {{\n", .{});
    std.debug.print("      _ = ctx;\n", .{});
    std.debug.print("      switch (part) {{\n", .{});
    std.debug.print("          .text_delta => |delta| {{\n", .{});
    std.debug.print("              std.debug.print(\"{{s}}\", .{{delta.text}});\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("          .finish => |finish| {{\n", .{});
    std.debug.print("              std.debug.print(\"\\nDone: {{s}}\\n\", .{{@tagName(finish.finish_reason)}});\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("          else => {{}},\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // Example 5: Simulated streaming output
    std.debug.print("5. Simulated Streaming Output\n", .{});
    std.debug.print("------------------------------\n", .{});
    std.debug.print("Here's what streaming looks like (simulated):\n", .{});
    std.debug.print("\n", .{});

    // Simulate streaming output
    const simulated_text = "Code flows like water,\nBugs scatter in the moonlight,\nZig compiles at dawn.";
    for (simulated_text) |char| {
        std.debug.print("{c}", .{char});
        std.Thread.sleep(20 * std.time.ns_per_ms); // 20ms delay per character
    }
    std.debug.print("\n\n", .{});

    // Example 6: Accessing final result
    std.debug.print("6. Accessing Final Result\n", .{});
    std.debug.print("--------------------------\n", .{});
    std.debug.print("After streaming, access accumulated data:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const full_text = result.getText();\n", .{});
    std.debug.print("  const reasoning = result.getReasoningText();  // For reasoning models\n", .{});
    std.debug.print("  const usage = result.total_usage;\n", .{});
    std.debug.print("  const finish_reason = result.finish_reason;\n", .{});
    std.debug.print("\n", .{});

    // Example 7: Streaming with tools
    std.debug.print("7. Streaming with Tools\n", .{});
    std.debug.print("------------------------\n", .{});
    std.debug.print("Tools work with streaming too:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var result = try ai.streamText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"What's the weather?\",\n", .{});
    std.debug.print("      .tools = &tools,\n", .{});
    std.debug.print("      .max_steps = 5,\n", .{});
    std.debug.print("      .callbacks = callbacks,\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("\n", .{});

    // Example 8: Best practices
    std.debug.print("8. Best Practices\n", .{});
    std.debug.print("------------------\n", .{});
    std.debug.print("  - Use streaming for long responses\n", .{});
    std.debug.print("  - Show progress indicators in the callback\n", .{});
    std.debug.print("  - Handle errors gracefully in on_error\n", .{});
    std.debug.print("  - Always clean up with result.deinit()\n", .{});
    std.debug.print("  - Use context to pass state to callbacks\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example complete!\n", .{});
}
