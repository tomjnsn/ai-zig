const std = @import("std");
const provider_utils = @import("provider-utils");

const config_mod = @import("cohere-config.zig");
const options_mod = @import("cohere-options.zig");

/// Cohere Reranking Model
pub const CohereRerankingModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.CohereConfig,
    options: options_mod.CohereRerankingOptions,

    /// Create a new Cohere reranking model
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
        options: options_mod.CohereRerankingOptions,
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

    /// Reranking result for a single document
    pub const RerankResult = struct {
        index: usize,
        relevance_score: f32,
    };

    /// Rerank documents
    pub fn doRerank(
        self: *Self,
        query: []const u8,
        documents: []const []const u8,
        top_n: ?usize,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?[]RerankResult, ?anyerror, ?*anyopaque) void,
        callback_context: ?*anyopaque,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Build URL
        const url = config_mod.buildRerankUrl(
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
        body.put("query", .{ .string = query }) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        var docs = std.json.Array.init(request_allocator);
        for (documents) |doc| {
            docs.append(.{ .string = doc }) catch |err| {
                callback(null, err, callback_context);
                return;
            };
        }
        body.put("documents", .{ .array = docs }) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        if (top_n) |n| {
            const n_val = provider_utils.safeCast(i64, n) catch |err| {
                callback(null, err, callback_context);
                return;
            };
            body.put("top_n", .{ .integer = n_val }) catch |err| {
                callback(null, err, callback_context);
                return;
            };
        }

        // Add options
        if (self.options.max_tokens_per_doc) |max_tokens| {
            const max_tokens_val = provider_utils.safeCast(i64, max_tokens) catch |err| {
                callback(null, err, callback_context);
                return;
            };
            body.put("max_tokens_per_doc", .{ .integer = max_tokens_val }) catch |err| {
                callback(null, err, callback_context);
                return;
            };
        }

        _ = url;

        // For now, return placeholder result
        const result_count = top_n orelse documents.len;
        const results = result_allocator.alloc(RerankResult, result_count) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        for (results, 0..) |*result, i| {
            result.* = .{
                .index = i,
                .relevance_score = 1.0 - @as(f32, @floatFromInt(i)) * 0.1,
            };
        }

        callback(results, null, callback_context);
    }
};

test "CohereRerankingModel init" {
    const allocator = std.testing.allocator;

    var model = CohereRerankingModel.init(
        allocator,
        "rerank-v3.5",
        .{ .base_url = "https://api.cohere.com/v2" },
    );

    try std.testing.expectEqualStrings("rerank-v3.5", model.getModelId());
}
