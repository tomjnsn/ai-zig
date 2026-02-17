# Contributing to Zig AI SDK

Thank you for your interest in contributing to the Zig AI SDK!

## Development Setup

1. **Install Zig**: Ensure you have Zig 0.15.0 or later installed
   ```bash
   # Check your Zig version
   zig version
   ```

2. **Clone the repository**:
   ```bash
   git clone https://github.com/evmts/ai-zig.git
   cd ai-zig
   ```

3. **Build the project**:
   ```bash
   zig build
   ```

4. **Run tests**:
   ```bash
   zig build test
   ```

## Project Structure

- `packages/provider/` - Core provider interfaces and types
- `packages/provider-utils/` - HTTP utilities, streaming helpers
- `packages/ai/` - High-level API (generateText, streamText, etc.)
- `packages/<provider>/` - Individual provider implementations
- `examples/` - Example code
- `tests/` - Integration tests

## Adding a New Provider

1. Create a new directory under `packages/<provider-name>/src/`

2. Create the provider file following this pattern:
   ```zig
   const std = @import("std");
   const provider = @import("provider");

   pub const MyProviderSettings = struct {
       base_url: ?[]const u8 = null,
       api_key: ?[]const u8 = null,
   };

   pub const MyProvider = struct {
       allocator: std.mem.Allocator,
       settings: MyProviderSettings,
       base_url: []const u8,

       pub const specification_version = "v3";

       pub fn init(allocator: std.mem.Allocator, settings: MyProviderSettings) @This() {
           return .{
               .allocator = allocator,
               .settings = settings,
               .base_url = settings.base_url orelse "https://api.example.com",
           };
       }

       pub fn deinit(self: *@This()) void {
           _ = self;
       }

       pub fn getProvider(self: *const @This()) []const u8 {
           _ = self;
           return "my-provider";
       }

       pub fn languageModel(self: *@This(), model_id: []const u8) MyLanguageModel {
           return MyLanguageModel.init(self.allocator, model_id, self.base_url);
       }
   };
   ```

3. Create an `index.zig` that re-exports the public API:
   ```zig
   pub const provider = @import("my-provider.zig");
   pub const MyProvider = provider.MyProvider;
   pub const MyProviderSettings = provider.MyProviderSettings;
   pub const createMyProvider = provider.createMyProvider;

   test {
       @import("std").testing.refAllDecls(@This());
   }
   ```

4. Add the provider to `build.zig` — add an entry to the `test_configs` array and create a module with appropriate imports. See existing providers in `build.zig` for the current pattern.

5. Add tests in the provider file and integration tests

## Code Style

- Follow Zig's standard naming conventions
- Use `snake_case` for functions and variables
- Use `PascalCase` for types
- Add doc comments for public APIs using `///`
- Keep functions focused and small
- Use descriptive parameter names

## Memory Management

- Use arena allocators for request-scoped data
- Document ownership in function signatures
- Avoid memory leaks by properly deinitializing resources
- Use `defer` for cleanup operations

Example:
```zig
pub fn processRequest(allocator: std.mem.Allocator) !Result {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();
    // Use arena_allocator for temporary allocations

    // Return result allocated with the original allocator
    return Result.init(allocator);
}
```

## Testing

- Write unit tests for all public functions
- Use `std.testing` for assertions
- Test error conditions as well as happy paths
- Run tests with `zig build test`

Example test:
```zig
test "MyProvider basic" {
    const allocator = std.testing.allocator;
    var provider = createMyProvider(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("my-provider", provider.getProvider());
}
```

## Pull Request Process

1. Ensure all tests pass (`zig build test`)
2. Ensure the build succeeds (`zig build`)
3. Update documentation if needed
4. Add a clear description of your changes
5. Reference any related issues

## Reporting Bugs

1. Check if the issue already exists
2. Create a new issue with:
   - Clear title and description
   - Steps to reproduce
   - Expected vs actual behavior
   - Zig version and platform

## Questions?

Feel free to open an issue for questions or discussions.
