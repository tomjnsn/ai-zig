const std = @import("std");

/// Response from Google Generative AI generateContent API
pub const GoogleGenerateContentResponse = struct {
    candidates: ?[]Candidate = null,
    usageMetadata: ?UsageMetadata = null,
    promptFeedback: ?PromptFeedback = null,
    modelVersion: ?[]const u8 = null,

    pub const Candidate = struct {
        content: ?Content = null,
        finishReason: ?[]const u8 = null,
        safetyRatings: ?[]SafetyRating = null,
        citationMetadata: ?CitationMetadata = null,
        index: ?u32 = null,
        groundingMetadata: ?GroundingMetadata = null,
        avgLogprobs: ?f64 = null,
        logprobsResult: ?LogprobsResult = null,
        tokenCount: ?u32 = null,
    };

    pub const Content = struct {
        parts: ?[]Part = null,
        role: ?[]const u8 = null,
    };

    pub const Part = struct {
        text: ?[]const u8 = null,
        functionCall: ?FunctionCall = null,
        functionResponse: ?FunctionResponse = null,
        executableCode: ?ExecutableCode = null,
        codeExecutionResult: ?CodeExecutionResult = null,
        inlineData: ?InlineData = null,
        thought: ?bool = null,
    };

    pub const FunctionCall = struct {
        name: []const u8,
        args: ?std.json.Value = null,
    };

    pub const FunctionResponse = struct {
        name: []const u8,
        response: ?std.json.Value = null,
    };

    pub const ExecutableCode = struct {
        language: ?[]const u8 = null,
        code: ?[]const u8 = null,
    };

    pub const CodeExecutionResult = struct {
        outcome: ?[]const u8 = null,
        output: ?[]const u8 = null,
    };

    pub const InlineData = struct {
        mimeType: ?[]const u8 = null,
        data: ?[]const u8 = null,
    };

    pub const SafetyRating = struct {
        category: ?[]const u8 = null,
        probability: ?[]const u8 = null,
        blocked: ?bool = null,
    };

    pub const CitationMetadata = struct {
        citationSources: ?[]CitationSource = null,
    };

    pub const CitationSource = struct {
        startIndex: ?u32 = null,
        endIndex: ?u32 = null,
        uri: ?[]const u8 = null,
        license: ?[]const u8 = null,
    };

    pub const GroundingMetadata = struct {
        webSearchQueries: ?[][]const u8 = null,
        searchEntryPoint: ?SearchEntryPoint = null,
        groundingChunks: ?[]GroundingChunk = null,
        groundingSupports: ?[]GroundingSupport = null,
        retrievalMetadata: ?RetrievalMetadata = null,
    };

    pub const SearchEntryPoint = struct {
        renderedContent: ?[]const u8 = null,
        sdkBlob: ?[]const u8 = null,
    };

    pub const GroundingChunk = struct {
        web: ?WebChunk = null,
        retrievedContext: ?RetrievedContext = null,
    };

    pub const WebChunk = struct {
        uri: ?[]const u8 = null,
        title: ?[]const u8 = null,
    };

    pub const RetrievedContext = struct {
        uri: ?[]const u8 = null,
        title: ?[]const u8 = null,
        text: ?[]const u8 = null,
    };

    pub const GroundingSupport = struct {
        segment: ?Segment = null,
        groundingChunkIndices: ?[]u32 = null,
        confidenceScores: ?[]f64 = null,
    };

    pub const Segment = struct {
        partIndex: ?u32 = null,
        startIndex: ?u32 = null,
        endIndex: ?u32 = null,
        text: ?[]const u8 = null,
    };

    pub const RetrievalMetadata = struct {
        googleSearchDynamicRetrievalScore: ?f64 = null,
    };

    pub const LogprobsResult = struct {
        topCandidates: ?[]TopCandidates = null,
        chosenCandidates: ?[]LogprobsCandidate = null,
    };

    pub const TopCandidates = struct {
        candidates: ?[]LogprobsCandidate = null,
    };

    pub const LogprobsCandidate = struct {
        token: ?[]const u8 = null,
        tokenId: ?u32 = null,
        logProbability: ?f64 = null,
    };

    pub const UsageMetadata = struct {
        promptTokenCount: ?u32 = null,
        candidatesTokenCount: ?u32 = null,
        totalTokenCount: ?u32 = null,
        cachedContentTokenCount: ?u32 = null,
        thoughtsTokenCount: ?u32 = null,
        toolUsePromptTokenCount: ?u32 = null,
    };

    pub const PromptFeedback = struct {
        blockReason: ?[]const u8 = null,
        safetyRatings: ?[]SafetyRating = null,
    };

    /// Parse response from JSON string
    pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(GoogleGenerateContentResponse) {
        return try std.json.parseFromSlice(GoogleGenerateContentResponse, allocator, json_str, .{
            .ignore_unknown_fields = true,
        });
    }
};

