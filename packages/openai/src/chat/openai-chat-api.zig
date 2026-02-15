const std = @import("std");
const json_value = @import("provider").json_value;

/// OpenAI Chat completion response
pub const OpenAIChatResponse = struct {
    id: []const u8,
    object: []const u8,
    created: i64,
    model: []const u8,
    choices: []const Choice,
    usage: ?Usage = null,
    system_fingerprint: ?[]const u8 = null,
    service_tier: ?[]const u8 = null,

    pub const Choice = struct {
        index: u32,
        message: Message,
        finish_reason: ?[]const u8 = null,
        logprobs: ?Logprobs = null,
    };

    pub const Message = struct {
        role: []const u8,
        content: ?[]const u8 = null,
        refusal: ?[]const u8 = null,
        tool_calls: ?[]const ToolCall = null,
        annotations: ?[]const Annotation = null,
    };

    pub const ToolCall = struct {
        id: ?[]const u8 = null,
        type: []const u8,
        function: Function,
    };

    pub const Function = struct {
        name: []const u8,
        arguments: ?[]const u8 = null,
    };

    pub const Annotation = struct {
        url_citation: UrlCitation,
    };

    pub const UrlCitation = struct {
        url: []const u8,
        title: ?[]const u8 = null,
    };

    pub const Logprobs = struct {
        content: ?[]const LogprobContent = null,
    };

    pub const LogprobContent = struct {
        token: []const u8,
        logprob: f64,
        top_logprobs: ?[]const TopLogprob = null,
    };

    pub const TopLogprob = struct {
        token: []const u8,
        logprob: f64,
    };

    pub const Usage = struct {
        prompt_tokens: u64,
        completion_tokens: u64,
        total_tokens: u64,
        prompt_tokens_details: ?PromptTokensDetails = null,
        completion_tokens_details: ?CompletionTokensDetails = null,
    };

    pub const PromptTokensDetails = struct {
        cached_tokens: ?u64 = null,
        audio_tokens: ?u64 = null,
    };

    pub const CompletionTokensDetails = struct {
        reasoning_tokens: ?u64 = null,
        audio_tokens: ?u64 = null,
        accepted_prediction_tokens: ?u64 = null,
        rejected_prediction_tokens: ?u64 = null,
    };
};

/// OpenAI Chat streaming chunk
pub const OpenAIChatChunk = struct {
    id: ?[]const u8 = null,
    object: ?[]const u8 = null,
    created: ?i64 = null,
    model: ?[]const u8 = null,
    choices: []const ChunkChoice = &[_]ChunkChoice{},
    usage: ?OpenAIChatResponse.Usage = null,
    system_fingerprint: ?[]const u8 = null,
    service_tier: ?[]const u8 = null,

    /// Error field for error chunks
    @"error": ?ChunkError = null,

    pub const ChunkError = struct {
        message: []const u8,
        type: ?[]const u8 = null,
        code: ?[]const u8 = null,
    };

    pub const ChunkChoice = struct {
        index: u32,
        delta: Delta,
        finish_reason: ?[]const u8 = null,
        logprobs: ?OpenAIChatResponse.Logprobs = null,
    };

    pub const Delta = struct {
        role: ?[]const u8 = null,
        content: ?[]const u8 = null,
        refusal: ?[]const u8 = null,
        tool_calls: ?[]const DeltaToolCall = null,
        annotations: ?[]const OpenAIChatResponse.Annotation = null,
    };

    pub const DeltaToolCall = struct {
        index: u32,
        id: ?[]const u8 = null,
        type: ?[]const u8 = null,
        function: ?DeltaFunction = null,
    };

    pub const DeltaFunction = struct {
        name: ?[]const u8 = null,
        arguments: ?[]const u8 = null,
    };
};

