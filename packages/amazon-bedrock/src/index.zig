// Amazon Bedrock Provider for Zig AI SDK
//
// This module provides Amazon Bedrock API integration including:
// - Claude models (via Anthropic)
// - Amazon Titan models
// - Amazon Nova models
// - Meta Llama models
// - Mistral models
// - Cohere models
// - DeepSeek models
// - Embedding models (Titan, Cohere)
// - AWS SigV4 authentication support
// - Bearer token authentication support

// Provider
pub const provider = @import("bedrock-provider.zig");
pub const AmazonBedrockProvider = provider.AmazonBedrockProvider;
pub const AmazonBedrockProviderSettings = provider.AmazonBedrockProviderSettings;
pub const createAmazonBedrock = provider.createAmazonBedrock;
pub const createAmazonBedrockWithSettings = provider.createAmazonBedrockWithSettings;

// Configuration
pub const config = @import("bedrock-config.zig");
pub const BedrockConfig = config.BedrockConfig;
pub const BedrockCredentials = config.BedrockCredentials;
pub const buildBedrockRuntimeUrl = config.buildBedrockRuntimeUrl;
pub const buildBedrockAgentRuntimeUrl = config.buildBedrockAgentRuntimeUrl;
pub const buildConverseUrl = config.buildConverseUrl;
pub const buildConverseStreamUrl = config.buildConverseStreamUrl;
pub const buildInvokeModelUrl = config.buildInvokeModelUrl;

// Language model
pub const chat_model = @import("bedrock-chat-language-model.zig");
pub const BedrockChatLanguageModel = chat_model.BedrockChatLanguageModel;

// Embedding model
pub const embed_model = @import("bedrock-embedding-model.zig");
pub const BedrockEmbeddingModel = embed_model.BedrockEmbeddingModel;

// Options
pub const options = @import("bedrock-options.zig");
pub const ChatModels = options.ChatModels;
pub const EmbeddingModels = options.EmbeddingModels;
pub const ImageModels = options.ImageModels;
pub const RerankingModels = options.RerankingModels;
pub const StopReason = options.StopReason;
pub const ReasoningConfig = options.ReasoningConfig;
pub const BedrockProviderOptions = options.BedrockProviderOptions;
pub const isAnthropicModel = options.isAnthropicModel;
pub const isNovaModel = options.isNovaModel;
pub const supportsReasoning = options.supportsReasoning;

// Stop reason mapping
pub const map_finish = @import("map-bedrock-finish-reason.zig");
pub const mapBedrockFinishReason = map_finish.mapBedrockFinishReason;
pub const mapBedrockFinishReasonString = map_finish.mapBedrockFinishReasonString;

test {
    // Run all module tests
    @import("std").testing.refAllDecls(@This());
}
