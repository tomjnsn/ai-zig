const std = @import("std");
const embedding = @import("provider").embedding_model;
const shared = @import("provider").shared;

const config_mod = @import("mistral-config.zig");

/// Mistral Embedding Model
pub const MistralEmbeddingModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.MistralConfig,

    /// Maximum embeddings per call
    pub const max_embeddings_per_call: usize = 32;

    /// Supports parallel calls
    pub const supports_parallel_calls: bool = false;

    /// Create a new Mistral embedding model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.MistralConfig,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .config = config,
        };
    }

    /// Get the model ID
    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    /// Get the provider name
    pub fn getProvider(self: *const Self) []const u8 {
        return self.config.provider;
    }

    /// Get the maximum embeddings per call
    pub fn getMaxEmbeddingsPerCall(
        self: *const Self,
        callback: *const fn (?*anyopaque, ?u32) void,
        ctx: ?*anyopaque,
    ) void {
        _ = self;
        callback(ctx, @as(u32, max_embeddings_per_call));
    }

    /// Check if parallel calls are supported
    pub fn getSupportsParallelCalls(
        self: *const Self,
        callback: *const fn (?*anyopaque, bool) void,
        ctx: ?*anyopaque,
    ) void {
        _ = self;
        callback(ctx, supports_parallel_calls);
    }

    /// Generate embeddings
    pub fn doEmbed(
        self: *const Self,
        call_options: embedding.EmbeddingModelCallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, embedding.EmbeddingModelV3.EmbedResult) void,
        callback_context: ?*anyopaque,
    ) void {
        const values = call_options.values;
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Check max embeddings
        if (values.len > max_embeddings_per_call) {
            callback(callback_context, .{ .failure = error.TooManyEmbeddingValues });
            return;
        }

        // Build URL
        const url = config_mod.buildEmbeddingsUrl(
            request_allocator,
            self.config.base_url,
        ) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Build request body
        var body = std.json.ObjectMap.init(request_allocator);
        body.put("model", .{ .string = self.model_id }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        var input = std.json.Array.init(request_allocator);
        for (values) |value| {
            input.append(.{ .string = value }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }
        body.put("input", .{ .array = input }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };
        body.put("encoding_format", .{ .string = "float" }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        _ = url;

        // For now, return placeholder result
        const embeddings = result_allocator.alloc([]f32, values.len) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Mistral embeddings are 1024 dimensions
        const dimensions: usize = 1024;
        for (embeddings, 0..) |*emb, i| {
            _ = i;
            emb.* = result_allocator.alloc(f32, dimensions) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
            @memset(emb.*, 0.0);
        }

        // Convert embeddings to proper format
        var embed_list = std.ArrayList(embedding.EmbeddingModelV3Embedding).empty;
        for (embeddings) |emb| {
            embed_list.append(result_allocator, .{ .embedding = .{ .float = emb } }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        const result = embedding.EmbeddingModelV3.EmbedSuccess{
            .embeddings = embed_list.toOwnedSlice(result_allocator) catch &[_]embedding.EmbeddingModelV3Embedding{},
            .usage = null,
            .warnings = &[_]shared.SharedV3Warning{},
        };

        callback(callback_context, .{ .success = result });
    }

    /// Convert to EmbeddingModelV3 interface
    pub fn asEmbeddingModel(self: *Self) embedding.EmbeddingModelV3 {
        return embedding.asEmbeddingModel(Self, self);
    }
};

test "MistralEmbeddingModel init" {
    const allocator = std.testing.allocator;

    var model = MistralEmbeddingModel.init(
        allocator,
        "mistral-embed",
        .{ .base_url = "https://api.mistral.ai/v1" },
    );

    try std.testing.expectEqualStrings("mistral-embed", model.getModelId());
    try std.testing.expectEqual(MistralEmbeddingModel.max_embeddings_per_call, 32);
}
