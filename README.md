# Zig AI SDK

A comprehensive AI SDK for Zig, ported from the [Vercel AI SDK](https://sdk.vercel.ai). Provides a unified interface for interacting with multiple AI providers.

## Features

- **Multiple Providers**: Support for 14 AI provider packages
- **Streaming**: Callback-based streaming for real-time responses
- **Tool Calling**: Full support for function/tool calling with agentic loop
- **Structured Output**: Generate and stream structured JSON objects with schema validation
- **Embeddings**: Text embedding generation with similarity functions
- **Middleware**: Extensible request/response transformation (rate limiting, etc.)
- **Memory Safe**: Uses arena allocators for efficient memory management
- **Testable**: MockHttpClient for unit testing without network calls
- **Type-Erased HTTP**: Pluggable HTTP client interface via vtables

## Supported Providers

| Provider | Package | Live Tested |
|----------|---------|-------------|
| OpenAI (GPT-4, GPT-4o, o1, o3) | `openai` | Yes |
| Anthropic (Claude 3.5, Claude 4) | `anthropic` | Yes |
| Google AI (Gemini 2.0, 1.5) | `google` | Yes |
| Google Vertex AI | `google-vertex` | - |
| Azure OpenAI | `azure` | Yes |
| xAI (Grok) | `xai` | Yes |
| Perplexity | `perplexity` | - |
| Together AI | `togetherai` | - |
| Fireworks | `fireworks` | - |
| Cerebras | `cerebras` | - |
| DeepInfra | `deepinfra` | - |
| HuggingFace | `huggingface` | - |
| OpenAI Compatible (any compatible API) | `openai-compatible` | - |

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .@"zig-ai-sdk" = .{
        .url = "https://github.com/evmts/ai-zig/archive/main.tar.gz",
        .hash = "...",
    },
},
```

## Quick Start

```zig
const std = @import("std");
const ai = @import("ai");
const openai = @import("openai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create provider
    var provider = openai.createOpenAI(allocator);
    defer provider.deinit();

    // Get model
    var model = provider.languageModel("gpt-4o");

    // Generate text
    const result = try ai.generateText(allocator, .{
        .model = &model,
        .prompt = "What is the meaning of life?",
    });
    defer result.deinit(allocator);

    std.debug.print("{s}\n", .{result.text});
}
```

## Streaming Example

```zig
const callbacks = ai.StreamCallbacks{
    .on_part = struct {
        fn f(part: ai.StreamPart, _: ?*anyopaque) void {
            switch (part) {
                .text_delta => |delta| {
                    std.debug.print("{s}", .{delta.text});
                },
                else => {},
            }
        }
    }.f,
    .on_error = struct {
        fn f(err: anyerror, _: ?*anyopaque) void {
            std.debug.print("Error: {}\n", .{err});
        }
    }.f,
    .on_complete = struct {
        fn f(_: ?*anyopaque) void {
            std.debug.print("\nDone!\n", .{});
        }
    }.f,
};

const result = try ai.streamText(allocator, .{
    .model = &model,
    .prompt = "Tell me a story",
    .callbacks = callbacks,
});
defer result.deinit();
```

## Tool Calling Example

```zig
const tool = ai.Tool.create(.{
    .name = "get_weather",
    .description = "Get the weather for a location",
    .parameters = weather_schema,
    .execute = struct {
        fn f(input: std.json.Value, _: ai.ToolExecutionContext) !ai.ToolExecutionResult {
            // Process weather request
            return .{ .success = std.json.Value{ .string = "Sunny, 72F" } };
        }
    }.f,
});

const result = try ai.generateText(allocator, .{
    .model = &model,
    .prompt = "What's the weather in San Francisco?",
    .tools = &[_]ai.Tool{tool},
    .max_steps = 5,
});
```

## Embeddings Example

```zig
const embed = @import("ai").embed;

// Generate embedding
const result = try embed(allocator, .{
    .model = &embedding_model,
    .value = "Hello, world!",
});

// Calculate similarity
const similarity = ai.cosineSimilarity(result.embedding.values, other_embedding);
```

## Building

```bash
zig build              # Build all packages
zig build test         # Run all unit tests
zig build test-live    # Run live provider integration tests (requires API keys)
zig build run-example  # Run the example application
```

### Live Integration Tests

Live tests hit real provider APIs. Set up your keys and run:

```bash
cp .env.example .env   # Fill in your API keys
./scripts/test-live.sh # Loads .env and runs live tests
```

Tests skip automatically for providers without keys configured. See [.env.example](.env.example) for required variables.

## Architecture

The SDK uses several key patterns:

1. **Arena Allocators**: Request-scoped memory management
2. **Vtable Pattern**: Interface abstraction for models and HTTP clients
3. **Callback-based Streaming**: Non-blocking I/O with SSE parsing
4. **Provider Abstraction**: Unified interface across providers
5. **Type-Erased HTTP**: Pluggable `HttpClient` interface for real and mock implementations

### HTTP Client Interface

The SDK uses a type-erased HTTP client interface that allows dependency injection:

```zig
const provider_utils = @import("provider-utils");

