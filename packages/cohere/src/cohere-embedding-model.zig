const std = @import("std");
const embedding = @import("provider").embedding_model;
const shared = @import("provider").shared;

const config_mod = @import("cohere-config.zig");
const options_mod = @import("cohere-options.zig");

/// Cohere Embedding Model
pub const CohereEmbeddingModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.CohereConfig,
    options: options_mod.CohereEmbeddingOptions,

    /// Maximum embeddings per call
    pub const max_embeddings_per_call: usize = 96;

    /// Supports parallel calls
    pub const supports_parallel_calls: bool = true;

    /// Create a new Cohere embedding model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.CohereConfig,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .config = config,
            .options = .{},
        };
    }

    /// Create with options
    pub fn initWithOptions(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.CohereConfig,
        options: options_mod.CohereEmbeddingOptions,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .config = config,
            .options = options,
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
    pub fn getMaxEmbeddingsPerCall(self: *const Self) usize {
        _ = self;
        return max_embeddings_per_call;
    }

    /// Generate embeddings
    pub fn doEmbed(
        self: *Self,
        values: []const []const u8,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?embedding.EmbeddingModelV3.EmbedResult, ?anyerror, ?*anyopaque) void,
        callback_context: ?*anyopaque,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Check max embeddings
        if (values.len > max_embeddings_per_call) {
            callback(null, error.TooManyEmbeddingValues, callback_context);
            return;
        }

        // Build URL
        const url = config_mod.buildEmbedUrl(
            request_allocator,
            self.config.base_url,
        ) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        // Build request body
        var body = std.json.ObjectMap.init(request_allocator);
        body.put("model", .{ .string = self.model_id }) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        var texts = std.json.Array.init(request_allocator);
        for (values) |value| {
            texts.append(.{ .string = value }) catch |err| {
                callback(null, err, callback_context);
                return;
            };
        }
        body.put("texts", .{ .array = texts }) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        // Add input type
        if (self.options.input_type) |input_type| {
            body.put("input_type", .{ .string = input_type.toString() }) catch |err| {
                callback(null, err, callback_context);
                return;
            };
        } else {
            // Default to search_query
            body.put("input_type", .{ .string = "search_query" }) catch |err| {
                callback(null, err, callback_context);
                return;
            };
        }

        // Add truncation mode
        if (self.options.truncate) |truncate| {
            body.put("truncate", .{ .string = truncate.toString() }) catch |err| {
                callback(null, err, callback_context);
                return;
            };
        }

        body.put("embedding_types", .{ .array = blk: {
            var arr = std.json.Array.init(request_allocator);
            arr.append(.{ .string = "float" }) catch |err| {
                callback(null, err, callback_context);
                return;
            };
            break :blk arr;
        } }) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        _ = url;

        // For now, return placeholder result
        const embeddings = result_allocator.alloc([]f32, values.len) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        // Cohere v3 embeddings are 1024 dimensions
        const dimensions: usize = 1024;
        for (embeddings, 0..) |*emb, i| {
            _ = i;
            emb.* = result_allocator.alloc(f32, dimensions) catch |err| {
                callback(null, err, callback_context);
                return;
            };
            @memset(emb.*, 0.0);
        }

        const result = embedding.EmbeddingModelV3.EmbedResult{
            .embeddings = embeddings,
            .usage = null,
            .warnings = &[_]shared.SharedV3Warning{},
        };

        callback(result, null, callback_context);
    }

    /// Convert to EmbeddingModelV3 interface
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
    };

    fn doEmbedVtable(
        impl: *anyopaque,
        values: []const []const u8,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?embedding.EmbeddingModelV3.EmbedResult, ?anyerror, ?*anyopaque) void,
        callback_context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doEmbed(values, result_allocator, callback, callback_context);
    }

    fn getModelIdVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getModelId();
    }

    fn getProviderVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getProvider();
    }

    fn getMaxEmbeddingsPerCallVtable(impl: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getMaxEmbeddingsPerCall();
    }
};

test "CohereEmbeddingModel init" {
    const allocator = std.testing.allocator;

    var model = CohereEmbeddingModel.init(
        allocator,
        "embed-english-v3.0",
        .{ .base_url = "https://api.cohere.com/v2" },
    );

    try std.testing.expectEqualStrings("embed-english-v3.0", model.getModelId());
    try std.testing.expectEqual(@as(usize, 96), model.getMaxEmbeddingsPerCall());
}
