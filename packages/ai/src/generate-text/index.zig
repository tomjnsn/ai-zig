// Generate Text Module for Zig AI SDK
//
// This module provides text generation capabilities:
// - generateText: Non-streaming text generation
// - streamText: Streaming text generation with callbacks

pub const generate_text_mod = @import("generate-text.zig");
pub const stream_text_mod = @import("stream-text.zig");

// Re-export generateText types
pub const generateText = generate_text_mod.generateText;
pub const GenerateTextResult = generate_text_mod.GenerateTextResult;
pub const GenerateTextOptions = generate_text_mod.GenerateTextOptions;
pub const GenerateTextError = generate_text_mod.GenerateTextError;

// Re-export common types
pub const FinishReason = generate_text_mod.FinishReason;
pub const LanguageModelUsage = generate_text_mod.LanguageModelUsage;
pub const ToolCall = generate_text_mod.ToolCall;
pub const ToolResult = generate_text_mod.ToolResult;
pub const ContentPart = generate_text_mod.ContentPart;
pub const TextPart = generate_text_mod.TextPart;
pub const ReasoningPart = generate_text_mod.ReasoningPart;
pub const FilePart = generate_text_mod.FilePart;
pub const ResponseMetadata = generate_text_mod.ResponseMetadata;
pub const StepResult = generate_text_mod.StepResult;
pub const CallSettings = generate_text_mod.CallSettings;
pub const MessageRole = generate_text_mod.MessageRole;
pub const MessageContent = generate_text_mod.MessageContent;
pub const Message = generate_text_mod.Message;
pub const ToolDefinition = generate_text_mod.ToolDefinition;
pub const ToolChoice = generate_text_mod.ToolChoice;

// Re-export streamText types
pub const streamText = stream_text_mod.streamText;
pub const StreamTextResult = stream_text_mod.StreamTextResult;
pub const StreamTextOptions = stream_text_mod.StreamTextOptions;
pub const StreamTextError = stream_text_mod.StreamTextError;
pub const StreamCallbacks = stream_text_mod.StreamCallbacks;
pub const StreamPart = stream_text_mod.StreamPart;
pub const TextDelta = stream_text_mod.TextDelta;
pub const ReasoningDelta = stream_text_mod.ReasoningDelta;
pub const ToolCallStart = stream_text_mod.ToolCallStart;
pub const ToolCallDelta = stream_text_mod.ToolCallDelta;
pub const StepFinish = stream_text_mod.StepFinish;
pub const StepType = stream_text_mod.StepType;
pub const StreamFinish = stream_text_mod.StreamFinish;
pub const StreamError = stream_text_mod.StreamError;

pub const toGenerateTextResult = stream_text_mod.toGenerateTextResult;

// Builders
pub const builder_mod = @import("builder.zig");
pub const TextGenerationBuilder = builder_mod.TextGenerationBuilder;
pub const StreamTextBuilder = builder_mod.StreamTextBuilder;

test {
    @import("std").testing.refAllDecls(@This());
}
