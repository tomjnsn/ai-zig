const std = @import("std");

pub const provider_v3 = @import("provider-v3.zig");
pub const ProviderV3 = provider_v3.ProviderV3;
pub const implementProvider = provider_v3.implementProvider;
pub const asProvider = provider_v3.asProvider;

// Re-export result types from ProviderV3
pub const LanguageModelResult = ProviderV3.LanguageModelResult;
pub const EmbeddingModelResult = ProviderV3.EmbeddingModelResult;
pub const ImageModelResult = ProviderV3.ImageModelResult;
pub const TranscriptionModelResult = ProviderV3.TranscriptionModelResult;
pub const SpeechModelResult = ProviderV3.SpeechModelResult;

test {
    std.testing.refAllDecls(@This());
}
