// Deepgram Provider for Zig AI SDK
//
// This module provides Deepgram API integration including:
// - Transcription (Nova-2, Enhanced, Base, Whisper models)
// - Speech synthesis (Aura TTS voices)
// - Speaker diarization
// - Smart formatting
// - Entity/topic detection
// - Sentiment analysis

pub const provider = @import("deepgram-provider.zig");
pub const DeepgramProvider = provider.DeepgramProvider;
pub const DeepgramProviderSettings = provider.DeepgramProviderSettings;
pub const DeepgramTranscriptionModel = provider.DeepgramTranscriptionModel;
pub const DeepgramSpeechModel = provider.DeepgramSpeechModel;
pub const TranscriptionModels = provider.TranscriptionModels;
pub const SpeechModels = provider.SpeechModels;
pub const TranscriptionOptions = provider.TranscriptionOptions;
pub const SpeechOptions = provider.SpeechOptions;
pub const createDeepgram = provider.createDeepgram;
pub const createDeepgramWithSettings = provider.createDeepgramWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
