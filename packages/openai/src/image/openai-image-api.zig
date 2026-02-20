const std = @import("std");

/// OpenAI Image Generation Response
pub const OpenAIImageResponse = struct {
    created: ?i64 = null,
    data: []const ImageData,
    usage: ?Usage = null,
    size: ?[]const u8 = null,
    quality: ?[]const u8 = null,
    background: ?[]const u8 = null,
    output_format: ?[]const u8 = null,

    pub const ImageData = struct {
        b64_json: []const u8,
        url: ?[]const u8 = null,
        revised_prompt: ?[]const u8 = null,
    };

    pub const TokensDetails = struct {
        image_tokens: ?u64 = null,
        text_tokens: ?u64 = null,
    };

    pub const Usage = struct {
        input_tokens: ?u64 = null,
        input_tokens_details: ?TokensDetails = null,
        output_tokens: ?u64 = null,
        output_tokens_details: ?TokensDetails = null,
        total_tokens: ?u64 = null,
    };
};

/// OpenAI Image Generation Request
pub const OpenAIImageGenerationRequest = struct {
    model: []const u8,
    prompt: []const u8,
    n: ?u32 = null,
    size: ?[]const u8 = null,
    quality: ?[]const u8 = null,
    style: ?[]const u8 = null,
    response_format: ?[]const u8 = null,
    user: ?[]const u8 = null,
    background: ?[]const u8 = null,
    output_format: ?[]const u8 = null,
    output_compression: ?u8 = null,
};

/// OpenAI Image Edit Request (multipart form)
pub const OpenAIImageEditRequest = struct {
    model: []const u8,
    prompt: []const u8,
    n: ?u32 = null,
    size: ?[]const u8 = null,
    quality: ?[]const u8 = null,
    background: ?[]const u8 = null,
    output_format: ?[]const u8 = null,
    output_compression: ?u8 = null,
    user: ?[]const u8 = null,
};

/// Convert OpenAI image usage to standard format
pub const ImageUsage = struct {
    input_tokens: ?u64 = null,
    output_tokens: ?u64 = null,
    total_tokens: ?u64 = null,
};

pub fn convertUsage(usage: ?OpenAIImageResponse.Usage) ?ImageUsage {
    if (usage) |u| {
        return .{
            .input_tokens = u.input_tokens,
            .output_tokens = u.output_tokens,
            .total_tokens = u.total_tokens,
        };
    }
    return null;
}

test "convertUsage" {
    const usage = OpenAIImageResponse.Usage{
        .input_tokens = 100,
        .output_tokens = 200,
        .total_tokens = 300,
    };
    const result = convertUsage(usage);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(?u64, 100), result.?.input_tokens);
    try std.testing.expectEqual(@as(?u64, 200), result.?.output_tokens);
}
