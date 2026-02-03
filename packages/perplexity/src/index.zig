// Perplexity Provider for Zig AI SDK
//
// This module provides Perplexity API integration including:
// - Online chat models with web search
// - Real-time information retrieval
// - Citation support

pub const provider = @import("perplexity-provider.zig");
pub const PerplexityProvider = provider.PerplexityProvider;
pub const PerplexityProviderSettings = provider.PerplexityProviderSettings;
pub const createPerplexity = provider.createPerplexity;
pub const createPerplexityWithSettings = provider.createPerplexityWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
