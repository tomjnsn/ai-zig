const std = @import("std");
const provider_types = @import("provider");

const ImageModelV3 = provider_types.ImageModelV3;

/// Token/credit usage for image generation
pub const ImageGenerationUsage = struct {
    images: ?u32 = null,
    credits: ?f64 = null,
};

/// Generated image representation
pub const GeneratedImage = struct {
    /// Base64-encoded image data
    base64: ?[]const u8 = null,

    /// URL to the generated image
    url: ?[]const u8 = null,

    /// MIME type of the image
    mime_type: []const u8 = "image/png",

    /// Revised prompt (if model modified it)
    revised_prompt: ?[]const u8 = null,

    /// Get image data (either decode base64 or fetch URL)
    pub fn getData(self: *const GeneratedImage, allocator: std.mem.Allocator) ![]const u8 {
        if (self.base64) |b64| {
            const decoder = std.base64.standard.Decoder;
            const size = decoder.calcSizeForSlice(b64) catch return error.InvalidBase64;
            const buffer = try allocator.alloc(u8, size);
            decoder.decode(buffer, b64) catch return error.InvalidBase64;
            return buffer;
        }
        // URL fetching would require HTTP client
        return error.NoImageData;
    }
};

/// Response metadata for image generation
pub const ImageResponseMetadata = struct {
    id: ?[]const u8 = null,
    model_id: []const u8,
    timestamp: ?i64 = null,
    headers: ?std.StringHashMap([]const u8) = null,
};

/// Result of generateImage
pub const GenerateImageResult = struct {
    /// The generated images
    images: []const GeneratedImage,

    /// Usage information
    usage: ImageGenerationUsage,

    /// Response metadata
    response: ImageResponseMetadata,

    /// Warnings from the model
    warnings: ?[]const []const u8 = null,

    /// Get the first image (convenience method)
    pub fn getImage(self: *const GenerateImageResult) ?GeneratedImage {
        if (self.images.len > 0) {
            return self.images[0];
        }
        return null;
    }

    pub fn deinit(self: *GenerateImageResult, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Arena allocator handles cleanup
    }
};

/// Image size options
pub const ImageSize = union(enum) {
    /// Standard preset sizes
    preset: PresetSize,
    /// Custom dimensions
    custom: CustomSize,
};

pub const PresetSize = enum {
    small, // 256x256
    medium, // 512x512
    large, // 1024x1024
    wide, // 1792x1024
    tall, // 1024x1792
};

pub const CustomSize = struct {
    width: u32,
    height: u32,
};

/// Image quality options
pub const ImageQuality = enum {
    standard,
    hd,
};

/// Image style options
pub const ImageStyle = enum {
    natural,
    vivid,
};

/// Options for generateImage
pub const GenerateImageOptions = struct {
    /// The image model to use
    model: *ImageModelV3,

    /// The prompt describing the image to generate
    prompt: []const u8,

    /// Negative prompt (what to avoid)
    negative_prompt: ?[]const u8 = null,

    /// Number of images to generate
    n: u32 = 1,

    /// Image size
    size: ?ImageSize = null,

    /// Image quality
    quality: ImageQuality = .standard,

    /// Image style
    style: ImageStyle = .natural,

    /// Random seed for reproducibility
    seed: ?u64 = null,

    /// Maximum retries on failure
    max_retries: u32 = 2,

    /// Additional headers
    headers: ?std.StringHashMap([]const u8) = null,

    /// Provider-specific options
    provider_options: ?std.json.Value = null,
};

/// Error types for image generation
pub const GenerateImageError = error{
    ModelError,
    NetworkError,
    InvalidPrompt,
    ContentFiltered,
    TooManyImages,
    Cancelled,
    OutOfMemory,
};

/// Generate images using an image model
pub fn generateImage(
    allocator: std.mem.Allocator,
    options: GenerateImageOptions,
) GenerateImageError!GenerateImageResult {
    // Validate input
    if (options.prompt.len == 0) {
        return GenerateImageError.InvalidPrompt;
    }

    // Build call options for the provider
    const call_options = provider_types.ImageModelV3CallOptions{
        .prompt = options.prompt,
        .n = options.n,
        .seed = if (options.seed) |s| @as(i64, @intCast(s)) else null,
    };

    // Call model.doGenerate
    const CallbackCtx = struct { result: ?ImageModelV3.GenerateResult = null };
    var cb_ctx = CallbackCtx{};
    const ctx_ptr: *anyopaque = @ptrCast(&cb_ctx);

    options.model.doGenerate(
        call_options,
        allocator,
        struct {
            fn onResult(ptr: ?*anyopaque, result: ImageModelV3.GenerateResult) void {
                const ctx: *CallbackCtx = @ptrCast(@alignCast(ptr.?));
                ctx.result = result;
            }
        }.onResult,
        ctx_ptr,
    );

    const gen_success = switch (cb_ctx.result orelse return GenerateImageError.ModelError) {
        .success => |s| s,
        .failure => return GenerateImageError.ModelError,
    };

    // Convert provider images to ai-level GeneratedImage
    const image_data = switch (gen_success.images) {
        .base64 => |base64_images| base64_images,
        .binary => |_| return GenerateImageError.ModelError, // TODO: handle binary
    };

    const images = allocator.alloc(GeneratedImage, image_data.len) catch return GenerateImageError.OutOfMemory;
    for (image_data, 0..) |b64, i| {
        images[i] = .{
            .base64 = b64,
            .mime_type = "image/png",
        };
    }

    return GenerateImageResult{
        .images = images,
        .usage = .{
            .images = @as(u32, @intCast(image_data.len)),
        },
        .response = .{
            .model_id = gen_success.response.model_id,
            .timestamp = gen_success.response.timestamp,
        },
        .warnings = null,
    };
}

