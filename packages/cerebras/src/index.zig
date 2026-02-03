// Cerebras Provider for Zig AI SDK
//
// This module provides Cerebras API integration including:
// - Ultra-fast inference for Llama models
// - OpenAI-compatible API format

pub const provider = @import("cerebras-provider.zig");
pub const CerebrasProvider = provider.CerebrasProvider;
pub const CerebrasProviderSettings = provider.CerebrasProviderSettings;
pub const createCerebras = provider.createCerebras;
pub const createCerebrasWithSettings = provider.createCerebrasWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
