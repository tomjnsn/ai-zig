// Gladia Provider for Zig AI SDK
//
// This module provides Gladia API integration including:
// - Transcription (Enhanced and Fast models)
// - Speaker diarization
// - Translation
// - Emotion recognition
// - Summarization
// - Chapterization
// - Noise reduction

pub const provider = @import("gladia-provider.zig");
pub const GladiaProvider = provider.GladiaProvider;
pub const GladiaProviderSettings = provider.GladiaProviderSettings;
pub const GladiaTranscriptionModel = provider.GladiaTranscriptionModel;
pub const TranscriptionModels = provider.TranscriptionModels;
pub const TranscriptionOptions = provider.TranscriptionOptions;
pub const createGladia = provider.createGladia;
pub const createGladiaWithSettings = provider.createGladiaWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
