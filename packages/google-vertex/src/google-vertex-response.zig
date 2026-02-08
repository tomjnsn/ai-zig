const std = @import("std");

/// Response from Vertex AI embedding predict endpoint
/// Uses different structure than Google's embedContent endpoint
pub const VertexPredictEmbeddingResponse = struct {
    predictions: ?[]Prediction = null,
    metadata: ?Metadata = null,

    pub const Prediction = struct {
        embeddings: ?Embeddings = null,
    };

    pub const Embeddings = struct {
        values: ?[]f32 = null,
        statistics: ?Statistics = null,
    };

    pub const Statistics = struct {
        truncated: ?bool = null,
        token_count: ?u32 = null,
    };

    pub const Metadata = struct {
        billableCharacterCount: ?u32 = null,
    };

    /// Parse response from JSON string
    pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(VertexPredictEmbeddingResponse) {
        return try std.json.parseFromSlice(VertexPredictEmbeddingResponse, allocator, json_str, .{
            .ignore_unknown_fields = true,
        });
    }
};

/// Response from Vertex AI image predict endpoint
pub const VertexPredictImageResponse = struct {
    predictions: ?[]Prediction = null,

    pub const Prediction = struct {
        bytesBase64Encoded: ?[]const u8 = null,
        mimeType: ?[]const u8 = null,
    };

    /// Parse response from JSON string
    pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(VertexPredictImageResponse) {
        return try std.json.parseFromSlice(VertexPredictImageResponse, allocator, json_str, .{
            .ignore_unknown_fields = true,
        });
    }
};

// Tests

test "VertexPredictEmbeddingResponse parsing" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "predictions": [
        \\    {
        \\      "embeddings": {
        \\        "values": [0.1, 0.2, 0.3],
        \\        "statistics": {
        \\          "truncated": false,
        \\          "token_count": 5
        \\        }
        \\      }
        \\    }
        \\  ],
        \\  "metadata": {
        \\    "billableCharacterCount": 100
        \\  }
        \\}
    ;

    const parsed = try VertexPredictEmbeddingResponse.fromJson(allocator, json);
    defer parsed.deinit();

    try std.testing.expect(parsed.value.predictions != null);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.predictions.?.len);

    const pred = parsed.value.predictions.?[0];
    try std.testing.expect(pred.embeddings != null);
    try std.testing.expect(pred.embeddings.?.values != null);
    try std.testing.expectEqual(@as(usize, 3), pred.embeddings.?.values.?.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), pred.embeddings.?.values.?[0], 0.001);
}

test "VertexPredictImageResponse parsing" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "predictions": [
        \\    {
        \\      "bytesBase64Encoded": "aW1hZ2VkYXRh",
        \\      "mimeType": "image/png"
        \\    },
        \\    {
        \\      "bytesBase64Encoded": "aW1hZ2VkYXRhMg==",
        \\      "mimeType": "image/png"
        \\    }
        \\  ]
        \\}
    ;

    const parsed = try VertexPredictImageResponse.fromJson(allocator, json);
    defer parsed.deinit();

    try std.testing.expect(parsed.value.predictions != null);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.predictions.?.len);
    try std.testing.expectEqualStrings("aW1hZ2VkYXRh", parsed.value.predictions.?[0].bytesBase64Encoded.?);
    try std.testing.expectEqualStrings("image/png", parsed.value.predictions.?[0].mimeType.?);
}
