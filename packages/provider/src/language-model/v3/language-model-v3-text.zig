const std = @import("std");
const shared = @import("../../shared/v3/index.zig");

/// Text that the model has generated.
pub const LanguageModelV3Text = struct {
    /// The type identifier (always "text")
    type: Type = .text,

    /// The text content.
    text: []const u8,

    /// Optional provider-specific metadata for the text part.
    provider_metadata: ?shared.SharedV3ProviderMetadata = null,

    pub const Type = enum {
        text,

        pub fn toString(self: Type) []const u8 {
            return switch (self) {
                .text => "text",
            };
        }
    };

    const Self = @This();

    /// Create a new text content
    pub fn init(text: []const u8) Self {
        return .{
            .text = text,
        };
    }

    /// Create text content with provider metadata
    pub fn initWithMetadata(text: []const u8, metadata: shared.SharedV3ProviderMetadata) Self {
        return .{
            .text = text,
            .provider_metadata = metadata,
        };
    }

    /// Clone the text content
    pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
        return .{
            .type = self.type,
            .text = try allocator.dupe(u8, self.text),
            .provider_metadata = if (self.provider_metadata) |pm| try pm.clone(allocator) else null,
        };
    }

    /// Free memory allocated for this text content
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        if (self.provider_metadata) |*pm| {
            pm.deinit();
        }
    }
};

test "LanguageModelV3Text basic" {
    const text = LanguageModelV3Text.init("Hello, world!");
    try std.testing.expectEqualStrings("Hello, world!", text.text);
    try std.testing.expectEqual(LanguageModelV3Text.Type.text, text.type);
}
