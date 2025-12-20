const std = @import("std");
const shared = @import("../../shared/v3/index.zig");

/// An image file that can be used for image editing or variation generation.
pub const ImageModelV3File = union(enum) {
    /// File with binary or base64 data
    file: FileData,
    /// File referenced by URL
    url: UrlData,

    pub const FileData = struct {
        /// The IANA media type of the file, e.g. `image/png`.
        media_type: []const u8,

        /// File data as base64 encoded string or binary data.
        data: Data,

        /// Optional provider-specific metadata.
        provider_options: ?shared.SharedV3ProviderMetadata = null,

        pub const Data = union(enum) {
            base64: []const u8,
            binary: []const u8,
        };
    };

    pub const UrlData = struct {
        /// The URL of the image file.
        url: []const u8,

        /// Optional provider-specific metadata.
        provider_options: ?shared.SharedV3ProviderMetadata = null,
    };

    const Self = @This();

    /// Create a file from base64 data
    pub fn fromBase64(media_type: []const u8, data: []const u8) Self {
        return .{
            .file = .{
                .media_type = media_type,
                .data = .{ .base64 = data },
            },
        };
    }

    /// Create a file from binary data
    pub fn fromBinary(media_type: []const u8, data: []const u8) Self {
        return .{
            .file = .{
                .media_type = media_type,
                .data = .{ .binary = data },
            },
        };
    }

    /// Create a file from URL
    pub fn fromUrl(url: []const u8) Self {
        return .{
            .url = .{
                .url = url,
            },
        };
    }

    /// Check if this is a URL reference
    pub fn isUrl(self: Self) bool {
        return self == .url;
    }

    /// Check if this is file data
    pub fn isFile(self: Self) bool {
        return self == .file;
    }

    /// Get the URL if this is a URL reference
    pub fn getUrl(self: Self) ?[]const u8 {
        return switch (self) {
            .url => |u| u.url,
            .file => null,
        };
    }

    /// Get the media type if this is file data
    pub fn getMediaType(self: Self) ?[]const u8 {
        return switch (self) {
            .file => |f| f.media_type,
            .url => null,
        };
    }

    /// Clone the file
    pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
        return switch (self) {
            .file => |f| .{
                .file = .{
                    .media_type = try allocator.dupe(u8, f.media_type),
                    .data = switch (f.data) {
                        .base64 => |d| .{ .base64 = try allocator.dupe(u8, d) },
                        .binary => |d| .{ .binary = try allocator.dupe(u8, d) },
                    },
                    .provider_options = if (f.provider_options) |po| try po.clone(allocator) else null,
                },
            },
            .url => |u| .{
                .url = .{
                    .url = try allocator.dupe(u8, u.url),
                    .provider_options = if (u.provider_options) |po| try po.clone(allocator) else null,
                },
            },
        };
    }

    /// Free memory
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .file => |*f| {
                allocator.free(f.media_type);
                switch (f.data) {
                    .base64 => |d| allocator.free(d),
                    .binary => |d| allocator.free(d),
                }
                if (f.provider_options) |*po| {
                    po.deinit();
                }
            },
            .url => |*u| {
                allocator.free(u.url);
                if (u.provider_options) |*po| {
                    po.deinit();
                }
            },
        }
    }
};

test "ImageModelV3File url" {
    const file = ImageModelV3File.fromUrl("https://example.com/image.png");
    try std.testing.expect(file.isUrl());
    try std.testing.expectEqualStrings("https://example.com/image.png", file.getUrl().?);
}

test "ImageModelV3File binary" {
    const file = ImageModelV3File.fromBinary("image/png", &[_]u8{ 0x89, 0x50, 0x4E, 0x47 });
    try std.testing.expect(file.isFile());
    try std.testing.expectEqualStrings("image/png", file.getMediaType().?);
}
