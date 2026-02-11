const std = @import("std");
const shared = @import("../../shared/v3/index.zig");
const ImageModelV3File = @import("image-model-v3-file.zig").ImageModelV3File;
const ErrorDiagnostic = @import("../../errors/diagnostic.zig").ErrorDiagnostic;

/// Call options for image generation.
pub const ImageModelV3CallOptions = struct {
    /// Prompt for the image generation. Some operations, like upscaling, may not require a prompt.
    prompt: ?[]const u8 = null,

    /// Number of images to generate.
    n: u32 = 1,

    /// Size of the images to generate as "widthxheight".
    /// `null` will use the provider's default size.
    size: ?ImageSize = null,

    /// Aspect ratio of the images to generate as "width:height".
    /// `null` will use the provider's default aspect ratio.
    aspect_ratio: ?AspectRatio = null,

    /// Seed for the image generation.
    /// `null` will use the provider's default seed.
    seed: ?i64 = null,

    /// Array of images for image editing or variation generation.
    files: ?[]const ImageModelV3File = null,

    /// Mask image for inpainting operations.
    mask: ?ImageModelV3File = null,

    /// Additional provider-specific options.
    provider_options: ?shared.SharedV3ProviderOptions = null,

    /// Additional HTTP headers to be sent with the request.
    headers: ?std.StringHashMap([]const u8) = null,

    /// Error diagnostic out-parameter for rich error context on failure.
    error_diagnostic: ?*ErrorDiagnostic = null,

    /// Image size specification
    pub const ImageSize = struct {
        width: u32,
        height: u32,

        pub fn format(self: ImageSize, allocator: std.mem.Allocator) ![]u8 {
            return std.fmt.allocPrint(allocator, "{d}x{d}", .{ self.width, self.height });
        }

        pub fn parse(s: []const u8) ?ImageSize {
            const x_idx = std.mem.indexOfScalar(u8, s, 'x') orelse return null;
            const width = std.fmt.parseInt(u32, s[0..x_idx], 10) catch return null;
            const height = std.fmt.parseInt(u32, s[x_idx + 1 ..], 10) catch return null;
            return .{ .width = width, .height = height };
        }
    };

    /// Aspect ratio specification
    pub const AspectRatio = struct {
        width: u32,
        height: u32,

        pub fn format(self: AspectRatio, allocator: std.mem.Allocator) ![]u8 {
            return std.fmt.allocPrint(allocator, "{d}:{d}", .{ self.width, self.height });
        }

        pub fn parse(s: []const u8) ?AspectRatio {
            const colon_idx = std.mem.indexOfScalar(u8, s, ':') orelse return null;
            const width = std.fmt.parseInt(u32, s[0..colon_idx], 10) catch return null;
            const height = std.fmt.parseInt(u32, s[colon_idx + 1 ..], 10) catch return null;
            return .{ .width = width, .height = height };
        }

        pub fn toFloat(self: AspectRatio) f32 {
            return @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
        }
    };

    const Self = @This();

    /// Create call options with just a prompt
    pub fn init(prompt: []const u8) Self {
        return .{
            .prompt = prompt,
        };
    }

    /// Create call options with prompt and count
    pub fn initWithCount(prompt: []const u8, n: u32) Self {
        return .{
            .prompt = prompt,
            .n = n,
        };
    }

    /// Create call options with full settings
    pub fn initFull(
        prompt: ?[]const u8,
        n: u32,
        size: ?ImageSize,
        aspect_ratio: ?AspectRatio,
    ) Self {
        return .{
            .prompt = prompt,
            .n = n,
            .size = size,
            .aspect_ratio = aspect_ratio,
        };
    }
};

test "ImageModelV3CallOptions basic" {
    const options = ImageModelV3CallOptions.init("A beautiful sunset");
    try std.testing.expectEqualStrings("A beautiful sunset", options.prompt.?);
    try std.testing.expectEqual(@as(u32, 1), options.n);
}

test "ImageModelV3CallOptions ImageSize" {
    const size = ImageModelV3CallOptions.ImageSize.parse("1024x768");
    try std.testing.expectEqual(@as(u32, 1024), size.?.width);
    try std.testing.expectEqual(@as(u32, 768), size.?.height);
}

test "ImageModelV3CallOptions AspectRatio" {
    const ratio = ImageModelV3CallOptions.AspectRatio.parse("16:9");
    try std.testing.expectEqual(@as(u32, 16), ratio.?.width);
    try std.testing.expectEqual(@as(u32, 9), ratio.?.height);
    try std.testing.expectApproxEqAbs(@as(f32, 1.777), ratio.?.toFloat(), 0.01);
}
