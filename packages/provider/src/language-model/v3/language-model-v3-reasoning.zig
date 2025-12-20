const std = @import("std");
const shared = @import("../../shared/v3/index.zig");

/// Reasoning that the model has generated.
pub const LanguageModelV3Reasoning = struct {
    /// The type identifier (always "reasoning")
    type: Type = .reasoning,

    /// The reasoning text.
    text: []const u8,

    /// Optional provider-specific metadata for the reasoning part.
    provider_metadata: ?shared.SharedV3ProviderMetadata = null,

    pub const Type = enum {
        reasoning,

        pub fn toString(self: Type) []const u8 {
            return switch (self) {
                .reasoning => "reasoning",
            };
        }
    };

    const Self = @This();

    /// Create new reasoning content
    pub fn init(text: []const u8) Self {
        return .{
            .text = text,
        };
    }

    /// Create reasoning content with provider metadata
    pub fn initWithMetadata(text: []const u8, metadata: shared.SharedV3ProviderMetadata) Self {
        return .{
            .text = text,
            .provider_metadata = metadata,
        };
    }

    /// Clone the reasoning content
    pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
        return .{
            .type = self.type,
            .text = try allocator.dupe(u8, self.text),
            .provider_metadata = if (self.provider_metadata) |pm| try pm.clone(allocator) else null,
        };
    }

    /// Free memory allocated for this reasoning content
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        if (self.provider_metadata) |*pm| {
            pm.deinit();
        }
    }
};

test "LanguageModelV3Reasoning basic" {
    const reasoning = LanguageModelV3Reasoning.init("Let me think about this...");
    try std.testing.expectEqualStrings("Let me think about this...", reasoning.text);
    try std.testing.expectEqual(LanguageModelV3Reasoning.Type.reasoning, reasoning.type);
}
