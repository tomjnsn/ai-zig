// Middleware Example
//
// This example demonstrates how to use middleware to transform
// requests and responses in the Zig AI SDK.

const std = @import("std");
const ai = @import("ai");
const openai = @import("openai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Middleware Example\n", .{});
    std.debug.print("==================\n\n", .{});

    // Create OpenAI provider
    var provider = openai.createOpenAI(allocator);
    defer provider.deinit();

    var model = provider.languageModel("gpt-4o");
    std.debug.print("Using model: {s}\n\n", .{model.getModelId()});

    // Example 1: What is middleware?
    std.debug.print("1. What is Middleware?\n", .{});
    std.debug.print("-----------------------\n", .{});
    std.debug.print("Middleware allows you to intercept and modify requests\n", .{});
    std.debug.print("before they're sent and responses after they're received.\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Common use cases:\n", .{});
    std.debug.print("  - Logging requests and responses\n", .{});
    std.debug.print("  - Adding authentication headers\n", .{});
    std.debug.print("  - Collecting metrics and usage stats\n", .{});
    std.debug.print("  - Rate limiting and throttling\n", .{});
    std.debug.print("  - Request/response transformation\n", .{});
    std.debug.print("  - Retry logic and error handling\n", .{});
    std.debug.print("\n", .{});

    // Example 2: Middleware types
    std.debug.print("2. Middleware Types\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("Two types of middleware:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  RequestMiddleware  - Transforms requests before sending\n", .{});
    std.debug.print("  ResponseMiddleware - Transforms responses after receiving\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Type signatures:\n", .{});
    std.debug.print("  RequestMiddleware = *const fn(\n", .{});
    std.debug.print("      request: *MiddlewareRequest,\n", .{});
    std.debug.print("      context: *MiddlewareContext,\n", .{});
    std.debug.print("  ) anyerror!void;\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  ResponseMiddleware = *const fn(\n", .{});
    std.debug.print("      response: *MiddlewareResponse,\n", .{});
    std.debug.print("      context: *MiddlewareContext,\n", .{});
    std.debug.print("  ) anyerror!void;\n", .{});
    std.debug.print("\n", .{});

    // Example 3: Creating request middleware
    std.debug.print("3. Creating Request Middleware\n", .{});
    std.debug.print("-------------------------------\n", .{});
    std.debug.print("Request middleware can modify the request before it's sent:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  fn addHeaderMiddleware(\n", .{});
    std.debug.print("      request: *ai.MiddlewareRequest,\n", .{});
    std.debug.print("      context: *ai.MiddlewareContext,\n", .{});
    std.debug.print("  ) anyerror!void {{\n", .{});
    std.debug.print("      // Initialize headers if not present\n", .{});
    std.debug.print("      if (request.headers == null) {{\n", .{});
    std.debug.print("          request.headers = std.StringHashMap([]const u8).init(context.allocator);\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("      \n", .{});
    std.debug.print("      // Add a custom header\n", .{});
    std.debug.print("      try request.headers.?.put(\"X-Custom-Header\", \"my-value\");\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // Demonstrate the concept
    std.debug.print("Example: Adding a custom header\n", .{});
    std.debug.print("  Before: No custom headers\n", .{});
    std.debug.print("  After:  X-Custom-Header: my-value\n", .{});
    std.debug.print("\n", .{});

    // Example 4: Creating response middleware
    std.debug.print("4. Creating Response Middleware\n", .{});
    std.debug.print("--------------------------------\n", .{});
    std.debug.print("Response middleware can process or modify responses:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  fn metricsMiddleware(\n", .{});
    std.debug.print("      response: *ai.MiddlewareResponse,\n", .{});
    std.debug.print("      context: *ai.MiddlewareContext,\n", .{});
    std.debug.print("  ) anyerror!void {{\n", .{});
    std.debug.print("      _ = context;\n", .{});
    std.debug.print("      \n", .{});
    std.debug.print("      // Collect usage metrics\n", .{});
    std.debug.print("      if (response.usage) |usage| {{\n", .{});
    std.debug.print("          std.debug.print(\"Tokens used: {{d}}\\n\", .{{usage.total_tokens}});\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // Demonstrate the concept
    std.debug.print("Example: Collecting metrics\n", .{});
    std.debug.print("  Response received\n", .{});
    std.debug.print("  Metrics: Tokens used: 150\n", .{});
    std.debug.print("  Metrics: Prompt tokens: 100\n", .{});
    std.debug.print("  Metrics: Completion tokens: 50\n", .{});
    std.debug.print("\n", .{});

    // Example 5: Logging middleware
    std.debug.print("5. Built-in Logging Middleware\n", .{});
    std.debug.print("-------------------------------\n", .{});
    std.debug.print("The SDK provides a logging middleware:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Create logging middleware\n", .{});
    std.debug.print("  const logging = ai.createLoggingMiddleware();\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Define log function\n", .{});
    std.debug.print("  fn logFn(msg: []const u8) void {{\n", .{});
    std.debug.print("      std.debug.print(\"[LOG] {{s}}\\n\", .{{msg}});\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Store logging context\n", .{});
    std.debug.print("  var log_ctx = ai.LoggingMiddlewareContext.init(logFn);\n", .{});
    std.debug.print("  try log_ctx.store(&context);\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Add to chain\n", .{});
    std.debug.print("  try chain.useRequest(logging.request);\n", .{});
    std.debug.print("  try chain.useResponse(logging.response);\n", .{});
    std.debug.print("\n", .{});

    // Demonstrate logging
    std.debug.print("Example log output:\n", .{});
    std.debug.print("  [LOG] Request: Tell me a joke\n", .{});
    std.debug.print("  [LOG] Response: Why did the programmer quit? Too many bugs!\n", .{});
    std.debug.print("\n", .{});

    // Example 6: Middleware context
    std.debug.print("6. Middleware Context\n", .{});
    std.debug.print("----------------------\n", .{});
    std.debug.print("MiddlewareContext provides:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  - allocator: For memory allocations\n", .{});
    std.debug.print("  - model: The underlying language model\n", .{});
    std.debug.print("  - cancelled: Flag to cancel request chain\n", .{});
    std.debug.print("  - data: Custom data storage (StringHashMap)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Usage:\n", .{});
    std.debug.print("  var context = ai.MiddlewareContext.init(allocator);\n", .{});
    std.debug.print("  defer context.deinit();\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Store custom data\n", .{});
    std.debug.print("  try context.set(\"my_key\", my_data_ptr);\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Retrieve custom data\n", .{});
    std.debug.print("  if (context.get(\"my_key\")) |data| {{\n", .{});
    std.debug.print("      // Use data\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // Example 7: MiddlewareChain
    std.debug.print("7. Composing Middleware with MiddlewareChain\n", .{});
    std.debug.print("---------------------------------------------\n", .{});
    std.debug.print("MiddlewareChain manages multiple middleware functions:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Create chain\n", .{});
    std.debug.print("  var chain = ai.MiddlewareChain.init(allocator);\n", .{});
    std.debug.print("  defer chain.deinit();\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Add request middleware (executed in order)\n", .{});
    std.debug.print("  try chain.useRequest(addHeaderMiddleware);\n", .{});
    std.debug.print("  try chain.useRequest(loggingMiddleware);\n", .{});
    std.debug.print("  try chain.useRequest(authMiddleware);\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Add response middleware (executed in reverse order)\n", .{});
    std.debug.print("  try chain.useResponse(metricsMiddleware);\n", .{});
    std.debug.print("  try chain.useResponse(cacheMiddleware);\n", .{});
    std.debug.print("\n", .{});

    // Demonstrate execution order
    std.debug.print("Execution order:\n", .{});
    std.debug.print("  Request flow:\n", .{});
    std.debug.print("    1. addHeaderMiddleware\n", .{});
    std.debug.print("    2. loggingMiddleware\n", .{});
    std.debug.print("    3. authMiddleware\n", .{});
    std.debug.print("    4. [API Call]\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  Response flow:\n", .{});
    std.debug.print("    1. [API Response]\n", .{});
    std.debug.print("    2. cacheMiddleware\n", .{});
    std.debug.print("    3. metricsMiddleware\n", .{});
    std.debug.print("\n", .{});

    // Example 8: Processing through the chain
    std.debug.print("8. Processing Through the Chain\n", .{});
    std.debug.print("--------------------------------\n", .{});
    std.debug.print("Manually process requests/responses:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Create request\n", .{});
    std.debug.print("  var request = ai.MiddlewareRequest{{\n", .{});
    std.debug.print("      .prompt = \"Hello, AI!\",\n", .{});
    std.debug.print("      .settings = .{{ .temperature = 0.7 }},\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Create context\n", .{});
    std.debug.print("  var context = ai.MiddlewareContext.init(allocator);\n", .{});
    std.debug.print("  defer context.deinit();\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Process request through chain\n", .{});
    std.debug.print("  try chain.processRequest(&request, &context);\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // ... make API call ...\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Create response\n", .{});
    std.debug.print("  var response = ai.MiddlewareResponse{{\n", .{});
    std.debug.print("      .text = \"Hi there!\",\n", .{});
    std.debug.print("      .finish_reason = .stop,\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Process response through chain (reverse order)\n", .{});
    std.debug.print("  try chain.processResponse(&response, &context);\n", .{});
    std.debug.print("\n", .{});

    // Example 9: Custom middleware example
    std.debug.print("9. Complete Custom Middleware Example\n", .{});
    std.debug.print("--------------------------------------\n", .{});
    std.debug.print("Here's a full example of a custom middleware:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Middleware that adds a timestamp\n", .{});
    std.debug.print("  fn timestampMiddleware(\n", .{});
    std.debug.print("      request: *ai.MiddlewareRequest,\n", .{});
    std.debug.print("      context: *ai.MiddlewareContext,\n", .{});
    std.debug.print("  ) anyerror!void {{\n", .{});
    std.debug.print("      const timestamp = std.time.timestamp();\n", .{});
    std.debug.print("      \n", .{});
    std.debug.print("      // Initialize metadata if needed\n", .{});
    std.debug.print("      if (request.metadata == null) {{\n", .{});
    std.debug.print("          request.metadata = std.StringHashMap([]const u8).init(context.allocator);\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("      \n", .{});
    std.debug.print("      // Format timestamp\n", .{});
    std.debug.print("      const timestamp_str = try std.fmt.allocPrint(\n", .{});
    std.debug.print("          context.allocator,\n", .{});
    std.debug.print("          \"{{d}}\",\n", .{});
    std.debug.print("          .{{timestamp}},\n", .{});
    std.debug.print("      );\n", .{});
    std.debug.print("      \n", .{});
    std.debug.print("      // Add to metadata\n", .{});
    std.debug.print("      try request.metadata.?.put(\"timestamp\", timestamp_str);\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // Demonstrate timestamp middleware
    const current_timestamp = std.time.timestamp();
    std.debug.print("Example execution:\n", .{});
    std.debug.print("  Request metadata:\n", .{});
    std.debug.print("    timestamp: {d}\n", .{current_timestamp});
    std.debug.print("\n", .{});

    // Example 10: Cancelling requests
    std.debug.print("10. Cancelling Request Processing\n", .{});
    std.debug.print("----------------------------------\n", .{});
    std.debug.print("Middleware can cancel request processing:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  fn rateLimitMiddleware(\n", .{});
    std.debug.print("      request: *ai.MiddlewareRequest,\n", .{});
    std.debug.print("      context: *ai.MiddlewareContext,\n", .{});
    std.debug.print("  ) anyerror!void {{\n", .{});
    std.debug.print("      _ = request;\n", .{});
    std.debug.print("      \n", .{});
    std.debug.print("      // Check rate limit\n", .{});
    std.debug.print("      if (isRateLimited()) {{\n", .{});
    std.debug.print("          context.cancelled = true;\n", .{});
    std.debug.print("          return error.RateLimitExceeded;\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("When cancelled = true, remaining middleware won't execute.\n", .{});
    std.debug.print("\n", .{});

    // Example 11: MiddlewareRequest and MiddlewareResponse fields
    std.debug.print("11. Request and Response Fields\n", .{});
    std.debug.print("--------------------------------\n", .{});
    std.debug.print("MiddlewareRequest fields:\n", .{});
    std.debug.print("  - prompt: ?[]const u8\n", .{});
    std.debug.print("  - settings: CallSettings\n", .{});
    std.debug.print("  - headers: ?StringHashMap([]const u8)\n", .{});
    std.debug.print("  - provider_options: ?std.json.Value\n", .{});
    std.debug.print("  - metadata: ?StringHashMap([]const u8)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("MiddlewareResponse fields:\n", .{});
    std.debug.print("  - text: ?[]const u8\n", .{});
    std.debug.print("  - usage: ?LanguageModelUsage\n", .{});
    std.debug.print("  - finish_reason: ?FinishReason\n", .{});
    std.debug.print("  - headers: ?StringHashMap([]const u8)\n", .{});
    std.debug.print("  - metadata: ?StringHashMap([]const u8)\n", .{});
    std.debug.print("\n", .{});

    // Example 12: Best practices
    std.debug.print("12. Middleware Best Practices\n", .{});
    std.debug.print("------------------------------\n", .{});
    std.debug.print("  - Keep middleware focused on a single responsibility\n", .{});
    std.debug.print("  - Order matters: auth before logging, metrics after response\n", .{});
    std.debug.print("  - Use context.data for sharing state between middleware\n", .{});
    std.debug.print("  - Handle errors gracefully, don't swallow them\n", .{});
    std.debug.print("  - Be mindful of memory allocations in hot paths\n", .{});
    std.debug.print("  - Document what your middleware modifies\n", .{});
    std.debug.print("  - Test middleware independently before chaining\n", .{});
    std.debug.print("  - Use cancelled flag for early termination\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example complete!\n", .{});
}
