const std = @import("std");

/// OpenAI Image Model IDs
pub const OpenAIImageModelId = []const u8;

/// Well-known OpenAI image model IDs
pub const Models = struct {
    pub const dall_e_2 = "dall-e-2";
    pub const dall_e_3 = "dall-e-3";
    pub const gpt_image_1 = "gpt-image-1";
    pub const gpt_image_1_mini = "gpt-image-1-mini";
    pub const gpt_image_1_5 = "gpt-image-1.5";
};

/// Max images per call for each model
pub fn modelMaxImagesPerCall(model_id: []const u8) usize {
    if (std.mem.eql(u8, model_id, Models.dall_e_3)) {
        return 1;
    }
    if (std.mem.eql(u8, model_id, Models.dall_e_2)) {
        return 10;
    }
    if (std.mem.startsWith(u8, model_id, "gpt-image")) {
        return 10;
    }
    return 1;
}

/// Check if model has default response format
pub fn hasDefaultResponseFormat(model_id: []const u8) bool {
    return std.mem.startsWith(u8, model_id, "gpt-image");
}

/// Image size options
pub const ImageSize = enum {
    @"256x256",
    @"512x512",
    @"1024x1024",
    @"1024x1536",
    @"1536x1024",
    auto,

    pub fn toString(self: ImageSize) []const u8 {
        return switch (self) {
            .@"256x256" => "256x256",
            .@"512x512" => "512x512",
            .@"1024x1024" => "1024x1024",
            .@"1024x1536" => "1024x1536",
            .@"1536x1024" => "1536x1024",
            .auto => "auto",
        };
    }
};

/// Image quality options
pub const ImageQuality = enum {
    standard,
    low,
    medium,
    high,
    auto,
    hd,

    pub fn toString(self: ImageQuality) []const u8 {
        return switch (self) {
            .standard => "standard",
            .low => "low",
            .medium => "medium",
            .high => "high",
            .auto => "auto",
            .hd => "hd",
        };
    }
};

/// Image style options
pub const ImageStyle = enum {
    vivid,
    natural,

    pub fn toString(self: ImageStyle) []const u8 {
        return switch (self) {
            .vivid => "vivid",
            .natural => "natural",
        };
    }
};

/// Image output format options
pub const ImageOutputFormat = enum {
    png,
    jpeg,
    webp,

    pub fn toString(self: ImageOutputFormat) []const u8 {
        return switch (self) {
            .png => "png",
            .jpeg => "jpeg",
            .webp => "webp",
        };
    }
};

/// Image background options
pub const ImageBackground = enum {
    transparent,
    @"opaque",
    auto,

    pub fn toString(self: ImageBackground) []const u8 {
        return switch (self) {
            .transparent => "transparent",
            .@"opaque" => "opaque",
            .auto => "auto",
        };
    }
};

/// OpenAI Image provider options
pub const OpenAIImageProviderOptions = struct {
    /// Image quality
    quality: ?ImageQuality = null,

    /// Image style
    style: ?ImageStyle = null,

    /// A unique identifier representing your end-user
    user: ?[]const u8 = null,

    /// Output format (gpt-image-1 only)
    output_format: ?ImageOutputFormat = null,

    /// Background transparency (gpt-image-1 only)
    background: ?ImageBackground = null,

    /// Output compression level 0-100 (gpt-image-1 only)
    output_compression: ?u8 = null,
};

test "modelMaxImagesPerCall" {
    try std.testing.expectEqual(@as(usize, 1), modelMaxImagesPerCall("dall-e-3"));
    try std.testing.expectEqual(@as(usize, 10), modelMaxImagesPerCall("dall-e-2"));
    try std.testing.expectEqual(@as(usize, 10), modelMaxImagesPerCall("gpt-image-1"));
    try std.testing.expectEqual(@as(usize, 1), modelMaxImagesPerCall("unknown"));
}

test "hasDefaultResponseFormat" {
    try std.testing.expect(hasDefaultResponseFormat("gpt-image-1"));
    try std.testing.expect(hasDefaultResponseFormat("gpt-image-1-mini"));
    try std.testing.expect(hasDefaultResponseFormat("gpt-image-1.5"));
    try std.testing.expect(!hasDefaultResponseFormat("dall-e-3"));
}

test "gpt-image-1.5 model" {
    try std.testing.expectEqualStrings("gpt-image-1.5", Models.gpt_image_1_5);
    try std.testing.expectEqual(@as(usize, 10), modelMaxImagesPerCall(Models.gpt_image_1_5));
    try std.testing.expect(hasDefaultResponseFormat(Models.gpt_image_1_5));
}
