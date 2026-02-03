// LMNT Provider for Zig AI SDK
//
// This module provides LMNT API integration including:
// - Speech synthesis (text-to-speech with Aurora/Blizzard voices)

pub const provider = @import("lmnt-provider.zig");
pub const LmntProvider = provider.LmntProvider;
pub const LmntProviderSettings = provider.LmntProviderSettings;
pub const LmntSpeechModel = provider.LmntSpeechModel;
pub const SpeechModels = provider.SpeechModels;
pub const SpeechOptions = provider.SpeechOptions;
pub const createLmnt = provider.createLmnt;
pub const createLmntWithSettings = provider.createLmntWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
