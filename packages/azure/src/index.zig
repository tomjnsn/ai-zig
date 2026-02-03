// Azure OpenAI Provider for Zig AI SDK
//
// This module provides Azure OpenAI API integration including:
// - Chat completion models (GPT-4, GPT-3.5-turbo, etc.)
// - Embedding models
// - Image generation (DALL-E)
// - Speech synthesis
// - Audio transcription (Whisper)
//
// Azure OpenAI reuses OpenAI model implementations with Azure-specific
// authentication (api-key header) and URL construction.

// Provider
pub const provider = @import("azure-openai-provider.zig");
pub const AzureOpenAIProvider = provider.AzureOpenAIProvider;
pub const AzureOpenAIProviderSettings = provider.AzureOpenAIProviderSettings;
pub const createAzure = provider.createAzure;
pub const createAzureWithSettings = provider.createAzureWithSettings;

// Configuration
pub const config = @import("azure-config.zig");
pub const AzureOpenAIConfig = config.AzureOpenAIConfig;
pub const buildAzureUrl = config.buildAzureUrl;
pub const buildBaseUrlFromResourceName = config.buildBaseUrlFromResourceName;

// Re-export OpenAI types that Azure uses
pub const openai = @import("openai");

test {
    // Run all module tests
    @import("std").testing.refAllDecls(@This());
}
