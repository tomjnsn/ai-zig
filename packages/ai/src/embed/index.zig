// Embed Module for Zig AI SDK
//
// This module provides embedding generation capabilities:
// - embed: Generate embedding for a single value
// - embedMany: Generate embeddings for multiple values
// - Similarity functions: cosine, euclidean, dot product

pub const embed_mod = @import("embed.zig");

// Re-export types
pub const embed = embed_mod.embed;
pub const embedMany = embed_mod.embedMany;
pub const EmbedResult = embed_mod.EmbedResult;
pub const EmbedManyResult = embed_mod.EmbedManyResult;
pub const EmbedOptions = embed_mod.EmbedOptions;
pub const EmbedManyOptions = embed_mod.EmbedManyOptions;
pub const EmbedError = embed_mod.EmbedError;
pub const Embedding = embed_mod.Embedding;
pub const EmbeddingUsage = embed_mod.EmbeddingUsage;
pub const EmbeddingResponseMetadata = embed_mod.EmbeddingResponseMetadata;

// Builder
pub const builder_mod = @import("builder.zig");
pub const EmbedBuilder = builder_mod.EmbedBuilder;

// Re-export similarity functions
pub const cosineSimilarity = embed_mod.cosineSimilarity;
pub const euclideanDistance = embed_mod.euclideanDistance;
pub const dotProduct = embed_mod.dotProduct;

test {
    @import("std").testing.refAllDecls(@This());
}
