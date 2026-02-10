const std = @import("std");
const provider_types = @import("provider");

const EmbeddingModelV3 = provider_types.EmbeddingModelV3;

/// Token usage for embedding operations
pub const EmbeddingUsage = struct {
    tokens: ?u64 = null,
};

/// Single embedding result
pub const Embedding = struct {
    /// The embedding vector
    values: []const f64,

    /// Index in the input array (for embed_many)
    index: ?usize = null,
};

/// Response metadata for embedding
pub const EmbeddingResponseMetadata = struct {
    id: ?[]const u8 = null,
    model_id: []const u8,
    timestamp: ?i64 = null,
    headers: ?std.StringHashMap([]const u8) = null,
};

/// Result of embed (single value)
pub const EmbedResult = struct {
    /// The generated embedding
    embedding: Embedding,

    /// Token usage
    usage: EmbeddingUsage,

    /// Response metadata
    response: EmbeddingResponseMetadata,

    /// Warnings from the model
    warnings: ?[]const []const u8 = null,

    /// Get the embedding vector
    pub fn getEmbedding(self: *const EmbedResult) []const f64 {
        return self.embedding.values;
    }

    /// Get the dimensionality of the embedding
    pub fn dimension(self: *const EmbedResult) usize {
        return self.embedding.values.len;
    }

    pub fn deinit(self: *EmbedResult, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Arena allocator handles cleanup
    }
};

/// Result of embedMany (multiple values)
pub const EmbedManyResult = struct {
    /// The generated embeddings
    embeddings: []const Embedding,

    /// Token usage
    usage: EmbeddingUsage,

    /// Response metadata
    response: EmbeddingResponseMetadata,

    /// Warnings from the model
    warnings: ?[]const []const u8 = null,

    pub fn deinit(self: *EmbedManyResult, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Arena allocator handles cleanup
    }
};

/// Options for embed
pub const EmbedOptions = struct {
    /// The embedding model to use
    model: *EmbeddingModelV3,

    /// The value to embed
    value: []const u8,

    /// Maximum retries on failure
    max_retries: u32 = 2,

    /// Additional headers
    headers: ?std.StringHashMap([]const u8) = null,

    /// Request context for timeout/cancellation
    request_context: ?*const @import("../context.zig").RequestContext = null,

    /// Retry policy for automatic retries
    retry_policy: ?@import("../retry.zig").RetryPolicy = null,
};

/// Options for embedMany
pub const EmbedManyOptions = struct {
    /// The embedding model to use
    model: *EmbeddingModelV3,

    /// The values to embed
    values: []const []const u8,

    /// Maximum retries on failure
    max_retries: u32 = 2,

    /// Additional headers
    headers: ?std.StringHashMap([]const u8) = null,

    /// Request context for timeout/cancellation
    request_context: ?*const @import("../context.zig").RequestContext = null,

    /// Retry policy for automatic retries
    retry_policy: ?@import("../retry.zig").RetryPolicy = null,
};

/// Error types for embedding
pub const EmbedError = error{
    ModelError,
    NetworkError,
    InvalidInput,
    TooManyValues,
    Cancelled,
    OutOfMemory,
};

/// Generate an embedding for a single value
pub fn embed(
    allocator: std.mem.Allocator,
    options: EmbedOptions,
) EmbedError!EmbedResult {
    // Check request context for cancellation/timeout
    if (options.request_context) |ctx| {
        if (ctx.isDone()) return EmbedError.Cancelled;
    }

    // Validate input
    if (options.value.len == 0) {
        return EmbedError.InvalidInput;
    }

    // Call model.doEmbed with a single-value slice
    const values = [_][]const u8{options.value};
    const call_options = provider_types.EmbeddingModelCallOptions{
        .values = &values,
    };

    const CallbackCtx = struct {
        result: ?EmbeddingModelV3.EmbedResult = null,
    };
    var cb_ctx = CallbackCtx{};
    const ctx_ptr: *anyopaque = @ptrCast(&cb_ctx);

    options.model.doEmbed(
        call_options,
        allocator,
        struct {
            fn onResult(ptr: ?*anyopaque, result: EmbeddingModelV3.EmbedResult) void {
                const ctx: *CallbackCtx = @ptrCast(@alignCast(ptr.?));
                ctx.result = result;
            }
        }.onResult,
        ctx_ptr,
    );

    const embed_success = switch (cb_ctx.result orelse return EmbedError.ModelError) {
        .success => |s| s,
        .failure => return EmbedError.ModelError,
    };

    // Convert f32 embeddings to f64
    if (embed_success.embeddings.len == 0) {
        return EmbedError.ModelError;
    }

    const f32_values = embed_success.embeddings[0];
    const f64_values = try allocator.alloc(f64, f32_values.len);
    for (f32_values, 0..) |v, i| {
        f64_values[i] = @as(f64, @floatCast(v));
    }

    return EmbedResult{
        .embedding = .{
            .values = f64_values,
        },
        .usage = .{
            .tokens = if (embed_success.usage) |u| u.tokens else null,
        },
        .response = .{
            .model_id = options.model.getModelId(),
        },
        .warnings = null,
    };
}

