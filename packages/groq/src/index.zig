// Groq Provider for Zig AI SDK
//
// This module provides Groq API integration including:
// - Chat models (Llama 3.3, Mixtral, Gemma, etc.)
// - Reasoning models (DeepSeek R1, QwQ, etc.)
// - Transcription models (Whisper)
// - OpenAI-compatible API format
// - Bearer token authentication support

// Provider
pub const provider = @import("groq-provider.zig");
pub const GroqProvider = provider.GroqProvider;
pub const GroqProviderSettings = provider.GroqProviderSettings;
pub const createGroq = provider.createGroq;
pub const createGroqWithSettings = provider.createGroqWithSettings;

// Configuration
pub const config = @import("groq-config.zig");
pub const GroqConfig = config.GroqConfig;
pub const buildChatCompletionsUrl = config.buildChatCompletionsUrl;
pub const buildTranscriptionsUrl = config.buildTranscriptionsUrl;

// Language model
pub const chat_model = @import("groq-chat-language-model.zig");
pub const GroqChatLanguageModel = chat_model.GroqChatLanguageModel;

// Transcription model
pub const transcription = @import("groq-transcription-model.zig");
pub const GroqTranscriptionModel = transcription.GroqTranscriptionModel;

// Options
pub const options = @import("groq-options.zig");
pub const ChatModels = options.ChatModels;
pub const TranscriptionModels = options.TranscriptionModels;
pub const ReasoningFormat = options.ReasoningFormat;
pub const ReasoningEffort = options.ReasoningEffort;
pub const ServiceTier = options.ServiceTier;
pub const GroqProviderOptions = options.GroqProviderOptions;
pub const supportsReasoning = options.supportsReasoning;

// Finish reason mapping
pub const map_finish = @import("map-groq-finish-reason.zig");
pub const mapGroqFinishReason = map_finish.mapGroqFinishReason;

test {
    // Run all module tests
    @import("std").testing.refAllDecls(@This());
}
