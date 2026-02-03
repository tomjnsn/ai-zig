// Replicate Provider for Zig AI SDK
//
// This module provides Replicate API integration including:
// - Image generation models (Stable Diffusion, FLUX, etc.)
// - Model versioning support
// - Prediction polling

pub const provider = @import("replicate-provider.zig");
pub const ReplicateProvider = provider.ReplicateProvider;
pub const ReplicateProviderSettings = provider.ReplicateProviderSettings;
pub const ReplicateImageModel = provider.ReplicateImageModel;
pub const createReplicate = provider.createReplicate;
pub const createReplicateWithSettings = provider.createReplicateWithSettings;

test {
    @import("std").testing.refAllDecls(@This());
}
