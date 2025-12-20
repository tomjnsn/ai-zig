// Embeddings Example
//
// This example demonstrates how to generate text embeddings and
// use similarity functions for semantic search and comparison.

const std = @import("std");
const ai = @import("ai");
const openai = @import("openai");

/// Sample documents for semantic search
const documents = [_][]const u8{
    "The quick brown fox jumps over the lazy dog.",
    "A fast auburn fox leaps across a sleepy canine.",
    "Python is a popular programming language for data science.",
    "Zig is a systems programming language focused on performance.",
    "The weather today is sunny with clear skies.",
    "Machine learning models require large datasets for training.",
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Embeddings Example\n", .{});
    std.debug.print("==================\n\n", .{});

    // Example 1: Similarity functions with pre-computed vectors
    std.debug.print("1. Similarity Functions\n", .{});
    std.debug.print("------------------------\n", .{});

    // Example vectors (normalized for cosine similarity)
    const vec_a = [_]f64{ 0.6, 0.8, 0.0 };
    const vec_b = [_]f64{ 0.8, 0.6, 0.0 };
    const vec_c = [_]f64{ 0.0, 0.0, 1.0 };

    std.debug.print("Vector A: [{d:.2}, {d:.2}, {d:.2}]\n", .{ vec_a[0], vec_a[1], vec_a[2] });
    std.debug.print("Vector B: [{d:.2}, {d:.2}, {d:.2}]\n", .{ vec_b[0], vec_b[1], vec_b[2] });
    std.debug.print("Vector C: [{d:.2}, {d:.2}, {d:.2}]\n", .{ vec_c[0], vec_c[1], vec_c[2] });
    std.debug.print("\n", .{});

    // Cosine similarity (higher = more similar, range: -1 to 1)
    const cos_ab = ai.cosineSimilarity(&vec_a, &vec_b);
    const cos_ac = ai.cosineSimilarity(&vec_a, &vec_c);
    const cos_bc = ai.cosineSimilarity(&vec_b, &vec_c);

    std.debug.print("Cosine Similarity (higher = more similar):\n", .{});
    std.debug.print("  A-B: {d:.4} (very similar)\n", .{cos_ab});
    std.debug.print("  A-C: {d:.4} (orthogonal/unrelated)\n", .{cos_ac});
    std.debug.print("  B-C: {d:.4} (orthogonal/unrelated)\n", .{cos_bc});
    std.debug.print("\n", .{});

    // Euclidean distance (lower = more similar)
    const dist_ab = ai.euclideanDistance(&vec_a, &vec_b);
    const dist_ac = ai.euclideanDistance(&vec_a, &vec_c);
    const dist_bc = ai.euclideanDistance(&vec_b, &vec_c);

    std.debug.print("Euclidean Distance (lower = more similar):\n", .{});
    std.debug.print("  A-B: {d:.4}\n", .{dist_ab});
    std.debug.print("  A-C: {d:.4}\n", .{dist_ac});
    std.debug.print("  B-C: {d:.4}\n", .{dist_bc});
    std.debug.print("\n", .{});

    // Dot product
    const dot_ab = ai.dotProduct(&vec_a, &vec_b);
    const dot_ac = ai.dotProduct(&vec_a, &vec_c);
    const dot_bc = ai.dotProduct(&vec_b, &vec_c);

    std.debug.print("Dot Product:\n", .{});
    std.debug.print("  A-B: {d:.4}\n", .{dot_ab});
    std.debug.print("  A-C: {d:.4}\n", .{dot_ac});
    std.debug.print("  B-C: {d:.4}\n", .{dot_bc});
    std.debug.print("\n", .{});

    // Example 2: Semantic search simulation
    std.debug.print("2. Semantic Search (Simulated)\n", .{});
    std.debug.print("-------------------------------\n", .{});

    std.debug.print("Documents:\n", .{});
    for (documents, 0..) |doc, i| {
        std.debug.print("  {d}. \"{s}\"\n", .{ i + 1, doc });
    }
    std.debug.print("\n", .{});

    // In a real application, you would:
    // 1. Generate embeddings for all documents
    // 2. Generate embedding for the query
    // 3. Compare using cosine similarity
    // 4. Return the most similar documents

    std.debug.print("Query: \"What programming language is good for systems?\"\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("To perform semantic search:\n", .{});
    std.debug.print("  1. Generate embeddings for all documents using embedMany()\n", .{});
    std.debug.print("  2. Generate embedding for the query using embed()\n", .{});
    std.debug.print("  3. Calculate cosine similarity between query and each document\n", .{});
    std.debug.print("  4. Return documents sorted by similarity\n", .{});
    std.debug.print("\n", .{});

    // Example 3: Provider setup for embeddings
    std.debug.print("3. Embedding Provider Setup\n", .{});
    std.debug.print("----------------------------\n", .{});

    var provider = openai.createOpenAI(allocator);
    defer provider.deinit();

    std.debug.print("Provider: {s}\n", .{provider.getProvider()});
    std.debug.print("Available embedding models:\n", .{});
    std.debug.print("  - text-embedding-3-small (1536 dimensions, fast)\n", .{});
    std.debug.print("  - text-embedding-3-large (3072 dimensions, more accurate)\n", .{});
    std.debug.print("  - text-embedding-ada-002 (1536 dimensions, legacy)\n", .{});
    std.debug.print("\n", .{});

    // Example embedding call (requires API key)
    // var embed_model = provider.embeddingModel("text-embedding-3-small");
    // const result = try ai.embed(allocator, .{
    //     .model = &embed_model,
    //     .value = "Hello, world!",
    // });
    // std.debug.print("Embedding dimensions: {d}\n", .{result.embedding.values.len});

    // Example 4: Use cases for embeddings
    std.debug.print("4. Common Use Cases\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("  - Semantic search: Find documents by meaning, not just keywords\n", .{});
    std.debug.print("  - Clustering: Group similar texts together\n", .{});
    std.debug.print("  - Recommendation: Find similar items\n", .{});
    std.debug.print("  - Anomaly detection: Find outliers in text data\n", .{});
    std.debug.print("  - RAG: Retrieval-Augmented Generation for LLMs\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example complete!\n", .{});
}