/// Generate embeddings for multiple values
pub fn embedMany(
    allocator: std.mem.Allocator,
    options: EmbedManyOptions,
) EmbedError!EmbedManyResult {
    // Check request context for cancellation/timeout
    if (options.request_context) |ctx| {
        if (ctx.isDone()) return EmbedError.Cancelled;
    }

    // Validate input
    if (options.values.len == 0) {
        return EmbedError.InvalidInput;
    }

    // Query max embeddings per call
    const MaxCtx = struct { max: ?u32 = null };
    var max_ctx = MaxCtx{};
    options.model.getMaxEmbeddingsPerCall(
        struct {
            fn cb(ptr: ?*anyopaque, val: ?u32) void {
                const ctx: *MaxCtx = @ptrCast(@alignCast(ptr.?));
                ctx.max = val;
            }
        }.cb,
        @ptrCast(&max_ctx),
    );
    const max_per_call: usize = if (max_ctx.max) |m| @as(usize, m) else options.values.len;

    // Process in batches
    var all_embeddings = std.array_list.Managed(Embedding).init(allocator);
    var total_tokens: u64 = 0;

    var offset: usize = 0;
    while (offset < options.values.len) {
        const end = @min(offset + max_per_call, options.values.len);
        const batch = options.values[offset..end];

        const call_options = provider_types.EmbeddingModelCallOptions{
            .values = batch,
        };

        const CallbackCtx = struct { result: ?EmbeddingModelV3.EmbedResult = null };
        var cb_ctx = CallbackCtx{};
        const ctx_ptr: *anyopaque = @ptrCast(&cb_ctx);

        options.model.doEmbed(
            call_options,
            allocator,
            struct {
                fn onResult(ptr: ?*anyopaque, result: EmbeddingModelV3.EmbedResult) void {
                    const ctx: *CallbackCtx = @ptrCast(@alignCast(ptr.?));
                    ctx.result = result;
                }
            }.onResult,
            ctx_ptr,
        );

        const embed_success = switch (cb_ctx.result orelse return EmbedError.ModelError) {
            .success => |s| s,
            .failure => return EmbedError.ModelError,
        };

        // Convert f32 embeddings to f64 and add to results
        for (embed_success.embeddings) |f32_values| {
            const f64_values = allocator.alloc(f64, f32_values.len) catch return EmbedError.OutOfMemory;
            for (f32_values, 0..) |v, i| {
                f64_values[i] = @as(f64, @floatCast(v));
            }
            // Free the provider-allocated f32 values
            allocator.free(f32_values);
            all_embeddings.append(.{
                .values = f64_values,
                .index = all_embeddings.items.len,
            }) catch return EmbedError.OutOfMemory;
        }
        // Free the provider-allocated embeddings slice
        allocator.free(embed_success.embeddings);

        if (embed_success.usage) |u| {
            total_tokens += u.tokens;
        }

        offset = end;
    }

    return EmbedManyResult{
        .embeddings = all_embeddings.toOwnedSlice() catch return EmbedError.OutOfMemory,
        .usage = .{
            .tokens = if (total_tokens > 0) total_tokens else null,
        },
        .response = .{
            .model_id = options.model.getModelId(),
        },
        .warnings = null,
    };
}

