// Conversation Example
//
// This example demonstrates how to build multi-turn conversations
// with the Zig AI SDK, including system prompts and message history.

const std = @import("std");
const ai = @import("ai");
const openai = @import("openai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Conversation Example\n", .{});
    std.debug.print("====================\n\n", .{});

    // Create OpenAI provider
    var provider = openai.createOpenAI(allocator);
    defer provider.deinit();

    var model = provider.languageModel("gpt-4o");
    std.debug.print("Using model: {s}\n\n", .{model.getModelId()});

    // Example 1: System prompt
    std.debug.print("1. System Prompts\n", .{});
    std.debug.print("------------------\n", .{});
    std.debug.print("System prompts set the behavior and context for the AI:\n", .{});
    std.debug.print("\n", .{});

    const system_prompt =
        \\You are a helpful programming assistant specializing in Zig.
        \\You provide concise, accurate answers about Zig syntax,
        \\memory management, and best practices.
    ;

    std.debug.print("System: {s}\n", .{system_prompt});
    std.debug.print("\n", .{});

    // Example 2: Building message history
    std.debug.print("2. Message History Structure\n", .{});
    std.debug.print("-----------------------------\n", .{});
    std.debug.print("Messages are structured with roles and content:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const messages = [_]ai.Message{{\n", .{});
    std.debug.print("      .{{ .role = .system, .content = .{{ .text = system_prompt }} }},\n", .{});
    std.debug.print("      .{{ .role = .user, .content = .{{ .text = \"What is an arena allocator?\" }} }},\n", .{});
    std.debug.print("      .{{ .role = .assistant, .content = .{{ .text = \"An arena allocator...\" }} }},\n", .{});
    std.debug.print("      .{{ .role = .user, .content = .{{ .text = \"Show me an example?\" }} }},\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // Show conversation flow
    std.debug.print("Example conversation flow:\n", .{});
    std.debug.print("  [System]: You are a helpful programming assistant...\n", .{});
    std.debug.print("  [User]: What is an arena allocator in Zig?\n", .{});
    std.debug.print("  [Assistant]: An arena allocator in Zig is a memory allocation...\n", .{});
    std.debug.print("  [User]: Can you show me an example?\n", .{});
    std.debug.print("\n", .{});

    // Example 3: Making a request with history
    std.debug.print("3. Request with Message History\n", .{});
    std.debug.print("--------------------------------\n", .{});
    std.debug.print("To continue the conversation, pass the message history:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const result = try ai.generateText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .messages = &messages,  // Include history\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("\n", .{});

    // Example 4: Different message content types
    std.debug.print("4. Message Content Types\n", .{});
    std.debug.print("-------------------------\n", .{});
    std.debug.print("Messages can contain different types of content:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  .text        - Plain text messages\n", .{});
    std.debug.print("  .parts       - Multiple content parts (text + images)\n", .{});
    std.debug.print("  .tool_calls  - Tool/function call by assistant\n", .{});
    std.debug.print("  .tool_result - Result from tool execution\n", .{});
    std.debug.print("\n", .{});

    // Example 5: Conversation with tool calls
    std.debug.print("5. Conversation with Tool Calls\n", .{});
    std.debug.print("--------------------------------\n", .{});
    std.debug.print("When tools are involved, the message flow looks like:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  1. [User]: \"What's the weather in Tokyo?\"\n", .{});
    std.debug.print("  2. [Assistant]: (tool_call: get_weather, args: {{location: 'Tokyo'}})\n", .{});
    std.debug.print("  3. [Tool]: (tool_result: {{temperature: 22, conditions: 'Sunny'}})\n", .{});
    std.debug.print("  4. [Assistant]: \"The weather in Tokyo is 22C and sunny.\"\n", .{});
    std.debug.print("\n", .{});

    // Example 6: Message roles
    std.debug.print("6. Message Roles\n", .{});
    std.debug.print("-----------------\n", .{});
    std.debug.print("Available message roles:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  .system    - Instructions for the model's behavior\n", .{});
    std.debug.print("  .user      - Messages from the user\n", .{});
    std.debug.print("  .assistant - Responses from the AI\n", .{});
    std.debug.print("  .tool      - Results from tool execution\n", .{});
    std.debug.print("\n", .{});

    // Example 7: Best practices
    std.debug.print("7. Conversation Best Practices\n", .{});
    std.debug.print("-------------------------------\n", .{});
    std.debug.print("  - Keep system prompts concise but specific\n", .{});
    std.debug.print("  - Trim old messages to stay within token limits\n", .{});
    std.debug.print("  - Summarize long conversations periodically\n", .{});
    std.debug.print("  - Use clear role separation (user/assistant)\n", .{});
    std.debug.print("  - Handle tool calls in the message flow\n", .{});
    std.debug.print("  - Consider using arena allocators for message storage\n", .{});
    std.debug.print("\n", .{});

    // Example 8: Dynamic conversation building
    std.debug.print("8. Dynamic Conversation Building\n", .{});
    std.debug.print("---------------------------------\n", .{});
    std.debug.print("For dynamic conversations, use an ArrayList:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var messages = std.ArrayListUnmanaged(ai.Message){{}};\n", .{});
    std.debug.print("  defer messages.deinit(allocator);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  try messages.append(allocator, .{{\n", .{});
    std.debug.print("      .role = .user,\n", .{});
    std.debug.print("      .content = .{{ .text = user_input }},\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example complete!\n", .{});
}