// Use the standard HTTP client (default)
var provider = openai.createOpenAI(allocator);

// Or inject a mock client for testing
var mock = provider_utils.MockHttpClient.init(allocator);
defer mock.deinit();

mock.setResponse(.{
    .status_code = 200,
    .body = "{\"choices\":[{\"message\":{\"content\":\"Hello!\"}}]}",
});

var provider = openai.createOpenAIWithSettings(allocator, .{
    .http_client = mock.asInterface(),
});
```

## Memory Management

```zig
// Arena allocator for request scope
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();

// Use arena for request processing
const result = try processRequest(arena.allocator());

// Data is automatically freed when arena is deinitialized
```

## Project Structure

```
ai-zig/
├── build.zig              # Root build configuration
├── build.zig.zon          # Package manifest
├── packages/
│   ├── ai/                # High-level API (generateText, streamText, generateObject, etc.)
│   ├── provider/          # Core provider interfaces and types
│   ├── provider-utils/    # HTTP client, streaming utilities, SSE parsing
│   ├── openai/            # OpenAI provider
│   ├── openai-compatible/ # OpenAI-compatible base (shared by several providers)
│   ├── anthropic/         # Anthropic provider
│   ├── google/            # Google AI provider
│   ├── google-vertex/     # Google Vertex AI provider
│   ├── azure/             # Azure OpenAI provider
│   ├── xai/               # xAI (Grok) provider
│   ├── perplexity/        # Perplexity provider
│   ├── togetherai/        # Together AI provider
│   ├── fireworks/         # Fireworks provider
│   ├── cerebras/          # Cerebras provider
│   ├── deepinfra/         # DeepInfra provider
│   └── huggingface/       # HuggingFace provider
├── scripts/
│   └── test-live.sh       # Run live tests with .env
├── tests/
│   └── integration/       # Live provider integration tests
└── examples/
    └── simple.zig         # Example usage
```

## Testing

The SDK includes comprehensive unit tests (800+ passing, including ~33 compilation-verification tests via `refAllDecls`):

```bash
zig build test
```

### MockHttpClient

For unit testing provider implementations without network calls:

```zig
const allocator = std.testing.allocator;

var mock = provider_utils.MockHttpClient.init(allocator);
defer mock.deinit();

// Configure expected response
mock.setResponse(.{
    .status_code = 200,
    .body = "{\"id\":\"123\",\"choices\":[...]}",
});

// Pass to provider
var provider = openai.createOpenAIWithSettings(allocator, .{
    .http_client = mock.asInterface(),
});

// Make request...

// Verify request was made correctly
const req = mock.lastRequest().?;
try std.testing.expectEqualStrings("POST", req.method.toString());
```

## Roadmap

### Working (with live integration tests)
- `generateText` / `streamText` - text generation and streaming
- `generateObject` / `streamObject` - structured JSON output with schema validation
- Tool execution with agentic loop (multi-step)
- 5 providers tested: OpenAI, Anthropic, Google, Azure, xAI

### Working (unit tests only)
- `embed` / `embedMany` - text embedding generation
- Middleware chain (rate limiting)
- `RetryPolicy`, `RequestContext`
- `generateImage`, `generateSpeech`, `transcribe` - API surface exists, no provider implementations yet

### Known Issues
- **Streaming memory**: Provider `doStream` implementations allocate internally without proper cleanup; streaming tests use `ArenaAllocator` as a workaround
- **API response coverage**: Some provider response structs don't cover all fields returned by live APIs; `ignore_unknown_fields` is used as a temporary workaround until structs are updated to match full API schemas

### Planned
- Complete API response struct coverage for all providers
- Fix streaming memory management
- Re-enable removed providers (Mistral, Groq, DeepSeek, Cohere, Bedrock, etc.)
- Image generation providers (Fal, FLUX, DALL-E)
- Speech/audio providers (ElevenLabs, Deepgram, etc.)
- Additional middleware (logging, caching, token counting)
- Multi-modal prompt support (images in prompts)

## Requirements

- Zig 0.15.0 or later

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License
