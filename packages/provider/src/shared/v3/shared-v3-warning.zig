const std = @import("std");

/// Warning from the model.
///
/// For example, that certain features are unsupported or compatibility
/// functionality is used (which might lead to suboptimal results).
pub const SharedV3Warning = union(enum) {
    /// A feature is not supported by the model.
    unsupported: UnsupportedWarning,
    /// A compatibility feature is used that might lead to suboptimal results.
    compatibility: CompatibilityWarning,
    /// Other warning.
    other: OtherWarning,

    pub const UnsupportedWarning = struct {
        /// The feature that is not supported.
        feature: []const u8,
        /// Additional details about the warning.
        details: ?[]const u8 = null,
    };

    pub const CompatibilityWarning = struct {
        /// The feature that is used in a compatibility mode.
        feature: []const u8,
        /// Additional details about the warning.
        details: ?[]const u8 = null,
    };

    pub const OtherWarning = struct {
        /// The message of the warning.
        message: []const u8,
    };

    /// Create an unsupported feature warning
    pub fn unsupportedFeature(feature: []const u8, details: ?[]const u8) SharedV3Warning {
        return .{ .unsupported = .{
            .feature = feature,
            .details = details,
        } };
    }

    /// Create a compatibility warning
    pub fn compatibilityMode(feature: []const u8, details: ?[]const u8) SharedV3Warning {
        return .{ .compatibility = .{
            .feature = feature,
            .details = details,
        } };
    }

    /// Create an other warning
    pub fn otherWarning(message: []const u8) SharedV3Warning {
        return .{ .other = .{
            .message = message,
        } };
    }

    /// Get the warning type as a string
    pub fn warningType(self: SharedV3Warning) []const u8 {
        return switch (self) {
            .unsupported => "unsupported",
            .compatibility => "compatibility",
            .other => "other",
        };
    }

    /// Get a human-readable description of the warning
    pub fn describe(self: SharedV3Warning, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        const writer = list.writer(allocator);

        switch (self) {
            .unsupported => |w| {
                try writer.print("Unsupported feature: {s}", .{w.feature});
                if (w.details) |d| {
                    try writer.print(" ({s})", .{d});
                }
            },
            .compatibility => |w| {
                try writer.print("Compatibility mode: {s}", .{w.feature});
                if (w.details) |d| {
                    try writer.print(" ({s})", .{d});
                }
            },
            .other => |w| {
                try writer.print("Warning: {s}", .{w.message});
            },
        }

        return list.toOwnedSlice(allocator);
    }
};

test "SharedV3Warning unsupported" {
    const warning = SharedV3Warning.unsupportedFeature("streaming", "Model does not support streaming");
    try std.testing.expectEqualStrings("unsupported", warning.warningType());

    switch (warning) {
        .unsupported => |w| {
            try std.testing.expectEqualStrings("streaming", w.feature);
            try std.testing.expectEqualStrings("Model does not support streaming", w.details.?);
        },
        else => unreachable,
    }
}

test "SharedV3Warning compatibility" {
    const warning = SharedV3Warning.compatibilityMode("function calling", null);
    try std.testing.expectEqualStrings("compatibility", warning.warningType());
}

test "SharedV3Warning other" {
    const warning = SharedV3Warning.otherWarning("Something went wrong");
    try std.testing.expectEqualStrings("other", warning.warningType());
}