/// Calculate cosine similarity between two embeddings
pub fn cosineSimilarity(a: []const f64, b: []const f64) f64 {
    if (a.len != b.len or a.len == 0) {
        return 0;
    }

    var dot_product: f64 = 0;
    var norm_a: f64 = 0;
    var norm_b: f64 = 0;

    for (a, b) |ai, bi| {
        dot_product += ai * bi;
        norm_a += ai * ai;
        norm_b += bi * bi;
    }

    const denominator = @sqrt(norm_a) * @sqrt(norm_b);
    if (denominator == 0) {
        return 0;
    }

    return dot_product / denominator;
}

/// Calculate Euclidean distance between two embeddings
pub fn euclideanDistance(a: []const f64, b: []const f64) f64 {
    if (a.len != b.len) {
        return std.math.inf(f64);
    }

    var sum: f64 = 0;
    for (a, b) |ai, bi| {
        const diff = ai - bi;
        sum += diff * diff;
    }

    return @sqrt(sum);
}

/// Calculate dot product between two embeddings
pub fn dotProduct(a: []const f64, b: []const f64) f64 {
    if (a.len != b.len) {
        return 0;
    }

    var sum: f64 = 0;
    for (a, b) |ai, bi| {
        sum += ai * bi;
    }

    return sum;
}

test "EmbedOptions default values" {
    const model: EmbeddingModelV3 = undefined;
    const options = EmbedOptions{
        .model = @constCast(&model),
        .value = "Hello",
    };
    try std.testing.expect(options.max_retries == 2);
}

test "cosineSimilarity identical vectors" {
    const a = [_]f64{ 1.0, 0.0, 0.0 };
    const b = [_]f64{ 1.0, 0.0, 0.0 };
    const similarity = cosineSimilarity(&a, &b);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), similarity, 0.0001);
}

test "cosineSimilarity orthogonal vectors" {
    const a = [_]f64{ 1.0, 0.0, 0.0 };
    const b = [_]f64{ 0.0, 1.0, 0.0 };
    const similarity = cosineSimilarity(&a, &b);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), similarity, 0.0001);
}

test "euclideanDistance same point" {
    const a = [_]f64{ 1.0, 2.0, 3.0 };
    const b = [_]f64{ 1.0, 2.0, 3.0 };
    const distance = euclideanDistance(&a, &b);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), distance, 0.0001);
}

test "euclideanDistance unit distance" {
    const a = [_]f64{ 0.0, 0.0 };
    const b = [_]f64{ 1.0, 0.0 };
    const distance = euclideanDistance(&a, &b);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), distance, 0.0001);
}

test "dotProduct simple" {
    const a = [_]f64{ 1.0, 2.0, 3.0 };
    const b = [_]f64{ 4.0, 5.0, 6.0 };
    const product = dotProduct(&a, &b);
    // 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
    try std.testing.expectApproxEqAbs(@as(f64, 32.0), product, 0.0001);
}

test "embed returns embeddings from mock provider" {
    const MockEmbeddingModel = struct {
        const Self = @This();

        const mock_values = [_]f32{ 0.1, 0.2, 0.3 };
        const mock_embeddings = [_]provider_types.EmbeddingModelV3Embedding{
            &mock_values,
        };

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-embedding";
        }

        pub fn getMaxEmbeddingsPerCall(
            _: *const Self,
            callback: *const fn (?*anyopaque, ?u32) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, 100);
        }

        pub fn getSupportsParallelCalls(
            _: *const Self,
            callback: *const fn (?*anyopaque, bool) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, true);
        }

        pub fn doEmbed(
            _: *const Self,
            _: provider_types.EmbeddingModelCallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, EmbeddingModelV3.EmbedResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .success = .{
                .embeddings = &mock_embeddings,
                .usage = .{ .tokens = 5 },
            } });
        }
    };

    var mock = MockEmbeddingModel{};
    var model = provider_types.asEmbeddingModel(MockEmbeddingModel, &mock);

    const result = try embed(std.testing.allocator, .{
        .model = &model,
        .value = "test input",
    });
    defer std.testing.allocator.free(result.embedding.values);

    // Should have 3 embedding values
    try std.testing.expectEqual(@as(usize, 3), result.embedding.values.len);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), result.embedding.values[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), result.embedding.values[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3), result.embedding.values[2], 0.001);

    // Should have usage info
    try std.testing.expectEqual(@as(?u64, 5), result.usage.tokens);

    // Should have model ID from provider
    try std.testing.expectEqualStrings("mock-embedding", result.response.model_id);
}

