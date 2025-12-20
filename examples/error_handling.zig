// Error Handling Example
//
// This example demonstrates error handling patterns when working with
// the Zig AI SDK, including try/catch, retries, and streaming errors.

const std = @import("std");
const ai = @import("ai");
const openai = @import("openai");
const anthropic = @import("anthropic");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    _ = allocator; // Not used in this example since we're just demonstrating patterns

    std.debug.print("Error Handling Example\n", .{});
    std.debug.print("======================\n\n", .{});

    // Example 1: Common error types
    std.debug.print("1. Common Error Types\n", .{});
    std.debug.print("----------------------\n", .{});
    std.debug.print("The SDK returns errors for various failure scenarios:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Rate Limit Errors (429):\n", .{});
    std.debug.print("    - Too many requests in a time window\n", .{});
    std.debug.print("    - Typically retryable with exponential backoff\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Authentication Errors (401):\n", .{});
    std.debug.print("    - Invalid or missing API key\n", .{});
    std.debug.print("    - Not retryable - requires fixing credentials\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Server Errors (5xx):\n", .{});
    std.debug.print("    - Service temporarily unavailable\n", .{});
    std.debug.print("    - Usually retryable\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Invalid Request Errors (400):\n", .{});
    std.debug.print("    - Malformed request or invalid parameters\n", .{});
    std.debug.print("    - Not retryable - requires fixing the request\n", .{});
    std.debug.print("\n", .{});

    // Example 2: Basic try/catch pattern
    std.debug.print("2. Basic Try/Catch Pattern\n", .{});
    std.debug.print("---------------------------\n", .{});
    std.debug.print("Handle errors with Zig's error unions:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var provider = openai.createOpenAI(allocator);\n", .{});
    std.debug.print("  defer provider.deinit();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var model = provider.languageModel(\"gpt-4o\");\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const result = ai.generateText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"Hello!\",\n", .{});
    std.debug.print("  }}) catch |err| {{\n", .{});
    std.debug.print("      std.debug.print(\"Error: {{}}\\n\", .{{err}});\n", .{});
    std.debug.print("      return err;\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("  defer result.deinit(allocator);\n", .{});
    std.debug.print("\n", .{});

    // Example 3: Handling specific error types
    std.debug.print("3. Handling Specific Error Types\n", .{});
    std.debug.print("---------------------------------\n", .{});
    std.debug.print("Use switch statements to handle different errors:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const result = ai.generateText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"Hello!\",\n", .{});
    std.debug.print("  }}) catch |err| switch (err) {{\n", .{});
    std.debug.print("      error.RateLimitExceeded => {{\n", .{});
    std.debug.print("          std.debug.print(\"Rate limited! Wait and retry.\\n\", .{{}});\n", .{});
    std.debug.print("          return err;\n", .{});
    std.debug.print("      }},\n", .{});
    std.debug.print("      error.AuthenticationError => {{\n", .{});
    std.debug.print("          std.debug.print(\"Invalid API key!\\n\", .{{}});\n", .{});
    std.debug.print("          return err;\n", .{});
    std.debug.print("      }},\n", .{});
    std.debug.print("      error.ServerError => {{\n", .{});
    std.debug.print("          std.debug.print(\"Server error, retry later.\\n\", .{{}});\n", .{});
    std.debug.print("          return err;\n", .{});
    std.debug.print("      }},\n", .{});
    std.debug.print("      else => return err,\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // Example 4: Provider-specific error patterns
    std.debug.print("4. Provider-Specific Error Handling\n", .{});
    std.debug.print("------------------------------------\n", .{});
    std.debug.print("Different providers have specific error structures:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  OpenAI Errors:\n", .{});
    std.debug.print("    - Contains: message, type, param, code\n", .{});
    std.debug.print("    - Check isRateLimitError(), isRetryable()\n", .{});
    std.debug.print("    - Error types: rate_limit_error, invalid_request_error\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Anthropic Errors:\n", .{});
    std.debug.print("    - Contains: type, error.type, error.message\n", .{});
    std.debug.print("    - Check isOverloadedError(), isRetryable()\n", .{});
    std.debug.print("    - Error types: rate_limit_error, overloaded_error\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Google Errors:\n", .{});
    std.debug.print("    - Contains: code, message, status\n", .{});
    std.debug.print("    - Status codes: RESOURCE_EXHAUSTED, UNAVAILABLE\n", .{});
    std.debug.print("    - Check isRetryable() for automatic retry logic\n", .{});
    std.debug.print("\n", .{});

    // Example 5: Automatic retries with max_retries
    std.debug.print("5. Automatic Retries\n", .{});
    std.debug.print("---------------------\n", .{});
    std.debug.print("The SDK supports automatic retry with exponential backoff:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const result = try ai.generateText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"Hello!\",\n", .{});
    std.debug.print("      .max_retries = 3,  // Retry up to 3 times (default: 2)\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("  defer result.deinit(allocator);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("How retries work:\n", .{});
    std.debug.print("  - Only retries errors marked as retryable\n", .{});
    std.debug.print("  - Uses exponential backoff between attempts\n", .{});
    std.debug.print("  - First retry: ~1 second delay\n", .{});
    std.debug.print("  - Second retry: ~2 seconds delay\n", .{});
    std.debug.print("  - Third retry: ~4 seconds delay\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Retryable errors include:\n", .{});
    std.debug.print("  - Rate limit errors (429)\n", .{});
    std.debug.print("  - Server errors (5xx)\n", .{});
    std.debug.print("  - Network timeouts\n", .{});
    std.debug.print("  - Service unavailable errors\n", .{});
    std.debug.print("\n", .{});

    // Example 6: Manual retry implementation
    std.debug.print("6. Manual Retry Implementation\n", .{});
    std.debug.print("-------------------------------\n", .{});
    std.debug.print("For custom retry logic, implement your own backoff:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const max_attempts = 5;\n", .{});
    std.debug.print("  var attempt: u32 = 0;\n", .{});
    std.debug.print("  var delay_ms: u64 = 1000;\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const result = while (attempt < max_attempts) : (attempt += 1) {{\n", .{});
    std.debug.print("      const res = ai.generateText(allocator, .{{\n", .{});
    std.debug.print("          .model = &model,\n", .{});
    std.debug.print("          .prompt = \"Hello!\",\n", .{});
    std.debug.print("          .max_retries = 0,  // Disable automatic retries\n", .{});
    std.debug.print("      }}) catch |err| {{\n", .{});
    std.debug.print("          if (attempt < max_attempts - 1) {{\n", .{});
    std.debug.print("              std.debug.print(\"Attempt {{}} failed, retrying...\\n\", .{{attempt + 1}});\n", .{});
    std.debug.print("              std.Thread.sleep(delay_ms * std.time.ns_per_ms);\n", .{});
    std.debug.print("              delay_ms *= 2;  // Exponential backoff\n", .{});
    std.debug.print("              continue;\n", .{});
    std.debug.print("          }}\n", .{});
    std.debug.print("          return err;\n", .{});
    std.debug.print("      }};\n", .{});
    std.debug.print("      break res;\n", .{});
    std.debug.print("  }} else unreachable;\n", .{});
    std.debug.print("  defer result.deinit(allocator);\n", .{});
    std.debug.print("\n", .{});

    // Example 7: Streaming error handling
    std.debug.print("7. Streaming Error Handling\n", .{});
    std.debug.print("----------------------------\n", .{});
    std.debug.print("Handle errors in streaming callbacks:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const ErrorContext = struct {{\n", .{});
    std.debug.print("      error_occurred: bool = false,\n", .{});
    std.debug.print("      error_message: ?[]const u8 = null,\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var ctx = ErrorContext{{}};\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const callbacks = ai.StreamCallbacks{{\n", .{});
    std.debug.print("      .on_part = onStreamPart,\n", .{});
    std.debug.print("      .on_error = onStreamError,\n", .{});
    std.debug.print("      .on_complete = onStreamComplete,\n", .{});
    std.debug.print("      .context = &ctx,\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  fn onStreamError(error_info: ai.StreamError, context: ?*anyopaque) void {{\n", .{});
    std.debug.print("      if (context) |ctx_ptr| {{\n", .{});
    std.debug.print("          const error_ctx: *ErrorContext = @alignCast(@ptrCast(ctx_ptr));\n", .{});
    std.debug.print("          error_ctx.error_occurred = true;\n", .{});
    std.debug.print("          error_ctx.error_message = error_info.message;\n", .{});
    std.debug.print("          std.debug.print(\"Stream error: {{s}}\\n\", .{{error_info.message}});\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var result = try ai.streamText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"Hello!\",\n", .{});
    std.debug.print("      .callbacks = callbacks,\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("  defer result.deinit();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Check for errors after streaming completes\n", .{});
    std.debug.print("  if (ctx.error_occurred) {{\n", .{});
    std.debug.print("      std.debug.print(\"Streaming failed: {{s}}\\n\", .{{ctx.error_message.?}});\n", .{});
    std.debug.print("      return error.StreamingFailed;\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // Example 8: Error recovery strategies
    std.debug.print("8. Error Recovery Strategies\n", .{});
    std.debug.print("-----------------------------\n", .{});
    std.debug.print("Different strategies for different error types:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Rate Limit Errors:\n", .{});
    std.debug.print("    1. Wait for rate limit window to reset\n", .{});
    std.debug.print("    2. Check 'Retry-After' header if provided\n", .{});
    std.debug.print("    3. Use exponential backoff (1s, 2s, 4s, 8s...)\n", .{});
    std.debug.print("    4. Consider request batching or throttling\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Authentication Errors:\n", .{});
    std.debug.print("    1. Verify API key is set: std.posix.getenv(\"OPENAI_API_KEY\")\n", .{});
    std.debug.print("    2. Check key has correct permissions\n", .{});
    std.debug.print("    3. Verify API key format matches provider\n", .{});
    std.debug.print("    4. DO NOT retry - fix credentials first\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Server Errors:\n", .{});
    std.debug.print("    1. Retry with exponential backoff\n", .{});
    std.debug.print("    2. Implement circuit breaker pattern\n", .{});
    std.debug.print("    3. Fall back to alternative model/provider\n", .{});
    std.debug.print("    4. Set reasonable timeout limits\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Invalid Request Errors:\n", .{});
    std.debug.print("    1. Validate input before sending\n", .{});
    std.debug.print("    2. Check token limits (use tokenization)\n", .{});
    std.debug.print("    3. Verify required fields are set\n", .{});
    std.debug.print("    4. DO NOT retry - fix request first\n", .{});
    std.debug.print("\n", .{});

    // Example 9: Timeout handling
    std.debug.print("9. Timeout Handling\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("Handle long-running requests with timeouts:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Note: Timeout handling is typically done at the HTTP client level\n", .{});
    std.debug.print("  // The SDK's underlying HTTP client may throw timeout errors\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const result = ai.generateText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"Long task...\",\n", .{});
    std.debug.print("  }}) catch |err| {{\n", .{});
    std.debug.print("      if (err == error.Timeout or err == error.ConnectionTimedOut) {{\n", .{});
    std.debug.print("          std.debug.print(\"Request timed out\\n\", .{{}});\n", .{});
    std.debug.print("          // Consider retrying or using streaming instead\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("      return err;\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // Example 10: Best practices
    std.debug.print("10. Error Handling Best Practices\n", .{});
    std.debug.print("----------------------------------\n", .{});
    std.debug.print("  - Always use 'defer result.deinit()' to clean up\n", .{});
    std.debug.print("  - Set appropriate max_retries (default: 2)\n", .{});
    std.debug.print("  - Log errors with context for debugging\n", .{});
    std.debug.print("  - Don't retry non-retryable errors (4xx except 429)\n", .{});
    std.debug.print("  - Implement exponential backoff for retries\n", .{});
    std.debug.print("  - Use streaming for long responses to detect errors early\n", .{});
    std.debug.print("  - Set max retry limits to avoid infinite loops\n", .{});
    std.debug.print("  - Handle streaming errors in on_error callback\n", .{});
    std.debug.print("  - Validate inputs before making API calls\n", .{});
    std.debug.print("  - Consider fallback providers for high availability\n", .{});
    std.debug.print("\n", .{});

    // Example 11: Complete error handling example
    std.debug.print("11. Complete Error Handling Example\n", .{});
    std.debug.print("------------------------------------\n", .{});
    std.debug.print("Putting it all together:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  fn robustGenerate(\n", .{});
    std.debug.print("      allocator: std.mem.Allocator,\n", .{});
    std.debug.print("      model: *ai.LanguageModelV3,\n", .{});
    std.debug.print("      prompt: []const u8,\n", .{});
    std.debug.print("  ) !ai.GenerateTextResult {{\n", .{});
    std.debug.print("      // Validate input\n", .{});
    std.debug.print("      if (prompt.len == 0) return error.InvalidPrompt;\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("      // Try with automatic retries first\n", .{});
    std.debug.print("      const result = ai.generateText(allocator, .{{\n", .{});
    std.debug.print("          .model = model,\n", .{});
    std.debug.print("          .prompt = prompt,\n", .{});
    std.debug.print("          .max_retries = 3,\n", .{});
    std.debug.print("      }}) catch |err| switch (err) {{\n", .{});
    std.debug.print("          error.AuthenticationError => {{\n", .{});
    std.debug.print("              std.debug.print(\"Auth failed - check API key\\n\", .{{}});\n", .{});
    std.debug.print("              return err;\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("          error.RateLimitExceeded => {{\n", .{});
    std.debug.print("              std.debug.print(\"Rate limited after retries\\n\", .{{}});\n", .{});
    std.debug.print("              return err;\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("          error.InvalidRequest => {{\n", .{});
    std.debug.print("              std.debug.print(\"Invalid request - check parameters\\n\", .{{}});\n", .{});
    std.debug.print("              return err;\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("          else => {{\n", .{});
    std.debug.print("              std.debug.print(\"Unexpected error: {{}}\\n\", .{{err}});\n", .{});
    std.debug.print("              return err;\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("      }};\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("      return result;\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example complete!\n", .{});
    std.debug.print("\nKey Takeaways:\n", .{});
    std.debug.print("- Use try/catch or catch |err| patterns for error handling\n", .{});
    std.debug.print("- Enable automatic retries with max_retries option\n", .{});
    std.debug.print("- Only retry errors that are retryable (rate limits, server errors)\n", .{});
    std.debug.print("- Implement exponential backoff for manual retries\n", .{});
    std.debug.print("- Handle streaming errors in the on_error callback\n", .{});
    std.debug.print("- Always clean up resources with defer result.deinit()\n", .{});
}
