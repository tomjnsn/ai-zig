const std = @import("std");
const embedding = @import("provider").embedding_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");

const config_mod = @import("google-config.zig");
const options_mod = @import("google-generative-ai-options.zig");

/// Google Generative AI Embedding Model
pub const GoogleGenerativeAIEmbeddingModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.GoogleGenerativeAIConfig,

    /// Maximum embeddings per API call
    pub const max_embeddings_per_call: usize = 2048;

    /// Supports parallel calls
    pub const supports_parallel_calls: bool = true;

    /// Create a new Google Generative AI embedding model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.GoogleGenerativeAIConfig,
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
        const provider_options: ?options_mod.GoogleGenerativeAIEmbeddingProviderOptions = null;
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Check max embeddings
        if (values.len > max_embeddings_per_call) {
            callback(callback_context, .{ .failure = error.TooManyEmbeddingValues });
            return;
        }

        // Build URL - use single or batch endpoint
        const url = if (values.len == 1)
            std.fmt.allocPrint(
                request_allocator,
                "{s}/models/{s}:embedContent",
                .{ self.config.base_url, self.model_id },
            ) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            }
        else
            std.fmt.allocPrint(
                request_allocator,
                "{s}/models/{s}:batchEmbedContents",
                .{ self.config.base_url, self.model_id },
            ) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };

        // Build request body
        var body = std.json.ObjectMap.init(request_allocator);

        if (values.len == 1) {
            // Single embedding request
            try body.put("model", .{ .string = std.fmt.allocPrint(
                request_allocator,
                "models/{s}",
                .{self.model_id},
            ) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            } });

            var content = std.json.ObjectMap.init(request_allocator);
            var parts = std.json.Array.init(request_allocator);
            var part = std.json.ObjectMap.init(request_allocator);
            part.put("text", .{ .string = values[0] }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
            parts.append(.{ .object = part }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
            content.put("parts", .{ .array = parts }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
            body.put("content", .{ .object = content }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        } else {
            // Batch embedding request
            var requests = std.json.Array.init(request_allocator);
            for (values) |value| {
                var req = std.json.ObjectMap.init(request_allocator);
                req.put("model", .{ .string = std.fmt.allocPrint(
                    request_allocator,
                    "models/{s}",
                    .{self.model_id},
                ) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                } }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };

                var content = std.json.ObjectMap.init(request_allocator);
                content.put("role", .{ .string = "user" }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };

                var parts = std.json.Array.init(request_allocator);
                var part = std.json.ObjectMap.init(request_allocator);
                part.put("text", .{ .string = value }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
                parts.append(.{ .object = part }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
                content.put("parts", .{ .array = parts }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };

                req.put("content", .{ .object = content }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };

                // Add provider options
                if (provider_options) |opts| {
                    if (opts.output_dimensionality) |dim| {
                        req.put("outputDimensionality", .{ .integer = @intCast(dim) }) catch |err| {
                            callback(callback_context, .{ .failure = err });
                            return;
                        };
                    }
                    if (opts.task_type) |task| {
                        req.put("taskType", .{ .string = task.toString() }) catch |err| {
                            callback(callback_context, .{ .failure = err });
                            return;
                        };
                    }
                }

                requests.append(.{ .object = req }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
            body.put("requests", .{ .array = requests }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        // Get headers
        const headers = if (self.config.headers_fn) |headers_fn|
            headers_fn(&self.config, request_allocator)
        else
            std.StringHashMap([]const u8).init(request_allocator);

        // TODO: Make HTTP request with url and headers
        _ = url;
        _ = headers;

        // For now, return placeholder result
        // Actual implementation would make HTTP request and parse response
        const embeddings = result_allocator.alloc([]f32, values.len) catch |err| {
            callback(null, err, callback_context);
            return;
        };
        for (embeddings, 0..) |*emb, i| {
            _ = i;
            emb.* = result_allocator.alloc(f32, 768) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
            @memset(emb.*, 0.0);
        }

        // Convert embeddings to proper format
        var embed_list = std.ArrayList(embedding.EmbeddingModelV3Embedding).init(result_allocator);
        for (embeddings) |emb| {
            embed_list.append(.{ .embedding = .{ .float = emb } }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        const result = embedding.EmbeddingModelV3.EmbedSuccess{
            .embeddings = embed_list.toOwnedSlice() catch &[_]embedding.EmbeddingModelV3Embedding{},
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

test "GoogleGenerativeAIEmbeddingModel init" {
    const allocator = std.testing.allocator;

    var model = GoogleGenerativeAIEmbeddingModel.init(
        allocator,
        "text-embedding-004",
        .{},
    );

    try std.testing.expectEqualStrings("text-embedding-004", model.getModelId());
    try std.testing.expectEqualStrings("google.generative-ai", model.getProvider());
    try std.testing.expectEqual(@as(usize, 2048), GoogleGenerativeAIEmbeddingModel.max_embeddings_per_call);
}