/// Response from Google Generative AI embedContent API
pub const GoogleEmbedContentResponse = struct {
    embedding: ?Embedding = null,

    pub const Embedding = struct {
        values: ?[]f32 = null,
    };

    /// Parse response from JSON string
    pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(GoogleEmbedContentResponse) {
        return try std.json.parseFromSlice(GoogleEmbedContentResponse, allocator, json_str, .{
            .ignore_unknown_fields = true,
        });
    }
};

/// Response from Google Generative AI batchEmbedContents API
pub const GoogleBatchEmbedContentsResponse = struct {
    embeddings: ?[]Embedding = null,

    pub const Embedding = struct {
        values: ?[]f32 = null,
    };

    /// Parse response from JSON string
    pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(GoogleBatchEmbedContentsResponse) {
        return try std.json.parseFromSlice(GoogleBatchEmbedContentsResponse, allocator, json_str, .{
            .ignore_unknown_fields = true,
        });
    }
};

/// Response from Google Imagen predict API
pub const GooglePredictResponse = struct {
    predictions: ?[]Prediction = null,

    pub const Prediction = struct {
        bytesBase64Encoded: ?[]const u8 = null,
        mimeType: ?[]const u8 = null,
    };

    /// Parse response from JSON string
    pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(GooglePredictResponse) {
        return try std.json.parseFromSlice(GooglePredictResponse, allocator, json_str, .{
            .ignore_unknown_fields = true,
        });
    }
};

// Tests

test "GoogleGenerateContentResponse parsing - basic text" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "candidates": [{
        \\    "content": {
        \\      "parts": [{"text": "Hello, world!"}],
        \\      "role": "model"
        \\    },
        \\    "finishReason": "STOP"
        \\  }],
        \\  "usageMetadata": {
        \\    "promptTokenCount": 5,
        \\    "candidatesTokenCount": 3,
        \\    "totalTokenCount": 8
        \\  }
        \\}
    ;

    const parsed = try GoogleGenerateContentResponse.fromJson(allocator, json);
    defer parsed.deinit();

    try std.testing.expect(parsed.value.candidates != null);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.candidates.?.len);

    const candidate = parsed.value.candidates.?[0];
    try std.testing.expect(candidate.content != null);
    try std.testing.expect(candidate.content.?.parts != null);
    try std.testing.expectEqualStrings("Hello, world!", candidate.content.?.parts.?[0].text.?);
    try std.testing.expectEqualStrings("STOP", candidate.finishReason.?);

    try std.testing.expect(parsed.value.usageMetadata != null);
    try std.testing.expectEqual(@as(u32, 5), parsed.value.usageMetadata.?.promptTokenCount.?);
    try std.testing.expectEqual(@as(u32, 3), parsed.value.usageMetadata.?.candidatesTokenCount.?);
}

test "GoogleGenerateContentResponse parsing - function call" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "candidates": [{
        \\    "content": {
        \\      "parts": [{
        \\        "functionCall": {
        \\          "name": "get_weather",
        \\          "args": {"location": "San Francisco"}
        \\        }
        \\      }],
        \\      "role": "model"
        \\    },
        \\    "finishReason": "STOP"
        \\  }]
        \\}
    ;

    const parsed = try GoogleGenerateContentResponse.fromJson(allocator, json);
    defer parsed.deinit();

    const part = parsed.value.candidates.?[0].content.?.parts.?[0];
    try std.testing.expect(part.functionCall != null);
    try std.testing.expectEqualStrings("get_weather", part.functionCall.?.name);
}

test "GoogleEmbedContentResponse parsing" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "embedding": {
        \\    "values": [0.1, 0.2, 0.3, 0.4, 0.5]
        \\  }
        \\}
    ;

    const parsed = try GoogleEmbedContentResponse.fromJson(allocator, json);
    defer parsed.deinit();

    try std.testing.expect(parsed.value.embedding != null);
    try std.testing.expect(parsed.value.embedding.?.values != null);
    try std.testing.expectEqual(@as(usize, 5), parsed.value.embedding.?.values.?.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), parsed.value.embedding.?.values.?[0], 0.001);
}

test "GoogleBatchEmbedContentsResponse parsing" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "embeddings": [
        \\    {"values": [0.1, 0.2]},
        \\    {"values": [0.3, 0.4]}
        \\  ]
        \\}
    ;

    const parsed = try GoogleBatchEmbedContentsResponse.fromJson(allocator, json);
    defer parsed.deinit();

    try std.testing.expect(parsed.value.embeddings != null);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.embeddings.?.len);
}

test "GooglePredictResponse parsing" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "predictions": [
        \\    {"bytesBase64Encoded": "aW1hZ2VkYXRh", "mimeType": "image/png"}
        \\  ]
        \\}
    ;

    const parsed = try GooglePredictResponse.fromJson(allocator, json);
    defer parsed.deinit();

    try std.testing.expect(parsed.value.predictions != null);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.predictions.?.len);
    try std.testing.expectEqualStrings("aW1hZ2VkYXRh", parsed.value.predictions.?[0].bytesBase64Encoded.?);
    try std.testing.expectEqualStrings("image/png", parsed.value.predictions.?[0].mimeType.?);
}
