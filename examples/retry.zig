// Retry Policy Example
//
// This example demonstrates how to configure retry policies
// for automatic retry with exponential backoff.

const std = @import("std");
const ai = @import("ai");

pub fn main() !void {
    std.debug.print("Retry Policy Example\n", .{});
    std.debug.print("=====================\n\n", .{});

    // Example 1: Default retry policy
    std.debug.print("1. Default Retry Policy\n", .{});
    std.debug.print("------------------------\n", .{});
    std.debug.print("The default policy: 2 retries, exponential backoff:\n\n", .{});
    std.debug.print("  const policy = ai.RetryPolicy{{}};\n", .{});
    std.debug.print("  // max_retries: 2\n", .{});
    std.debug.print("  // initial_delay_ms: 1000 (1 second)\n", .{});
    std.debug.print("  // max_delay_ms: 30000 (30 seconds)\n", .{});
    std.debug.print("  // backoff_multiplier: 2.0\n", .{});
    std.debug.print("  // jitter: true\n\n", .{});

    // Example 2: Custom retry policy
    std.debug.print("2. Custom Retry Policy\n", .{});
    std.debug.print("------------------------\n", .{});
    std.debug.print("Configure for your use case:\n\n", .{});
    std.debug.print("  const result = try ai.generateText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"Hello!\",\n", .{});
    std.debug.print("      .retry_policy = .{{\n", .{});
    std.debug.print("          .max_retries = 5,\n", .{});
    std.debug.print("          .initial_delay_ms = 500,\n", .{});
    std.debug.print("          .max_delay_ms = 60000,\n", .{});
    std.debug.print("          .backoff_multiplier = 3.0,\n", .{});
    std.debug.print("          .jitter = true,\n", .{});
    std.debug.print("      }},\n", .{});
    std.debug.print("  }});\n\n", .{});

    // Example 3: Preset policies
    std.debug.print("3. Preset Policies\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("Use built-in presets:\n\n", .{});
    std.debug.print("  // Default: 2 retries, 1s initial delay\n", .{});
    std.debug.print("  .retry_policy = ai.RetryPolicy.default_policy,\n\n", .{});
    std.debug.print("  // Aggressive: 5 retries, 2s initial, 3x multiplier\n", .{});
    std.debug.print("  .retry_policy = ai.RetryPolicy.aggressive,\n\n", .{});
    std.debug.print("  // None: disable retries entirely\n", .{});
    std.debug.print("  .retry_policy = ai.RetryPolicy.none,\n\n", .{});

    // Example 4: Selective retry
    std.debug.print("4. Selective Retry Categories\n", .{});
    std.debug.print("-------------------------------\n", .{});
    std.debug.print("Control which errors trigger retries:\n\n", .{});
    std.debug.print("  .retry_policy = .{{\n", .{});
    std.debug.print("      .retry_on_rate_limit = true,   // 429 errors\n", .{});
    std.debug.print("      .retry_on_server_error = true, // 5xx errors\n", .{});
    std.debug.print("      .retry_on_timeout = false,     // don't retry timeouts\n", .{});
    std.debug.print("  }},\n\n", .{});

    // Example 5: Check retry decisions
    std.debug.print("5. Programmatic Retry Decisions\n", .{});
    std.debug.print("---------------------------------\n", .{});
    std.debug.print("Use the policy to make retry decisions:\n\n", .{});
    std.debug.print("  const policy = ai.RetryPolicy{{ .max_retries = 3 }};\n\n", .{});
    std.debug.print("  // Check if should retry for a given attempt and status\n", .{});
    std.debug.print("  policy.shouldRetry(0, 429) // true - rate limited\n", .{});
    std.debug.print("  policy.shouldRetry(0, 500) // true - server error\n", .{});
    std.debug.print("  policy.shouldRetry(0, 400) // false - client error\n", .{});
    std.debug.print("  policy.shouldRetry(3, 429) // false - max retries reached\n\n", .{});
    std.debug.print("  // Calculate delay for a retry attempt\n", .{});
    std.debug.print("  policy.delayMs(0, null) // ~1000ms (first retry)\n", .{});
    std.debug.print("  policy.delayMs(1, null) // ~2000ms (second retry)\n", .{});
    std.debug.print("  policy.delayMs(2, null) // ~4000ms (third retry)\n\n", .{});

    // Example 6: With builder pattern
    std.debug.print("6. Using with Builder Pattern\n", .{});
    std.debug.print("------------------------------\n", .{});
    std.debug.print("  var builder = ai.TextGenerationBuilder.init(allocator);\n", .{});
    std.debug.print("  const result = try builder\n", .{});
    std.debug.print("      .model(&model)\n", .{});
    std.debug.print("      .prompt(\"Hello!\")\n", .{});
    std.debug.print("      .withRetry(ai.RetryPolicy.aggressive)\n", .{});
    std.debug.print("      .execute();\n\n", .{});

    std.debug.print("Example complete!\n", .{});
}
