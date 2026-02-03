// Hume AI Provider for Zig AI SDK
//
// This module provides Hume AI API integration including:
// - Empathic Voice Interface (speech synthesis with emotion)
// - Expression analysis

pub const provider = @import("hume-provider.zig");
pub const HumeProvider = provider.HumeProvider;
pub const HumeProviderSettings = provider.HumeProviderSettings;
pub const HumeSpeechModel = provider.HumeSpeechModel;
pub const HumeExpressionModel = provider.HumeExpressionModel;
pub const SpeechOptions = provider.SpeechOptions;
pub const Prosody = provider.Prosody;
pub const createHume = provider.createHume;
pub const createHumeWithSettings = provider.createHumeWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
