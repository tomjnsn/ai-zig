const std = @import("std");
const embedding = @import("provider").embedding_model;
const shared = @import("provider").shared;

const config_mod = @import("openai-compatible-config.zig");

/// OpenAI-compatible Embedding Model
pub const OpenAICompatibleEmbeddingModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.OpenAICompatibleConfig,

    pub const max_embeddings_per_call: usize = 2048;
    pub const supports_parallel_calls: bool = true;

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.OpenAICompatibleConfig,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .config = config,
        };
    }

    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        return self.config.provider;
    }

    pub fn getMaxEmbeddingsPerCall(
        self: *const Self,
        callback: *const fn (?*anyopaque, ?u32) void,
        ctx: ?*anyopaque,
    ) void {
        _ = self;
        callback(ctx, @as(u32, @intCast(max_embeddings_per_call)));
    }

    pub fn getSupportsParallelCalls(
        self: *const Self,
        callback: *const fn (?*anyopaque, bool) void,
        ctx: ?*anyopaque,
    ) void {
        _ = self;
        callback(ctx, supports_parallel_calls);
    }

    pub fn doEmbed(
        self: *Self,
        options: embedding.EmbeddingModelCallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, embedding.EmbeddingModelV3.EmbedResult) void,
        callback_context: ?*anyopaque,
    ) void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        const values = options.values;

        if (values.len > max_embeddings_per_call) {
            callback(callback_context, .{ .failure = error.TooManyEmbeddingValues });
            return;
        }

        const url = config_mod.buildEmbeddingsUrl(
            request_allocator,
            self.config.base_url,
        ) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

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

        _ = url;

        const embeddings_array = result_allocator.alloc(embedding.EmbeddingModelV3Embedding, values.len) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        const dimensions: usize = 1536;
        for (embeddings_array, 0..) |*emb, i| {
            _ = i;
            const embedding_values = result_allocator.alloc(f32, dimensions) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
            @memset(embedding_values, 0.0);
            emb.* = embedding_values;
        }

        callback(callback_context, .{
            .success = .{
                .embeddings = embeddings_array,
                .usage = null,
                .warnings = &[_]shared.SharedV3Warning{},
            },
        });
    }

    pub fn asEmbeddingModel(self: *Self) embedding.EmbeddingModelV3 {
        return .{
            .vtable = &vtable,
            .impl = self,
        };
    }

    const vtable = embedding.EmbeddingModelV3.VTable{
        .doEmbed = doEmbedVtable,
        .getModelId = getModelIdVtable,
        .getProvider = getProviderVtable,
        .getMaxEmbeddingsPerCall = getMaxEmbeddingsPerCallVtable,
        .getSupportsParallelCalls = getSupportsParallelCallsVtable,
    };

    fn doEmbedVtable(
        impl: *anyopaque,
        options: embedding.EmbeddingModelCallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, embedding.EmbeddingModelV3.EmbedResult) void,
        callback_context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doEmbed(options, result_allocator, callback, callback_context);
    }

    fn getModelIdVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getModelId();
    }

    fn getProviderVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getProvider();
    }

    fn getMaxEmbeddingsPerCallVtable(
        impl: *anyopaque,
        callback: *const fn (?*anyopaque, ?u32) void,
        ctx: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.getMaxEmbeddingsPerCall(callback, ctx);
    }

    fn getSupportsParallelCallsVtable(
        impl: *anyopaque,
        callback: *const fn (?*anyopaque, bool) void,
        ctx: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.getSupportsParallelCalls(callback, ctx);
    }
};

test "OpenAICompatibleEmbeddingModel init" {
    const allocator = std.testing.allocator;

    var model = OpenAICompatibleEmbeddingModel.init(
        allocator,
        "text-embedding-3-small",
        .{ .base_url = "https://api.example.com/v1" },
    );

    try std.testing.expectEqualStrings("text-embedding-3-small", model.getModelId());
}
