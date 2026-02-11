const std = @import("std");
const json_value = @import("../json-value/index.zig");

/// Marker for identifying AI SDK errors
pub const ai_sdk_error_marker = "ai-sdk.zig.error";

/// AI SDK Error types as a Zig error set
pub const AiSdkError = error{
    ApiCallError,
    EmptyResponseBodyError,
    InvalidArgumentError,
    InvalidPromptError,
    InvalidResponseDataError,
    JsonParseError,
    LoadApiKeyError,
    LoadSettingError,
    NoContentGeneratedError,
    NoSuchModelError,
    TooManyEmbeddingValuesForCallError,
    TypeValidationError,
    UnsupportedFunctionalityError,
};

/// Extended error information that provides context about AI SDK errors.
/// This struct is used to carry detailed error information alongside the error code.
pub const AiSdkErrorInfo = struct {
    /// The error kind
    kind: ErrorKind,
    /// Human-readable error message
    message: []const u8,
    /// Optional underlying cause
    cause: ?*const AiSdkErrorInfo = null,
    /// Additional context specific to the error type
    context: ?ErrorContext = null,

    pub const ErrorKind = enum {
        api_call,
        empty_response_body,
        invalid_argument,
        invalid_prompt,
        invalid_response_data,
        json_parse,
        load_api_key,
        load_setting,
        no_content_generated,
        no_such_model,
        too_many_embedding_values,
        type_validation,
        unsupported_functionality,
    };

    /// Get the error name as a string
    pub fn name(self: AiSdkErrorInfo) []const u8 {
        return switch (self.kind) {
            .api_call => "AI_APICallError",
            .empty_response_body => "AI_EmptyResponseBodyError",
            .invalid_argument => "AI_InvalidArgumentError",
            .invalid_prompt => "AI_InvalidPromptError",
            .invalid_response_data => "AI_InvalidResponseDataError",
            .json_parse => "AI_JSONParseError",
            .load_api_key => "AI_LoadAPIKeyError",
            .load_setting => "AI_LoadSettingError",
            .no_content_generated => "AI_NoContentGeneratedError",
            .no_such_model => "AI_NoSuchModelError",
            .too_many_embedding_values => "AI_TooManyEmbeddingValuesForCallError",
            .type_validation => "AI_TypeValidationError",
            .unsupported_functionality => "AI_UnsupportedFunctionalityError",
        };
    }

    /// Convert to the corresponding Zig error
    pub fn toError(self: AiSdkErrorInfo) AiSdkError {
        return switch (self.kind) {
            .api_call => error.ApiCallError,
            .empty_response_body => error.EmptyResponseBodyError,
            .invalid_argument => error.InvalidArgumentError,
            .invalid_prompt => error.InvalidPromptError,
            .invalid_response_data => error.InvalidResponseDataError,
            .json_parse => error.JsonParseError,
            .load_api_key => error.LoadApiKeyError,
            .load_setting => error.LoadSettingError,
            .no_content_generated => error.NoContentGeneratedError,
            .no_such_model => error.NoSuchModelError,
            .too_many_embedding_values => error.TooManyEmbeddingValuesForCallError,
            .type_validation => error.TypeValidationError,
            .unsupported_functionality => error.UnsupportedFunctionalityError,
        };
    }

    /// Format the error for display
    pub fn format(self: AiSdkErrorInfo, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        const writer = list.writer(allocator);

        try writer.print("{s}: {s}", .{ self.name(), self.message });

        if (self.cause) |cause| {
            try writer.print("\nCaused by: {s}", .{cause.message});
        }

        return list.toOwnedSlice(allocator);
    }
};

/// Union type for error-specific context
pub const ErrorContext = union(enum) {
    api_call: ApiCallContext,
    invalid_argument: InvalidArgumentContext,
    invalid_prompt: InvalidPromptContext,
    invalid_response_data: InvalidResponseDataContext,
    json_parse: JsonParseContext,
    no_such_model: NoSuchModelContext,
    too_many_embedding_values: TooManyEmbeddingValuesContext,
    type_validation: TypeValidationContext,
    unsupported_functionality: UnsupportedFunctionalityContext,
};

/// Context for API call errors
pub const ApiCallContext = struct {
    url: []const u8,
    request_body_values: ?json_value.JsonValue = null,
    status_code: ?u16 = null,
    response_headers: ?std.StringHashMap([]const u8) = null,
    response_body: ?[]const u8 = null,
    is_retryable: bool = false,
    data: ?json_value.JsonValue = null,
};

/// Context for invalid argument errors
pub const InvalidArgumentContext = struct {
    argument: []const u8,
};

/// Context for invalid prompt errors
pub const InvalidPromptContext = struct {
    prompt: ?json_value.JsonValue = null,
};

/// Context for invalid response data errors
pub const InvalidResponseDataContext = struct {
    data: ?json_value.JsonValue = null,
};

/// Context for JSON parse errors
pub const JsonParseContext = struct {
    text: []const u8,
};

/// Context for no such model errors
pub const NoSuchModelContext = struct {
    model_id: []const u8,
    model_type: ModelType,

    pub const ModelType = enum {
        language_model,
        embedding_model,
        image_model,
        transcription_model,
        speech_model,
        reranking_model,
    };
};

/// Context for too many embedding values errors
pub const TooManyEmbeddingValuesContext = struct {
    provider: []const u8,
    model_id: []const u8,
    max_embeddings_per_call: u32,
    values_count: usize,
};

/// Context for type validation errors
pub const TypeValidationContext = struct {
    value: ?json_value.JsonValue = null,
};

/// Context for unsupported functionality errors
pub const UnsupportedFunctionalityContext = struct {
    functionality: []const u8,
};

/// Get error message from any error type
pub fn getErrorMessage(err: anyerror) []const u8 {
    return @errorName(err);
}

/// Get error message from optional error or unknown
pub fn getErrorMessageOptional(err: ?anyerror) []const u8 {
    if (err) |e| {
        return getErrorMessage(e);
    }
    return "unknown error";
}

/// Check if a status code is retryable
pub fn isRetryableStatusCode(status_code: ?u16) bool {
    if (status_code) |code| {
        return code == 408 or // request timeout
            code == 409 or // conflict
            code == 429 or // too many requests
            code >= 500; // server error
    }
    return false;
}

test "AiSdkErrorInfo basic operations" {
    const info = AiSdkErrorInfo{
        .kind = .api_call,
        .message = "Test error",
        .context = .{ .api_call = .{
            .url = "https://api.example.com",
            .status_code = 500,
            .is_retryable = true,
        } },
    };

    try std.testing.expectEqualStrings("AI_APICallError", info.name());
    try std.testing.expectEqual(AiSdkError.ApiCallError, info.toError());
}

test "isRetryableStatusCode" {
    try std.testing.expect(isRetryableStatusCode(408));
    try std.testing.expect(isRetryableStatusCode(409));
    try std.testing.expect(isRetryableStatusCode(429));
    try std.testing.expect(isRetryableStatusCode(500));
    try std.testing.expect(isRetryableStatusCode(503));
    try std.testing.expect(!isRetryableStatusCode(400));
    try std.testing.expect(!isRetryableStatusCode(404));
    try std.testing.expect(!isRetryableStatusCode(null));
}
