# Agent Task: Fix Zig 0.15 Compatibility and Make All Tests Pass

## CRITICAL INSTRUCTION
**DO NOT STOP UNTIL `zig build test` RUNS SUCCESSFULLY WITH ALL TESTS PASSING.**

You must iterate, fix errors, re-run tests, and repeat until there are ZERO compilation errors and all tests pass. This is not optional - partial completion is not acceptable.

## Context

This is a Zig AI SDK with 32 provider packages. Comprehensive unit tests (~300+ new tests) have been added to 13 previously untested providers:

- ElevenLabs, Deepgram, Groq, Azure, xAI, Perplexity, TogetherAI, Fireworks, Cerebras, DeepInfra, Replicate, HuggingFace
- provider-utils (HTTP client, streaming, JSON parsing)

The tests are written correctly but the codebase has **Zig 0.15 compatibility issues** that prevent them from running.

## Known Issues to Fix

### 1. Relative Path Imports (HIGHEST PRIORITY)
Many files use relative imports that don't work with Zig 0.15's module system:
```zig
// WRONG - causes "import of file outside module path" error
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");

// CORRECT - use module imports
const provider_v3 = @import("provider").provider.v3;
```

**Affected packages** (non-exhaustive):
- `packages/mistral/src/*.zig`
- `packages/ai/src/**/*.zig`
- `packages/cerebras/src/*.zig`
- `packages/openai-compatible/src/*.zig`
- `packages/fireworks/src/*.zig`
- `packages/azure/src/*.zig`
- `packages/cohere/src/*.zig`
- `packages/google/src/*.zig`
- `packages/anthropic/src/*.zig`
- `packages/openai/src/*.zig`
- And likely others

### 2. Parameter Shadowing
Zig 0.15 is stricter about parameter names shadowing method names:
```zig
// WRONG
pub fn init(message: []const u8) Self { ... }
pub fn message(self: Self) []const u8 { ... }  // shadows!

// CORRECT - rename parameter
pub fn init(msg: []const u8) Self { ... }
pub fn message(self: Self) []const u8 { ... }
```

**Affected files**:
- `packages/provider/src/errors/empty-response-body-error.zig`
- `packages/provider/src/errors/load-api-key-error.zig`
- `packages/provider/src/errors/load-setting-error.zig`
- `packages/provider/src/errors/no-content-generated-error.zig`

### 3. Var vs Const
```zig
// WRONG - Zig 0.15 error: "local variable is never mutated"
var embeddings = allocator.alloc(...);

// CORRECT
const embeddings = allocator.alloc(...);
```

**Affected files**:
- `packages/mistral/src/mistral-embedding-model.zig`
- `packages/openai-compatible/src/openai-compatible-embedding-model.zig`
- `packages/cohere/src/cohere-embedding-model.zig`
- `packages/cohere/src/cohere-reranking-model.zig`

### 4. Pointless Discards
```zig
// WRONG - Zig 0.15 error: "pointless discard of local variable"
_ = headers;  // when headers is actually used

// CORRECT - remove the discard or restructure the code
```

**Affected files**:
- `packages/mistral/src/mistral-chat-language-model.zig`
- `packages/cohere/src/cohere-chat-language-model.zig`
- `packages/ai/src/generate-object/generate-object.zig`

### 5. Missing Exports
```zig
// packages/provider/src/index.zig references isJson but it may not exist
pub const isJson = json_value.isJson;
```

### 6. @fieldParentPtr API Change
```zig
// WRONG - Zig 0.15 changed the API
const self = @fieldParentPtr(Type, "field", ptr);

// CORRECT - new API takes 2 args
const self = @fieldParentPtr(ptr, @offsetOf(Type, "field"));
// OR depending on usage pattern, restructure the code
```

**Affected files**:
- `packages/ai/src/middleware/middleware.zig`

### 7. Union Tag Type Access
```zig
// WRONG
JsonValue.null.isNull()

// May need to check how union methods are called in Zig 0.15
```

## Workflow

1. Run `zig build test 2>&1 | head -100`
2. Identify the first few errors
3. Fix them systematically
4. Repeat until ALL tests pass

## Important Commands

```bash
# Run all tests
zig build test

# Check specific file syntax
zig ast-check packages/provider/src/index.zig

# Test a single package (if needed for isolation)
zig test packages/provider/src/index.zig
```

## Module Structure Reference

The build.zig defines these modules that should be used for imports:
- `provider` → packages/provider/src/index.zig
- `provider-utils` → packages/provider-utils/src/index.zig
- `openai-compatible` → packages/openai-compatible/src/index.zig
- `openai` → packages/openai/src/index.zig
- `ai` → packages/ai/src/index.zig

## Success Criteria

**The task is ONLY complete when:**
```bash
zig build test
```
**Outputs something like:**
```
All X tests passed.
```

**With ZERO compilation errors.**

## DO NOT:
- Stop after fixing just some errors
- Report "tests added successfully" without actually running them
- Skip any package or leave it broken
- Give up due to complexity

## DO:
- Fix ALL errors, no matter how many iterations it takes
- Use subagents/parallel work where possible
- Be systematic - work through packages one by one if needed
- Verify each fix by re-running tests
- Keep going until `zig build test` succeeds completely
