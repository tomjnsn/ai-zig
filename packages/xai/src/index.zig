// xAI Provider for Zig AI SDK
//
// This module provides xAI (Grok) API integration including:
// - Chat models (grok-2, grok-2-mini, etc.)
// - Image models
// - Responses API for agentic tool calling
// - OpenAI-compatible API format

pub const provider = @import("xai-provider.zig");
pub const XaiProvider = provider.XaiProvider;
pub const XaiProviderSettings = provider.XaiProviderSettings;
pub const createXai = provider.createXai;
pub const createXaiWithSettings = provider.createXaiWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
