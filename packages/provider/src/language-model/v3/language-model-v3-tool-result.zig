const std = @import("std");
const json_value = @import("../../json-value/index.zig");
const shared = @import("../../shared/v3/index.zig");

/// Result of a tool call that has been executed by the provider.
pub const LanguageModelV3ToolResult = struct {
    /// The type identifier (always "tool-result")
    type: Type = .tool_result,

    /// The ID of the tool call that this result is associated with.
    tool_call_id: []const u8,

    /// Name of the tool that generated this result.
    tool_name: []const u8,

    /// Result of the tool call. This is a JSON value.
    result: json_value.JsonValue,

    /// Optional flag if the result is an error or an error message.
    is_error: bool = false,

    /// Whether the tool result is preliminary.
    /// Preliminary tool results replace each other, e.g. image previews.
    /// There always has to be a final, non-preliminary tool result.
    preliminary: bool = false,

    /// Whether the tool is dynamic, i.e. defined at runtime.
    /// For example, MCP (Model Context Protocol) tools that are executed by the provider.
    dynamic: bool = false,

    /// Additional provider-specific metadata for the tool result.
    provider_metadata: ?shared.SharedV3ProviderMetadata = null,

    pub const Type = enum {
        tool_result,

        pub fn toString(self: Type) []const u8 {
            return switch (self) {
                .tool_result => "tool-result",
            };
        }
    };

    const Self = @This();

    /// Create a new tool result
    pub fn init(tool_call_id: []const u8, tool_name: []const u8, result: json_value.JsonValue) Self {
        return .{
            .tool_call_id = tool_call_id,
            .tool_name = tool_name,
            .result = result,
        };
    }

    /// Create an error tool result
    pub fn initError(tool_call_id: []const u8, tool_name: []const u8, error_result: json_value.JsonValue) Self {
        return .{
            .tool_call_id = tool_call_id,
            .tool_name = tool_name,
            .result = error_result,
            .is_error = true,
        };
    }

    /// Create a preliminary tool result
    pub fn initPreliminary(tool_call_id: []const u8, tool_name: []const u8, result: json_value.JsonValue) Self {
        return .{
            .tool_call_id = tool_call_id,
            .tool_name = tool_name,
            .result = result,
            .preliminary = true,
        };
    }

    /// Clone the tool result
    pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
        return .{
            .type = self.type,
            .tool_call_id = try allocator.dupe(u8, self.tool_call_id),
            .tool_name = try allocator.dupe(u8, self.tool_name),
            .result = try self.result.clone(allocator),
            .is_error = self.is_error,
            .preliminary = self.preliminary,
            .dynamic = self.dynamic,
            .provider_metadata = if (self.provider_metadata) |pm| try pm.clone(allocator) else null,
        };
    }

    /// Free memory allocated for this tool result
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.tool_call_id);
        allocator.free(self.tool_name);
        self.result.deinit(allocator);
        if (self.provider_metadata) |*pm| {
            pm.deinit();
        }
    }
};

test "LanguageModelV3ToolResult basic" {
    const result = LanguageModelV3ToolResult.init(
        "call-1",
        "search",
        json_value.JsonValue{ .string = "Search results here" },
    );
    try std.testing.expectEqualStrings("call-1", result.tool_call_id);
    try std.testing.expectEqualStrings("search", result.tool_name);
    try std.testing.expect(!result.is_error);
    try std.testing.expect(!result.preliminary);
}

test "LanguageModelV3ToolResult error" {
    const result = LanguageModelV3ToolResult.initError(
        "call-2",
        "api_call",
        json_value.JsonValue{ .string = "Connection failed" },
    );
    try std.testing.expect(result.is_error);
}
