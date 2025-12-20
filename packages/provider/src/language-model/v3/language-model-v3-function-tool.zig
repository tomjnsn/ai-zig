const std = @import("std");
const json_value = @import("../../json-value/index.zig");
const shared = @import("../../shared/v3/index.zig");

/// A tool has a name, a description, and a set of parameters.
/// Note: this is **not** the user-facing tool definition. The AI SDK methods will
/// map the user-facing tool definitions to this format.
pub const LanguageModelV3FunctionTool = struct {
    /// The type of the tool (always 'function').
    type: Type = .function,

    /// The name of the tool. Unique within this model call.
    name: []const u8,

    /// A description of the tool. The language model uses this to understand the
    /// tool's purpose and to provide better completion suggestions.
    description: ?[]const u8 = null,

    /// The parameters that the tool expects. The language model uses this to
    /// understand the tool's input requirements and to provide matching suggestions.
    /// This is a JSON Schema (draft-07).
    input_schema: json_value.JsonValue,

    /// An optional list of input examples that show the language
    /// model what the input should look like.
    input_examples: ?[]const InputExample = null,

    /// Strict mode setting for the tool.
    /// Providers that support strict mode will use this setting to determine
    /// how the input should be generated. Strict mode will always produce
    /// valid inputs, but it might limit what input schemas are supported.
    strict: bool = false,

    /// The provider-specific options for the tool.
    provider_options: ?shared.SharedV3ProviderOptions = null,

    pub const Type = enum {
        function,

        pub fn toString(self: Type) []const u8 {
            return switch (self) {
                .function => "function",
            };
        }
    };

    /// Input example for a tool
    pub const InputExample = struct {
        input: json_value.JsonObject,
    };

    const Self = @This();

    /// Create a new function tool
    pub fn init(name: []const u8, input_schema: json_value.JsonValue) Self {
        return .{
            .name = name,
            .input_schema = input_schema,
        };
    }

    /// Create a function tool with description
    pub fn initWithDescription(
        name: []const u8,
        description: []const u8,
        input_schema: json_value.JsonValue,
    ) Self {
        return .{
            .name = name,
            .description = description,
            .input_schema = input_schema,
        };
    }

    /// Clone the function tool
    pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
        var cloned_examples: ?[]InputExample = null;
        if (self.input_examples) |examples| {
            cloned_examples = try allocator.alloc(InputExample, examples.len);
            for (examples, 0..) |example, i| {
                cloned_examples.?[i] = .{
                    .input = try example.input.clone(allocator),
                };
            }
        }

        return .{
            .type = self.type,
            .name = try allocator.dupe(u8, self.name),
            .description = if (self.description) |d| try allocator.dupe(u8, d) else null,
            .input_schema = try self.input_schema.clone(allocator),
            .input_examples = cloned_examples,
            .strict = self.strict,
            .provider_options = if (self.provider_options) |po| try po.clone(allocator) else null,
        };
    }

    /// Free memory allocated for this function tool
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.description) |d| allocator.free(d);
        self.input_schema.deinit(allocator);
        if (self.input_examples) |examples| {
            for (examples) |*example| {
                example.input.deinit();
            }
            allocator.free(examples);
        }
        if (self.provider_options) |*po| {
            po.deinit();
        }
    }
};

test "LanguageModelV3FunctionTool basic" {
    const tool = LanguageModelV3FunctionTool.init(
        "search",
        json_value.JsonValue{ .object = json_value.JsonObject.init(std.testing.allocator) },
    );
    try std.testing.expectEqualStrings("search", tool.name);
    try std.testing.expectEqual(LanguageModelV3FunctionTool.Type.function, tool.type);
}
