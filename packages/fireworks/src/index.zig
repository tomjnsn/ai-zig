// Fireworks AI Provider for Zig AI SDK
//
// This module provides Fireworks AI API integration including:
// - Chat models
// - Embedding models
// - Image models
// - OpenAI-compatible API format

pub const provider = @import("fireworks-provider.zig");
pub const FireworksProvider = provider.FireworksProvider;
pub const FireworksProviderSettings = provider.FireworksProviderSettings;
pub const createFireworks = provider.createFireworks;
pub const createFireworksWithSettings = provider.createFireworksWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
