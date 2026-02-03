// DeepSeek Provider for Zig AI SDK
//
// This module provides DeepSeek API integration including:
// - Chat models (deepseek-chat)
// - Reasoning models (deepseek-reasoner)
// - OpenAI-compatible API format
// - Bearer token authentication support

// Provider
pub const provider = @import("deepseek-provider.zig");
pub const DeepSeekProvider = provider.DeepSeekProvider;
pub const DeepSeekProviderSettings = provider.DeepSeekProviderSettings;
pub const createDeepSeek = provider.createDeepSeek;
pub const createDeepSeekWithSettings = provider.createDeepSeekWithSettings;

// Configuration
pub const config = @import("deepseek-config.zig");
pub const DeepSeekConfig = config.DeepSeekConfig;
pub const buildChatCompletionsUrl = config.buildChatCompletionsUrl;

// Language model
pub const chat_model = @import("deepseek-chat-language-model.zig");
pub const DeepSeekChatLanguageModel = chat_model.DeepSeekChatLanguageModel;

// Options
pub const options = @import("deepseek-options.zig");
pub const ChatModels = options.ChatModels;
pub const ThinkingConfig = options.ThinkingConfig;
pub const ThinkingType = options.ThinkingType;
pub const DeepSeekChatOptions = options.DeepSeekChatOptions;
pub const supportsReasoning = options.supportsReasoning;

// Finish reason mapping
pub const map_finish = @import("map-deepseek-finish-reason.zig");
pub const mapDeepSeekFinishReason = map_finish.mapDeepSeekFinishReason;

test {
    @import("std").testing.refAllDecls(@This());
}