test "embedMany batches requests per provider limits" {
    const MockBatchEmbeddingModel = struct {
        const Self = @This();

        call_count: u32 = 0,

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-batch";
        }

        pub fn getMaxEmbeddingsPerCall(
            _: *const Self,
            callback: *const fn (?*anyopaque, ?u32) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, 2); // Max 2 per call to force batching with 3 values
        }

        pub fn getSupportsParallelCalls(
            _: *const Self,
            callback: *const fn (?*anyopaque, bool) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, false);
        }

        pub fn doEmbed(
            self: *Self,
            options: provider_types.EmbeddingModelCallOptions,
            alloc: std.mem.Allocator,
            callback: *const fn (?*anyopaque, EmbeddingModelV3.EmbedResult) void,
            ctx: ?*anyopaque,
        ) void {
            self.call_count += 1;

            // Return one embedding per input value
            const embeddings = alloc.alloc(provider_types.EmbeddingModelV3Embedding, options.values.len) catch {
                callback(ctx, .{ .failure = error.OutOfMemory });
                return;
            };
            for (0..options.values.len) |i| {
                const vals = alloc.alloc(f32, 3) catch {
                    callback(ctx, .{ .failure = error.OutOfMemory });
                    return;
                };
                // Each embedding: [call_count * 0.1, call_count * 0.2, call_count * 0.3] offset by index
                const base: f32 = @floatFromInt(self.call_count);
                const idx: f32 = @floatFromInt(i);
                vals[0] = base * 0.1 + idx * 0.01;
                vals[1] = base * 0.2 + idx * 0.01;
                vals[2] = base * 0.3 + idx * 0.01;
                embeddings[i] = vals;
            }

            callback(ctx, .{ .success = .{
                .embeddings = embeddings,
                .usage = .{ .tokens = @as(u64, options.values.len) * 3 },
            } });
        }
    };

    var mock = MockBatchEmbeddingModel{};
    var model = provider_types.asEmbeddingModel(MockBatchEmbeddingModel, &mock);

    const values = [_][]const u8{ "hello", "world", "test" };
    const result = try embedMany(std.testing.allocator, .{
        .model = &model,
        .values = &values,
    });
    // Free all allocated embedding values
    defer {
        for (result.embeddings) |emb| {
            std.testing.allocator.free(emb.values);
        }
        std.testing.allocator.free(result.embeddings);
    }

    // Should have 3 embeddings (currently returns empty - this test should FAIL)
    try std.testing.expectEqual(@as(usize, 3), result.embeddings.len);

    // With max 2 per call and 3 values, should require 2 calls
    try std.testing.expectEqual(@as(u32, 2), mock.call_count);

    // Should have model ID from provider
    try std.testing.expectEqualStrings("mock-batch", result.response.model_id);
}

test "embed returns error on empty value" {
    const MockEmbed = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-embed";
        }

        pub fn getMaxEmbeddingsPerCall(
            _: *const Self,
            callback: *const fn (?*anyopaque, ?u32) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, 100);
        }

        pub fn getSupportsParallelCalls(
            _: *const Self,
            callback: *const fn (?*anyopaque, bool) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, true);
        }

        pub fn doEmbed(
            _: *const Self,
            _: provider_types.EmbeddingModelCallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, provider_types.EmbeddingModelV3.EmbedResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.ModelError });
        }
    };

    var mock = MockEmbed{};
    var model = provider_types.asEmbeddingModel(MockEmbed, &mock);

    // Empty value should return InvalidInput
    const result = embed(std.testing.allocator, .{
        .model = &model,
        .value = "",
    });

    try std.testing.expectError(EmbedError.InvalidInput, result);
}

test "embed returns error on model failure" {
    const MockFailEmbed = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-fail";
        }

        pub fn getMaxEmbeddingsPerCall(
            _: *const Self,
            callback: *const fn (?*anyopaque, ?u32) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, 100);
        }

        pub fn getSupportsParallelCalls(
            _: *const Self,
            callback: *const fn (?*anyopaque, bool) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, true);
        }

        pub fn doEmbed(
            _: *const Self,
            _: provider_types.EmbeddingModelCallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, provider_types.EmbeddingModelV3.EmbedResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.ModelError });
        }
    };

    var mock = MockFailEmbed{};
    var model = provider_types.asEmbeddingModel(MockFailEmbed, &mock);

    const result = embed(std.testing.allocator, .{
        .model = &model,
        .value = "test input",
    });

    try std.testing.expectError(EmbedError.ModelError, result);
}

