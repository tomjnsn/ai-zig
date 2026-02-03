// Together AI Provider for Zig AI SDK
//
// This module provides Together AI API integration including:
// - Chat models (Llama, Mixtral, etc.)
// - Embedding models
// - Image models
// - Reranking models
// - OpenAI-compatible API format

pub const provider = @import("togetherai-provider.zig");
pub const TogetherAIProvider = provider.TogetherAIProvider;
pub const TogetherAIProviderSettings = provider.TogetherAIProviderSettings;
pub const createTogetherAI = provider.createTogetherAI;
pub const createTogetherAIWithSettings = provider.createTogetherAIWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
