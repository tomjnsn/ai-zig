// DeepInfra Provider for Zig AI SDK
//
// This module provides DeepInfra API integration including:
// - Chat models (Llama, Mixtral, etc.)
// - Embedding models
// - OpenAI-compatible API format

pub const provider = @import("deepinfra-provider.zig");
pub const DeepInfraProvider = provider.DeepInfraProvider;
pub const DeepInfraProviderSettings = provider.DeepInfraProviderSettings;
pub const createDeepInfra = provider.createDeepInfra;
pub const createDeepInfraWithSettings = provider.createDeepInfraWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
