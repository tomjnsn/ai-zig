// Rev AI Provider for Zig AI SDK
//
// This module provides Rev AI API integration including:
// - Transcription (Machine and Human models)
// - Speaker diarization
// - Custom vocabularies
// - Emotion detection
// - Summarization
// - Translation

pub const provider = @import("revai-provider.zig");
pub const RevAIProvider = provider.RevAIProvider;
pub const RevAIProviderSettings = provider.RevAIProviderSettings;
pub const RevAITranscriptionModel = provider.RevAITranscriptionModel;
pub const TranscriptionModels = provider.TranscriptionModels;
pub const TranscriptionOptions = provider.TranscriptionOptions;
pub const CustomVocabulary = provider.CustomVocabulary;
pub const SummarizationConfig = provider.SummarizationConfig;
pub const TranslationConfig = provider.TranslationConfig;
pub const createRevAI = provider.createRevAI;
pub const createRevAIWithSettings = provider.createRevAIWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
