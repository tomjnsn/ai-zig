// AssemblyAI Provider for Zig AI SDK
//
// This module provides AssemblyAI API integration including:
// - Transcription (speech-to-text with best/nano models)
// - Speaker diarization
// - Sentiment analysis
// - Entity detection
// - Content safety
// - Auto-chapters
// - LeMUR language model for audio understanding

pub const provider = @import("assemblyai-provider.zig");
pub const AssemblyAIProvider = provider.AssemblyAIProvider;
pub const AssemblyAIProviderSettings = provider.AssemblyAIProviderSettings;
pub const AssemblyAITranscriptionModel = provider.AssemblyAITranscriptionModel;
pub const AssemblyAILanguageModel = provider.AssemblyAILanguageModel;
pub const TranscriptionModels = provider.TranscriptionModels;
pub const TranscriptionOptions = provider.TranscriptionOptions;
pub const createAssemblyAI = provider.createAssemblyAI;
pub const createAssemblyAIWithSettings = provider.createAssemblyAIWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
