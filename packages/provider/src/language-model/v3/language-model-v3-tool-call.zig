const std = @import("std");
const shared = @import("../../shared/v3/index.zig");

/// Tool calls that the model has generated.
pub const LanguageModelV3ToolCall = struct {
    /// The type identifier (always "tool-call")
    type: Type = .tool_call,

    /// The identifier of the tool call. It must be unique across all tool calls.
    tool_call_id: []const u8,

    /// The name of the tool that should be called.
    tool_name: []const u8,

    /// Stringified JSON object with the tool call arguments.
    /// Must match the parameters schema of the tool.
    input: []const u8,

    /// Whether the tool call will be executed by the provider.
    /// If this flag is not set or is false, the tool call will be executed by the client.
    provider_executed: bool = false,

    /// Whether the tool is dynamic, i.e. defined at runtime.
    /// For example, MCP (Model Context Protocol) tools that are executed by the provider.
    dynamic: bool = false,

    /// Additional provider-specific metadata for the tool call.
    provider_metadata: ?shared.SharedV3ProviderMetadata = null,

    pub const Type = enum {
        tool_call,

        pub fn toString(self: Type) []const u8 {
            return switch (self) {
                .tool_call => "tool-call",
            };
        }
    };

    const Self = @This();

    /// Create a new tool call
    pub fn init(tool_call_id: []const u8, tool_name: []const u8, input: []const u8) Self {
        return .{
            .tool_call_id = tool_call_id,
            .tool_name = tool_name,
            .input = input,
        };
    }

    /// Create a tool call that will be executed by the provider
    pub fn initProviderExecuted(tool_call_id: []const u8, tool_name: []const u8, input: []const u8) Self {
        return .{
            .tool_call_id = tool_call_id,
            .tool_name = tool_name,
            .input = input,
            .provider_executed = true,
        };
    }

    /// Clone the tool call
    pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
        return .{
            .type = self.type,
            .tool_call_id = try allocator.dupe(u8, self.tool_call_id),
            .tool_name = try allocator.dupe(u8, self.tool_name),
            .input = try allocator.dupe(u8, self.input),
            .provider_executed = self.provider_executed,
            .dynamic = self.dynamic,
            .provider_metadata = if (self.provider_metadata) |pm| try pm.clone(allocator) else null,
        };
    }

    /// Free memory allocated for this tool call
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.tool_call_id);
        allocator.free(self.tool_name);
        allocator.free(self.input);
        if (self.provider_metadata) |*pm| {
            pm.deinit();
        }
    }
};

test "LanguageModelV3ToolCall basic" {
    const tool_call = LanguageModelV3ToolCall.init("call-1", "search", "{\"query\": \"hello\"}");
    try std.testing.expectEqualStrings("call-1", tool_call.tool_call_id);
    try std.testing.expectEqualStrings("search", tool_call.tool_name);
    try std.testing.expectEqualStrings("{\"query\": \"hello\"}", tool_call.input);
    try std.testing.expect(!tool_call.provider_executed);
}

test "LanguageModelV3ToolCall provider_executed" {
    const tool_call = LanguageModelV3ToolCall.initProviderExecuted("call-2", "code_exec", "{}");
    try std.testing.expect(tool_call.provider_executed);
}
