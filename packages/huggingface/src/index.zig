// HuggingFace Provider for Zig AI SDK
//
// This module provides HuggingFace Inference API integration including:
// - Text generation models
// - Inference Endpoints support

pub const provider = @import("huggingface-provider.zig");
pub const HuggingFaceProvider = provider.HuggingFaceProvider;
pub const HuggingFaceProviderSettings = provider.HuggingFaceProviderSettings;
pub const createHuggingFace = provider.createHuggingFace;
pub const createHuggingFaceWithSettings = provider.createHuggingFaceWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