test "embed sequential requests don't leak memory" {
    const MockStressEmbed = struct {
        const Self = @This();

        const mock_embedding = [_]f32{ 0.1, 0.2, 0.3, 0.4 };

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-stress-embed";
        }

        pub fn getMaxEmbeddingsPerCall(
            _: *const Self,
            callback: *const fn (?*anyopaque, ?u32) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, 100);
        }

        pub fn getSupportsParallelCalls(
            _: *const Self,
            callback: *const fn (?*anyopaque, bool) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, true);
        }

        pub fn doEmbed(
            _: *const Self,
            _: provider_types.EmbeddingModelCallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, provider_types.EmbeddingModelV3.EmbedResult) void,
            ctx: ?*anyopaque,
        ) void {
            const embeddings = [_][]const f32{&mock_embedding};
            callback(ctx, .{ .success = .{
                .embeddings = &embeddings,
                .usage = .{ .tokens = 5 },
            } });
        }
    };

    var mock = MockStressEmbed{};
    var model = provider_types.asEmbeddingModel(MockStressEmbed, &mock);

    // Run 50 sequential embed calls - testing allocator detects leaks
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        const result = try embed(std.testing.allocator, .{
            .model = &model,
            .value = "test embedding text",
        });
        defer std.testing.allocator.free(result.embedding.values);
        try std.testing.expectEqual(@as(usize, 4), result.embedding.values.len);
    }
}

test "embedMany large batch with batching doesn't leak memory" {
    const MockLargeBatchEmbed = struct {
        const Self = @This();
        call_count: u32 = 0,

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-large-batch";
        }

        pub fn getMaxEmbeddingsPerCall(
            _: *const Self,
            callback: *const fn (?*anyopaque, ?u32) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, 10); // Max 10 per call
        }

        pub fn getSupportsParallelCalls(
            _: *const Self,
            callback: *const fn (?*anyopaque, bool) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, false);
        }

        pub fn doEmbed(
            self: *Self,
            options: provider_types.EmbeddingModelCallOptions,
            alloc: std.mem.Allocator,
            callback: *const fn (?*anyopaque, EmbeddingModelV3.EmbedResult) void,
            ctx: ?*anyopaque,
        ) void {
            self.call_count += 1;
            const embeddings = alloc.alloc(provider_types.EmbeddingModelV3Embedding, options.values.len) catch {
                callback(ctx, .{ .failure = error.OutOfMemory });
                return;
            };
            for (0..options.values.len) |i| {
                const vals = alloc.alloc(f32, 3) catch {
                    callback(ctx, .{ .failure = error.OutOfMemory });
                    return;
                };
                vals[0] = 0.1;
                vals[1] = 0.2;
                vals[2] = 0.3;
                embeddings[i] = vals;
            }
            callback(ctx, .{ .success = .{
                .embeddings = embeddings,
                .usage = .{ .tokens = @as(u64, options.values.len) * 3 },
            } });
        }
    };

    var mock = MockLargeBatchEmbed{};
    var model = provider_types.asEmbeddingModel(MockLargeBatchEmbed, &mock);

    // 50 texts with max 10 per call = 5 batches
    var texts: [50][]const u8 = undefined;
    for (&texts, 0..) |*t, i| {
        _ = i;
        t.* = "embedding text";
    }

    const result = try embedMany(std.testing.allocator, .{
        .model = &model,
        .values = &texts,
    });
    defer {
        for (result.embeddings) |emb| {
            std.testing.allocator.free(emb.values);
        }
        std.testing.allocator.free(result.embeddings);
    }

    // Should have 50 embeddings
    try std.testing.expectEqual(@as(usize, 50), result.embeddings.len);

    // Should have required 5 batches (50 / 10)
    try std.testing.expectEqual(@as(u32, 5), mock.call_count);

    // Each embedding should have 3 values
    for (result.embeddings) |emb| {
        try std.testing.expectEqual(@as(usize, 3), emb.values.len);
    }
}