/// OpenAI Chat completion request body
pub const OpenAIChatRequest = struct {
    model: []const u8,
    messages: []const RequestMessage,

    // Generation parameters
    max_tokens: ?u32 = null,
    max_completion_tokens: ?u32 = null,
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    frequency_penalty: ?f32 = null,
    presence_penalty: ?f32 = null,
    stop: ?[]const []const u8 = null,
    seed: ?i64 = null,

    // Response format
    response_format: ?ResponseFormat = null,

    // Tool related
    tools: ?[]const Tool = null,
    tool_choice: ?ToolChoice = null,
    parallel_tool_calls: ?bool = null,

    // Streaming
    stream: bool = false,
    stream_options: ?StreamOptions = null,

    // OpenAI specific
    logit_bias: ?std.StringHashMap(f32) = null,
    logprobs: ?bool = null,
    top_logprobs: ?u32 = null,
    user: ?[]const u8 = null,
    store: ?bool = null,
    metadata: ?std.StringHashMap([]const u8) = null,
    reasoning_effort: ?[]const u8 = null,
    service_tier: ?[]const u8 = null,
    verbosity: ?[]const u8 = null,

    pub const RequestMessage = struct {
        role: []const u8,
        content: ?MessageContent = null,
        name: ?[]const u8 = null,
        tool_calls: ?[]const OpenAIChatResponse.ToolCall = null,
        tool_call_id: ?[]const u8 = null,
    };

    pub const MessageContent = union(enum) {
        text: []const u8,
        parts: []const ContentPart,
    };

    pub const ContentPart = union(enum) {
        text: TextPart,
        image_url: ImageUrlPart,
    };

    pub const TextPart = struct {
        type: []const u8 = "text",
        text: []const u8,
    };

    pub const ImageUrlPart = struct {
        type: []const u8 = "image_url",
        image_url: ImageUrl,
    };

    pub const ImageUrl = struct {
        url: []const u8,
        detail: ?[]const u8 = null,
    };

    pub const ResponseFormat = union(enum) {
        text: struct { type: []const u8 = "text" },
        json_object: struct { type: []const u8 = "json_object" },
        json_schema: JsonSchemaFormat,
    };

    pub const JsonSchemaFormat = struct {
        type: []const u8 = "json_schema",
        json_schema: JsonSchema,
    };

    pub const JsonSchema = struct {
        schema: json_value.JsonValue,
        strict: bool = true,
        name: []const u8,
        description: ?[]const u8 = null,
    };

    pub const Tool = struct {
        type: []const u8 = "function",
        function: ToolFunction,
    };

    pub const ToolFunction = struct {
        name: []const u8,
        description: ?[]const u8 = null,
        parameters: ?json_value.JsonValue = null,
        strict: ?bool = null,
    };

    pub const ToolChoice = union(enum) {
        auto: []const u8,
        none: []const u8,
        required: []const u8,
        function: ToolChoiceFunction,
    };

    pub const ToolChoiceFunction = struct {
        type: []const u8 = "function",
        function: struct {
            name: []const u8,
        },
    };

    pub const StreamOptions = struct {
        include_usage: bool = true,
    };
};

/// Convert OpenAI usage to language model usage
pub const OpenAIChatUsage = OpenAIChatResponse.Usage;

pub fn convertOpenAIChatUsage(usage: ?OpenAIChatUsage) @import("provider").language_model.LanguageModelV3Usage {
    const LanguageModelV3Usage = @import("provider").language_model.LanguageModelV3Usage;

    if (usage) |u| {
        return .{
            .input_tokens = .{
                .total = u.prompt_tokens,
                .cache_read = if (u.prompt_tokens_details) |d| d.cached_tokens else null,
            },
            .output_tokens = .{
                .total = u.completion_tokens,
                .reasoning = if (u.completion_tokens_details) |d| d.reasoning_tokens else null,
            },
        };
    }

    return LanguageModelV3Usage.init();
}

test "convertOpenAIChatUsage" {
    const usage = OpenAIChatUsage{
        .prompt_tokens = 100,
        .completion_tokens = 50,
        .total_tokens = 150,
        .completion_tokens_details = .{
            .reasoning_tokens = 20,
        },
    };

    const result = convertOpenAIChatUsage(usage);
    try std.testing.expectEqual(@as(u64, 100), result.input_tokens.total.?);
    try std.testing.expectEqual(@as(u64, 50), result.output_tokens.total.?);
    try std.testing.expectEqual(@as(u64, 20), result.output_tokens.reasoning.?);
}
