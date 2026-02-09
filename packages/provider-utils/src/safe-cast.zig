const std = @import("std");

/// Safely cast an integer value to the target type, returning an error if the
/// value is out of range. Use this instead of @intCast for external/untrusted data.
pub fn safeCast(comptime T: type, value: anytype) error{IntegerOverflow}!T {
    return std.math.cast(T, value) orelse return error.IntegerOverflow;
}

test "safeCast succeeds for valid range" {
    try std.testing.expectEqual(@as(u8, 255), try safeCast(u8, @as(u16, 255)));
    try std.testing.expectEqual(@as(u8, 0), try safeCast(u8, @as(u16, 0)));
    try std.testing.expectEqual(@as(i8, -128), try safeCast(i8, @as(i16, -128)));
    try std.testing.expectEqual(@as(i8, 127), try safeCast(i8, @as(i16, 127)));
    try std.testing.expectEqual(@as(u32, 42), try safeCast(u32, @as(u64, 42)));
}

test "safeCast returns error for overflow" {
    try std.testing.expectError(error.IntegerOverflow, safeCast(u8, @as(u16, 256)));
    try std.testing.expectError(error.IntegerOverflow, safeCast(u8, @as(u16, 1000)));
    try std.testing.expectError(error.IntegerOverflow, safeCast(i8, @as(i16, 128)));
    try std.testing.expectError(error.IntegerOverflow, safeCast(i8, @as(i16, -129)));
}

test "safeCast returns error for negative to unsigned" {
    try std.testing.expectError(error.IntegerOverflow, safeCast(u8, @as(i16, -1)));
    try std.testing.expectError(error.IntegerOverflow, safeCast(u32, @as(i64, -100)));
}
