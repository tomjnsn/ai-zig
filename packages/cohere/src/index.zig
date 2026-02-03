// Cohere Provider for Zig AI SDK
//
// This module provides Cohere API integration including:
// - Chat models (Command R, Command R+, etc.)
// - Reasoning models (Command A Reasoning)
// - Embedding models (embed-english-v3.0, embed-multilingual-v3.0, etc.)
// - Reranking models (rerank-v3.5, etc.)
// - Bearer token authentication support

// Provider
pub const provider = @import("cohere-provider.zig");
pub const CohereProvider = provider.CohereProvider;
pub const CohereProviderSettings = provider.CohereProviderSettings;
pub const createCohere = provider.createCohere;
pub const createCohereWithSettings = provider.createCohereWithSettings;

// Configuration
pub const config = @import("cohere-config.zig");
pub const CohereConfig = config.CohereConfig;
pub const buildChatUrl = config.buildChatUrl;
pub const buildEmbedUrl = config.buildEmbedUrl;
pub const buildRerankUrl = config.buildRerankUrl;

// Language model
pub const chat_model = @import("cohere-chat-language-model.zig");
pub const CohereChatLanguageModel = chat_model.CohereChatLanguageModel;

// Embedding model
pub const embed_model = @import("cohere-embedding-model.zig");
pub const CohereEmbeddingModel = embed_model.CohereEmbeddingModel;

// Reranking model
pub const rerank_model = @import("cohere-reranking-model.zig");
pub const CohereRerankingModel = rerank_model.CohereRerankingModel;

// Options
pub const options = @import("cohere-options.zig");
pub const ChatModels = options.ChatModels;
pub const EmbeddingModels = options.EmbeddingModels;
pub const RerankingModels = options.RerankingModels;
pub const ThinkingConfig = options.ThinkingConfig;
pub const ThinkingType = options.ThinkingType;
pub const CohereChatModelOptions = options.CohereChatModelOptions;
pub const EmbeddingInputType = options.EmbeddingInputType;
pub const EmbeddingTruncate = options.EmbeddingTruncate;
pub const CohereEmbeddingOptions = options.CohereEmbeddingOptions;
pub const CohereRerankingOptions = options.CohereRerankingOptions;
pub const supportsReasoning = options.supportsReasoning;

// Error handling
pub const errors = @import("cohere-error.zig");
pub const CohereErrorData = errors.CohereErrorData;
pub const parseCohereError = errors.parseCohereError;
pub const formatCohereError = errors.formatCohereError;

// Finish reason mapping
pub const map_finish = @import("map-cohere-finish-reason.zig");
pub const mapCohereFinishReason = map_finish.mapCohereFinishReason;

test {
    // Run all module tests
    @import("std").testing.refAllDecls(@This());
}
