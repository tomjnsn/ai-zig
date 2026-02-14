# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Zig AI SDK - A comprehensive AI SDK for Zig, ported from the Vercel AI SDK. Provides unified interfaces for 14 AI provider packages including OpenAI, Anthropic, Google, Azure, xAI, and more. Supports text generation, streaming, tool calling, structured object generation, and embeddings.

**Requirements**: Zig 0.15.0 or later

## Build Commands

```bash
zig build              # Build all packages
zig build test         # Run all unit tests
zig build test-live    # Run live provider integration tests (requires API keys in .env)
zig build run-example  # Run the example application
```

There is no way to run individual test files - all tests are compiled and run together via `build.zig`.

### Live Integration Tests

Live tests require API keys in a `.env` file. Use the helper script:

```bash
cp .env.example .env       # Fill in your API keys
./scripts/test-live.sh     # Loads .env and runs zig build test-live
```

Required env vars per provider:
- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GOOGLE_GENERATIVE_AI_API_KEY`
- `XAI_API_KEY`
- `AZURE_API_KEY`, `AZURE_RESOURCE_NAME`, `AZURE_DEPLOYMENT_NAME`

Tests skip automatically when a provider's key is not set. The test file is at `tests/integration/live_provider_test.zig`.

## GitHub Workflow

This is a fork. Remotes:
- `origin` = `tomjnsn/ai-zig` (this fork — PRs and issues go here)
- `upstream` = `evmts/ai-zig` (upstream)

**IMPORTANT**: Always use `-R tomjnsn/ai-zig` or rely on `gh repo set-default` when creating PRs/issues with `gh`. Never create PRs or issues on the upstream `evmts/ai-zig` repo.

### Commit & PR Discipline

Every code change **must** be committed and submitted as a PR before moving on to the next task. Follow this workflow:

1. **Issue first**: Create a GitHub issue describing the work (or reference an existing one).
2. **Branch per issue**: Create a feature/fix branch from `main` (e.g., `fix/47-use-after-free`, `feature/51-tool-execution`).
3. **Commit immediately**: Commit changes as soon as a logical unit of work is done. Do not accumulate uncommitted changes across multiple tasks.
4. **PR per branch**: Open a PR referencing the issue (e.g., `Fixes #47`). Include a summary and test plan.
5. **Merge before next task**: Merge the PR (or get it approved) before starting the next piece of work.
6. **Never leave uncommitted work**: At the end of any session, all changes must be committed, pushed, and in a PR. No orphaned diffs on `main`.

## Architecture

### Package Hierarchy

```
packages/
├── provider/           # Core interfaces (LanguageModelV3, EmbeddingModelV3, etc.)
├── provider-utils/     # HTTP client, streaming, memory utilities, SSE parsing
├── ai/                 # High-level API (generateText, streamText, embed, etc.)
└── <provider>/         # Individual provider implementations (openai, anthropic, etc.)
```

### Key Design Patterns

1. **Vtable Pattern**: Interface abstraction for models instead of traits. Each model type (LanguageModelV3, EmbeddingModelV3, etc.) uses vtables for runtime polymorphism. See "Pointer Casting and Vtables" section below.

2. **Callback-based Streaming**: Non-async approach using `StreamCallbacks` with `on_part`, `on_error`, and `on_complete` callbacks.

3. **Arena Allocators**: Request-scoped memory management. Use `defer arena.deinit()` for cleanup.

4. **Provider Pattern**: Each provider implements `init()`, `deinit()`, `getProvider()`, and model factory methods (e.g., `languageModel()`).

5. **HttpClient Interface**: Type-erased HTTP client allowing mock injection for testing. Providers accept optional `http_client: ?provider_utils.HttpClient` in settings.

### Core Types

- `packages/provider/src/`: `JsonValue` (custom JSON type), error hierarchy, model interfaces
- `packages/provider-utils/src/http/`: HTTP client abstraction and standard library implementation
- `packages/ai/src/generate-text/`: Text generation with streaming and tool support
- `packages/ai/src/generate-object/`: Structured object generation with JSON schema validation
- `packages/ai/src/embed/`: Text embedding generation with similarity functions
- `packages/ai/src/tool/`: Tool/function calling with agentic loop support
- `packages/ai/src/middleware/`: Request/response middleware chain (rate limiting, etc.)

## Adding a New Provider

1. Create `packages/<provider-name>/src/` directory
2. Implement provider struct with `init()`, `deinit()`, `getProvider()`, model factory methods
3. Create `index.zig` that re-exports public API with `test { @import("std").testing.refAllDecls(@This()); }`
4. Add module to `build.zig` with appropriate imports (provider, provider-utils, and any base providers)
5. Add test config entry in the `test_configs` array in `build.zig`

## Code Style

- `snake_case` for functions and variables
- `PascalCase` for types
- Doc comments with `///` for public APIs
- Document memory ownership in function signatures
- Use `defer` for cleanup operations

## Memory Management

```zig
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
// Use arena.allocator() for request-scoped allocations
```

### Ownership Conventions

- **Caller-owned**: Function returns data allocated by the passed allocator. Caller must free.
- **Arena-owned**: Data lives until arena is deinitialized. No manual free needed.
- **Static**: Compile-time data (string literals, const slices). Never free.

### Header Functions

Provider `getHeaders()` functions return `std.StringHashMap([]const u8)`. Caller owns the returned map and must call `deinit()`:

```zig
var headers = provider.getHeaders(allocator);
defer headers.deinit();
```

## Pointer Casting and Vtables

The SDK uses vtables for runtime polymorphism. This requires `@ptrCast` and `@alignCast` when converting between `*anyopaque` and concrete types.

### Pattern

```zig
// Interface definition
pub const HttpClient = struct {
    vtable: *const VTable,
    impl: *anyopaque,  // Type-erased implementation pointer

    pub const VTable = struct {
        request: *const fn (impl: *anyopaque, ...) void,
    };

    pub fn request(self: HttpClient, ...) void {
        self.vtable.request(self.impl, ...);
    }
};

// Implementation
pub const MockHttpClient = struct {
    // ... fields ...

    pub fn asInterface(self: *MockHttpClient) HttpClient {
        return .{
            .vtable = &vtable,
            .impl = self,  // Implicit cast to *anyopaque
        };
    }

    const vtable = HttpClient.VTable{
        .request = doRequest,
    };

    fn doRequest(impl: *anyopaque, ...) void {
        // Cast back to concrete type - alignment is guaranteed since
        // impl was originally a *MockHttpClient
        const self: *MockHttpClient = @ptrCast(@alignCast(impl));
        // ... implementation ...
    }
};
```

### Alignment Safety

The `@alignCast` is safe when:
1. The pointer was originally the concrete type before being cast to `*anyopaque`
2. The vtable and impl are always paired correctly (same instance)

All vtable implementations in this codebase follow this pattern, ensuring alignment is preserved through the type-erasure round-trip.
