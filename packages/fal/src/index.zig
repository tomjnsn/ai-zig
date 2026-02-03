// Fal AI Provider for Zig AI SDK
//
// This module provides Fal AI API integration including:
// - Image generation models (FLUX, Stable Diffusion, etc.)
// - Speech generation models
// - Transcription models (Whisper)

pub const provider = @import("fal-provider.zig");
pub const FalProvider = provider.FalProvider;
pub const FalProviderSettings = provider.FalProviderSettings;
pub const FalImageModel = provider.FalImageModel;
pub const FalSpeechModel = provider.FalSpeechModel;
pub const FalTranscriptionModel = provider.FalTranscriptionModel;
pub const createFal = provider.createFal;
pub const createFalWithSettings = provider.createFalWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
