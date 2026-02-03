// ElevenLabs Provider for Zig AI SDK
//
// This module provides ElevenLabs API integration including:
// - Speech synthesis (text-to-speech)
// - Voice cloning
// - Transcription (Scribe)

pub const provider = @import("elevenlabs-provider.zig");
pub const ElevenLabsProvider = provider.ElevenLabsProvider;
pub const ElevenLabsProviderSettings = provider.ElevenLabsProviderSettings;
pub const ElevenLabsSpeechModel = provider.ElevenLabsSpeechModel;
pub const ElevenLabsTranscriptionModel = provider.ElevenLabsTranscriptionModel;
pub const createElevenLabs = provider.createElevenLabs;
pub const createElevenLabsWithSettings = provider.createElevenLabsWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