/// Get dimensions for a preset size
pub fn getPresetDimensions(preset: PresetSize) CustomSize {
    return switch (preset) {
        .small => .{ .width = 256, .height = 256 },
        .medium => .{ .width = 512, .height = 512 },
        .large => .{ .width = 1024, .height = 1024 },
        .wide => .{ .width = 1792, .height = 1024 },
        .tall => .{ .width = 1024, .height = 1792 },
    };
}

test "GenerateImageOptions default values" {
    const model: ImageModelV3 = undefined;
    const options = GenerateImageOptions{
        .model = @constCast(&model),
        .prompt = "A beautiful sunset",
    };
    try std.testing.expect(options.n == 1);
    try std.testing.expect(options.quality == .standard);
    try std.testing.expect(options.style == .natural);
}

test "getPresetDimensions" {
    const large = getPresetDimensions(.large);
    try std.testing.expectEqual(@as(u32, 1024), large.width);
    try std.testing.expectEqual(@as(u32, 1024), large.height);

    const wide = getPresetDimensions(.wide);
    try std.testing.expectEqual(@as(u32, 1792), wide.width);
    try std.testing.expectEqual(@as(u32, 1024), wide.height);
}

test "generateImage returns image from mock provider" {
    const MockImageModel = struct {
        const Self = @This();

        const mock_base64 = [_][]const u8{"aW1hZ2VfZGF0YQ=="}; // "image_data" in base64

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-image";
        }

        pub fn getMaxImagesPerCall(
            _: *const Self,
            callback: *const fn (?*anyopaque, ?u32) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, 4);
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.ImageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, ImageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .success = .{
                .images = .{ .base64 = &mock_base64 },
                .response = .{
                    .timestamp = 1234567890,
                    .model_id = "mock-image",
                },
            } });
        }
    };

    var mock = MockImageModel{};
    var model = provider_types.asImageModel(MockImageModel, &mock);

    const result = try generateImage(std.testing.allocator, .{
        .model = &model,
        .prompt = "A beautiful sunset",
    });
    defer std.testing.allocator.free(result.images);

    // Should have 1 image
    try std.testing.expectEqual(@as(usize, 1), result.images.len);

    // Should have base64 data
    try std.testing.expect(result.images[0].base64 != null);
    try std.testing.expectEqualStrings("aW1hZ2VfZGF0YQ==", result.images[0].base64.?);

    // Should have model ID from provider
    try std.testing.expectEqualStrings("mock-image", result.response.model_id);
}

test "GeneratedImage.getData decodes base64" {
    const image = GeneratedImage{
        .base64 = "SGVsbG8gV29ybGQ=", // "Hello World"
    };

    const data = try image.getData(std.testing.allocator);
    defer std.testing.allocator.free(data);

    try std.testing.expectEqualStrings("Hello World", data);
}

test "GeneratedImage.getData returns error for no data" {
    const image = GeneratedImage{};

    const result = image.getData(std.testing.allocator);
    try std.testing.expectError(error.NoImageData, result);
}

test "generateImage returns error on empty prompt" {
    const MockImg = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-img";
        }

        pub fn getMaxImagesPerCall(
            _: *const Self,
            callback: *const fn (?*anyopaque, ?u32) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, 4);
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.ImageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, ImageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.ModelError });
        }
    };

    var mock = MockImg{};
    var model = provider_types.asImageModel(MockImg, &mock);

    const result = generateImage(std.testing.allocator, .{
        .model = &model,
        .prompt = "",
    });

    try std.testing.expectError(GenerateImageError.InvalidPrompt, result);
}

test "generateImage returns error on model failure" {
    const MockFailImg = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-fail-img";
        }

        pub fn getMaxImagesPerCall(
            _: *const Self,
            callback: *const fn (?*anyopaque, ?u32) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, 4);
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.ImageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, ImageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.ModelError });
        }
    };

    var mock = MockFailImg{};
    var model = provider_types.asImageModel(MockFailImg, &mock);

    const result = generateImage(std.testing.allocator, .{
        .model = &model,
        .prompt = "Generate a cat image",
    });

    try std.testing.expectError(GenerateImageError.ModelError, result);
}
