// Timeout and Cancellation Example
//
// This example demonstrates how to use RequestContext for
// timeout and cancellation support in AI SDK requests.

const std = @import("std");
const ai = @import("ai");

pub fn main() !void {
    std.debug.print("Timeout and Cancellation Example\n", .{});
    std.debug.print("=================================\n\n", .{});

    // Example 1: Using RequestContext for timeouts
    std.debug.print("1. RequestContext with Timeout\n", .{});
    std.debug.print("------------------------------\n", .{});
    std.debug.print("Set a timeout on any API call:\n\n", .{});
    std.debug.print("  var ctx = ai.RequestContext.init(allocator);\n", .{});
    std.debug.print("  defer ctx.deinit();\n", .{});
    std.debug.print("  ctx.withTimeout(30_000); // 30 second timeout\n\n", .{});
    std.debug.print("  const result = try ai.generateText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"Hello!\",\n", .{});
    std.debug.print("      .request_context = &ctx,\n", .{});
    std.debug.print("  }});\n\n", .{});

    // Example 2: Cancellation from another thread
    std.debug.print("2. Cancellation\n", .{});
    std.debug.print("----------------\n", .{});
    std.debug.print("Cancel a request from another thread:\n\n", .{});
    std.debug.print("  var ctx = ai.RequestContext.init(allocator);\n", .{});
    std.debug.print("  defer ctx.deinit();\n\n", .{});
    std.debug.print("  // In another thread:\n", .{});
    std.debug.print("  ctx.cancel(); // Thread-safe atomic operation\n\n", .{});
    std.debug.print("  // In the main thread, the SDK checks ctx.isDone()\n", .{});
    std.debug.print("  // and returns error.Cancelled if cancelled or expired.\n\n", .{});

    // Example 3: Metadata storage
    std.debug.print("3. Request Metadata\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("Store metadata for logging or tracing:\n\n", .{});
    std.debug.print("  var ctx = ai.RequestContext.init(allocator);\n", .{});
    std.debug.print("  defer ctx.deinit();\n", .{});
    std.debug.print("  try ctx.setMetadata(\"request_id\", \"req-abc123\");\n", .{});
    std.debug.print("  try ctx.setMetadata(\"user\", \"user-456\");\n\n", .{});
    std.debug.print("  // Later, retrieve metadata:\n", .{});
    std.debug.print("  const req_id = ctx.getMetadata(\"request_id\"); // \"req-abc123\"\n\n", .{});

    // Example 4: Checking status
    std.debug.print("4. Status Checking\n", .{});
    std.debug.print("-------------------\n", .{});
    std.debug.print("Check request status at any point:\n\n", .{});
    std.debug.print("  if (ctx.isDone()) {{  // true if cancelled or expired\n", .{});
    std.debug.print("      return error.Cancelled;\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("  if (ctx.isCancelled()) {{ ... }}  // only cancellation\n", .{});
    std.debug.print("  if (ctx.isExpired()) {{ ... }}    // only timeout\n\n", .{});

    // Example 5: With builder pattern
    std.debug.print("5. Using with Builder Pattern\n", .{});
    std.debug.print("------------------------------\n", .{});
    std.debug.print("Combine with the builder for fluent API:\n\n", .{});
    std.debug.print("  var ctx = ai.RequestContext.init(allocator);\n", .{});
    std.debug.print("  defer ctx.deinit();\n", .{});
    std.debug.print("  ctx.withTimeout(10_000);\n\n", .{});
    std.debug.print("  var builder = ai.TextGenerationBuilder.init(allocator);\n", .{});
    std.debug.print("  const result = try builder\n", .{});
    std.debug.print("      .model(&model)\n", .{});
    std.debug.print("      .prompt(\"Quick question\")\n", .{});
    std.debug.print("      .withContext(&ctx)\n", .{});
    std.debug.print("      .execute();\n\n", .{});

    std.debug.print("Example complete!\n", .{});
}
