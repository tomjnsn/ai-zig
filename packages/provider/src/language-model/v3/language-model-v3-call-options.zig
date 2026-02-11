const std = @import("std");
const json_value = @import("../../json-value/index.zig");
const shared = @import("../../shared/v3/index.zig");
const LanguageModelV3Prompt = @import("language-model-v3-prompt.zig").LanguageModelV3Prompt;
const LanguageModelV3FunctionTool = @import("language-model-v3-function-tool.zig").LanguageModelV3FunctionTool;
const LanguageModelV3ProviderTool = @import("language-model-v3-provider-tool.zig").LanguageModelV3ProviderTool;
const LanguageModelV3ToolChoice = @import("language-model-v3-tool-choice.zig").LanguageModelV3ToolChoice;
const ErrorDiagnostic = @import("../../errors/diagnostic.zig").ErrorDiagnostic;

/// Options for calling a language model.
pub const LanguageModelV3CallOptions = struct {
    /// A language model prompt is a standardized prompt type.
    /// Note: This is **not** the user-facing prompt. The AI SDK methods will map the
    /// user-facing prompt types such as chat or instruction prompts to this format.
    prompt: LanguageModelV3Prompt,

    /// Maximum number of tokens to generate.
    max_output_tokens: ?u32 = null,

    /// Temperature setting. The range depends on the provider and model.
    temperature: ?f32 = null,

    /// Stop sequences. If set, the model will stop generating text when one
    /// of the stop sequences is generated. Providers may have limits on the
    /// number of stop sequences.
    stop_sequences: ?[]const []const u8 = null,

    /// Nucleus sampling.
    top_p: ?f32 = null,

    /// Only sample from the top K options for each subsequent token.
    /// Used to remove "long tail" low probability responses.
    /// Recommended for advanced use cases only.
    top_k: ?u32 = null,

    /// Presence penalty setting. It affects the likelihood of the model to
    /// repeat information that is already in the prompt.
    presence_penalty: ?f32 = null,

    /// Frequency penalty setting. It affects the likelihood of the model
    /// to repeatedly use the same words or phrases.
    frequency_penalty: ?f32 = null,

    /// Response format. The output can either be text or JSON.
    response_format: ResponseFormat = .{ .text = .{} },

    /// The seed (integer) to use for random sampling. If set and supported
    /// by the model, calls will generate deterministic results.
    seed: ?i64 = null,

    /// The tools that are available for the model.
    tools: ?[]const Tool = null,

    /// Specifies how the tool should be selected. Defaults to 'auto'.
    tool_choice: ?LanguageModelV3ToolChoice = null,

    /// Include raw chunks in the stream. Only applicable for streaming calls.
    include_raw_chunks: bool = false,

    /// Additional HTTP headers to be sent with the request.
    /// Only applicable for HTTP-based providers.
    headers: ?std.StringHashMap([]const u8) = null,

    /// Additional provider-specific options.
    provider_options: ?shared.SharedV3ProviderOptions = null,

    /// Error diagnostic out-parameter for rich error context on failure.
    error_diagnostic: ?*ErrorDiagnostic = null,

    /// Response format options
    pub const ResponseFormat = union(enum) {
        text: TextFormat,
        json: JsonFormat,

        pub const TextFormat = struct {};

        pub const JsonFormat = struct {
            /// JSON schema that the generated output should conform to.
            schema: ?json_value.JsonValue = null,
            /// Name of output that should be generated.
            name: ?[]const u8 = null,
            /// Description of the output that should be generated.
            description: ?[]const u8 = null,
        };
    };

    /// Tool can be either a function tool or a provider tool
    pub const Tool = union(enum) {
        function: LanguageModelV3FunctionTool,
        provider: LanguageModelV3ProviderTool,

        pub fn getName(self: Tool) []const u8 {
            return switch (self) {
                .function => |f| f.name,
                .provider => |p| p.name,
            };
        }

        pub fn getType(self: Tool) []const u8 {
            return switch (self) {
                .function => "function",
                .provider => "provider",
            };
        }
    };

    const Self = @This();

    /// Create call options with just a prompt
    pub fn init(prompt: LanguageModelV3Prompt) Self {
        return .{
            .prompt = prompt,
        };
    }

    /// Create call options with common settings
    pub fn initWithSettings(
        prompt: LanguageModelV3Prompt,
        max_output_tokens: ?u32,
        temperature: ?f32,
    ) Self {
        return .{
            .prompt = prompt,
            .max_output_tokens = max_output_tokens,
            .temperature = temperature,
        };
    }

    /// Check if JSON response format is requested
    pub fn isJsonFormat(self: Self) bool {
        return self.response_format == .json;
    }

    /// Get the number of tools
    pub fn getToolCount(self: Self) usize {
        return if (self.tools) |t| t.len else 0;
    }

    /// Check if tools are available
    pub fn hasTools(self: Self) bool {
        return self.getToolCount() > 0;
    }

    /// Find a tool by name
    pub fn findTool(self: Self, name: []const u8) ?Tool {
        if (self.tools) |tools| {
            for (tools) |tool| {
                if (std.mem.eql(u8, tool.getName(), name)) {
                    return tool;
                }
            }
        }
        return null;
    }
};

test "LanguageModelV3CallOptions basic" {
    const options = LanguageModelV3CallOptions.init(&[_]@import("language-model-v3-prompt.zig").LanguageModelV3Message{});
    try std.testing.expect(options.max_output_tokens == null);
    try std.testing.expect(options.temperature == null);
    try std.testing.expect(!options.hasTools());
}

test "LanguageModelV3CallOptions with settings" {
    const options = LanguageModelV3CallOptions.initWithSettings(
        &[_]@import("language-model-v3-prompt.zig").LanguageModelV3Message{},
        1000,
        0.7,
    );
    try std.testing.expectEqual(@as(u32, 1000), options.max_output_tokens.?);
    try std.testing.expectEqual(@as(f32, 0.7), options.temperature.?);
}
