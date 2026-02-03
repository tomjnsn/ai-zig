// Mistral Provider for Zig AI SDK
//
// This module provides Mistral API integration including:
// - Chat models (Mistral Large, Medium, Small, etc.)
// - Reasoning models (Magistral)
// - Vision models (Pixtral)
// - Embedding models (mistral-embed)
// - Bearer token authentication support

// Provider
pub const provider = @import("mistral-provider.zig");
pub const MistralProvider = provider.MistralProvider;
pub const MistralProviderSettings = provider.MistralProviderSettings;
pub const createMistral = provider.createMistral;
pub const createMistralWithSettings = provider.createMistralWithSettings;

// Configuration
pub const config = @import("mistral-config.zig");
pub const MistralConfig = config.MistralConfig;
pub const buildChatCompletionsUrl = config.buildChatCompletionsUrl;
pub const buildEmbeddingsUrl = config.buildEmbeddingsUrl;

// Language model
pub const chat_model = @import("mistral-chat-language-model.zig");
pub const MistralChatLanguageModel = chat_model.MistralChatLanguageModel;

// Embedding model
pub const embed_model = @import("mistral-embedding-model.zig");
pub const MistralEmbeddingModel = embed_model.MistralEmbeddingModel;

// Options
pub const options = @import("mistral-options.zig");
pub const ChatModels = options.ChatModels;
pub const EmbeddingModels = options.EmbeddingModels;
pub const MistralLanguageModelOptions = options.MistralLanguageModelOptions;
pub const MistralToolChoice = options.MistralToolChoice;
pub const ResponseFormatType = options.ResponseFormatType;
pub const supportsReasoning = options.supportsReasoning;
pub const supportsVision = options.supportsVision;

// Error handling
pub const errors = @import("mistral-error.zig");
pub const MistralErrorData = errors.MistralErrorData;
pub const parseMistralError = errors.parseMistralError;
pub const formatMistralError = errors.formatMistralError;

// Finish reason mapping
pub const map_finish = @import("map-mistral-finish-reason.zig");
pub const mapMistralFinishReason = map_finish.mapMistralFinishReason;

// Tool preparation
pub const prepare_tools = @import("mistral-prepare-tools.zig");
pub const PreparedTools = prepare_tools.PreparedTools;
pub const MistralTool = prepare_tools.MistralTool;
pub const MistralFunction = prepare_tools.MistralFunction;
pub const prepareTools = prepare_tools.prepareTools;
pub const serializeToolsToJson = prepare_tools.serializeToolsToJson;

test {
    // Run all module tests
    @import("std").testing.refAllDecls(@This());
}
