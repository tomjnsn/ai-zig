const std = @import("std");
const json_value = @import("../../json-value/index.zig");

/// The configuration of a provider tool.
/// Provider tools are tools that are specific to a certain provider.
/// The input and output schemas are defined by the provider, and
/// some of the tools are also executed on the provider systems.
pub const LanguageModelV3ProviderTool = struct {
    /// The type of the tool (always 'provider').
    type: Type = .provider,

    /// The ID of the tool. Should follow the format `<provider-id>.<unique-tool-name>`.
    id: []const u8,

    /// The name of the tool. Unique within this model call.
    name: []const u8,

    /// The arguments for configuring the tool.
    /// Must match the expected arguments defined by the provider for this tool.
    args: json_value.JsonObject,

    pub const Type = enum {
        provider,

        pub fn toString(self: Type) []const u8 {
            return switch (self) {
                .provider => "provider",
            };
        }
    };

    const Self = @This();

    /// Create a new provider tool
    pub fn init(id: []const u8, name: []const u8, args: json_value.JsonObject) Self {
        return .{
            .id = id,
            .name = name,
            .args = args,
        };
    }

    /// Validate that the ID follows the expected format
    pub fn isValidId(id: []const u8) bool {
        // ID should be in format: provider-id.tool-name
        if (std.mem.indexOfScalar(u8, id, '.')) |dot_idx| {
            return dot_idx > 0 and dot_idx < id.len - 1;
        }
        return false;
    }

    /// Get the provider ID from the tool ID
    pub fn getProviderId(self: Self) ?[]const u8 {
        if (std.mem.indexOfScalar(u8, self.id, '.')) |dot_idx| {
            return self.id[0..dot_idx];
        }
        return null;
    }

    /// Get the tool name from the tool ID
    pub fn getToolNameFromId(self: Self) ?[]const u8 {
        if (std.mem.indexOfScalar(u8, self.id, '.')) |dot_idx| {
            return self.id[dot_idx + 1 ..];
        }
        return null;
    }

    /// Clone the provider tool
    pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
        return .{
            .type = self.type,
            .id = try allocator.dupe(u8, self.id),
            .name = try allocator.dupe(u8, self.name),
            .args = try self.args.clone(allocator),
        };
    }

    /// Free memory allocated for this provider tool
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        self.args.deinit();
    }
};

test "LanguageModelV3ProviderTool basic" {
    var args = json_value.JsonObject.init(std.testing.allocator);
    defer args.deinit();

    const tool = LanguageModelV3ProviderTool.init(
        "openai.code_interpreter",
        "code_interpreter",
        args,
    );
    try std.testing.expectEqualStrings("openai.code_interpreter", tool.id);
    try std.testing.expectEqualStrings("code_interpreter", tool.name);
    try std.testing.expectEqual(LanguageModelV3ProviderTool.Type.provider, tool.type);
}

test "LanguageModelV3ProviderTool isValidId" {
    try std.testing.expect(LanguageModelV3ProviderTool.isValidId("openai.code_interpreter"));
    try std.testing.expect(LanguageModelV3ProviderTool.isValidId("anthropic.search"));
    try std.testing.expect(!LanguageModelV3ProviderTool.isValidId("invalid"));
    try std.testing.expect(!LanguageModelV3ProviderTool.isValidId(".invalid"));
    try std.testing.expect(!LanguageModelV3ProviderTool.isValidId("invalid."));
}

test "LanguageModelV3ProviderTool getProviderId" {
    var args = json_value.JsonObject.init(std.testing.allocator);
    defer args.deinit();

    const tool = LanguageModelV3ProviderTool.init(
        "openai.code_interpreter",
        "code_interpreter",
        args,
    );
    try std.testing.expectEqualStrings("openai", tool.getProviderId().?);
    try std.testing.expectEqualStrings("code_interpreter", tool.getToolNameFromId().?);
}
