const std = @import("std");
const embedding = @import("provider").embedding_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");

const config_mod = @import("google-vertex-config.zig");
const options_mod = @import("google-vertex-options.zig");
const response_types = @import("google-vertex-response.zig");

/// Google Vertex AI Embedding Model
pub const GoogleVertexEmbeddingModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.GoogleVertexConfig,

    /// Maximum embeddings per API call
    pub const max_embeddings_per_call: usize = 2048;

    /// Supports parallel calls
    pub const supports_parallel_calls: bool = true;

    /// Create a new Google Vertex AI embedding model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.GoogleVertexConfig,
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
        const provider_options: ?options_mod.GoogleVertexEmbeddingProviderOptions = null;
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
        const url = std.fmt.allocPrint(
            request_allocator,
            "{s}/models/{s}:predict",
            .{ self.config.base_url, self.model_id },
        ) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Build request body
        var body = std.json.ObjectMap.init(request_allocator);

        // Build instances array
        var instances = std.json.Array.init(request_allocator);
        for (values) |value| {
            var instance = std.json.ObjectMap.init(request_allocator);
            instance.put("content", .{ .string = value }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };

            if (provider_options) |opts| {
                if (opts.task_type) |task| {
                    instance.put("task_type", .{ .string = task.toString() }) catch |err| {
                        callback(callback_context, .{ .failure = err });
                        return;
                    };
                }
                if (opts.title) |title| {
                    instance.put("title", .{ .string = title }) catch |err| {
                        callback(callback_context, .{ .failure = err });
                        return;
                    };
                }
            }

            instances.append(.{ .object = instance }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }
        body.put("instances", .{ .array = instances }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Build parameters
        var parameters = std.json.ObjectMap.init(request_allocator);
        if (provider_options) |opts| {
            if (opts.output_dimensionality) |dim| {
                const dim_val = provider_utils.safeCast(i64, dim) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
                parameters.put("outputDimensionality", .{ .integer = dim_val }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
            if (opts.auto_truncate) |truncate| {
                parameters.put("autoTruncate", .{ .bool = truncate }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
        }
        if (parameters.count() > 0) {
            body.put("parameters", .{ .object = parameters }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        // Get headers
        var headers = if (self.config.headers_fn) |headers_fn|
            headers_fn(&self.config, request_allocator) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            }
        else
            std.StringHashMap([]const u8).init(request_allocator);

        headers.put("Content-Type", "application/json") catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Serialize request body
        var body_buffer = std.ArrayList(u8).empty;
        std.json.stringify(.{ .object = body }, .{}, body_buffer.writer(request_allocator)) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Get HTTP client
        const http_client = self.config.http_client orelse {
            callback(callback_context, .{ .failure = error.NoHttpClient });
            return;
        };

        // Convert headers to slice
        var header_list = std.ArrayList(provider_utils.HttpHeader).empty;
        var header_iter = headers.iterator();
        while (header_iter.next()) |entry| {
            header_list.append(request_allocator, .{
                .name = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        // Create context for callback
        const ResponseContext = struct {
            response_body: ?[]const u8 = null,
            response_error: ?provider_utils.HttpError = null,
        };
        var response_ctx = ResponseContext{};

        // Make HTTP request
        http_client.request(
            .{
                .method = .POST,
                .url = url,
                .headers = header_list.items,
                .body = body_buffer.items,
            },
            request_allocator,
            struct {
                fn onResponse(ctx: ?*anyopaque, response: provider_utils.HttpResponse) void {
                    const rctx: *ResponseContext = @ptrCast(@alignCast(ctx.?));
                    rctx.response_body = response.body;
                }
            }.onResponse,
            struct {
                fn onError(ctx: ?*anyopaque, err: provider_utils.HttpError) void {
                    const rctx: *ResponseContext = @ptrCast(@alignCast(ctx.?));
                    rctx.response_error = err;
                }
            }.onError,
            &response_ctx,
        );

        // Check for errors
        if (response_ctx.response_error != null) {
            callback(callback_context, .{ .failure = error.HttpRequestFailed });
            return;
        }

        const response_body = response_ctx.response_body orelse {
            callback(callback_context, .{ .failure = error.NoResponse });
            return;
        };

        // Parse response
        const parsed = response_types.VertexPredictEmbeddingResponse.fromJson(request_allocator, response_body) catch {
            callback(callback_context, .{ .failure = error.InvalidResponse });
            return;
        };
        const response = parsed.value;

        // Extract embeddings from response
        var embed_list = std.ArrayList(embedding.EmbeddingModelV3Embedding).empty;
        var total_tokens: u32 = 0;

        if (response.predictions) |predictions| {
            for (predictions) |pred| {
                if (pred.embeddings) |emb| {
                    if (emb.values) |emb_values| {
                        const values_copy = result_allocator.dupe(f32, emb_values) catch |err| {
                            callback(callback_context, .{ .failure = err });
                            return;
                        };
                        embed_list.append(result_allocator, .{ .embedding = .{ .float = values_copy } }) catch |err| {
                            callback(callback_context, .{ .failure = err });
                            return;
                        };

                        if (emb.statistics) |stats| {
                            if (stats.token_count) |tc| {
                                total_tokens += tc;
                            }
                        }
                    }
                }
            }
        }

        const result = embedding.EmbeddingModelV3.EmbedSuccess{
            .embeddings = embed_list.toOwnedSlice(result_allocator) catch &[_]embedding.EmbeddingModelV3Embedding{},
            .usage = .{
                .tokens = total_tokens,
            },
            .warnings = &[_]shared.SharedV3Warning{},
        };

        callback(callback_context, .{ .success = result });
    }

    /// Convert to EmbeddingModelV3 interface
    pub fn asEmbeddingModel(self: *Self) embedding.EmbeddingModelV3 {
        return embedding.asEmbeddingModel(Self, self);
    }
};

test "GoogleVertexEmbeddingModel init" {
    const allocator = std.testing.allocator;

    var model = GoogleVertexEmbeddingModel.init(
        allocator,
        "text-embedding-004",
        .{ .base_url = "https://us-central1-aiplatform.googleapis.com" },
    );

    try std.testing.expectEqualStrings("text-embedding-004", model.getModelId());
    try std.testing.expectEqual(@as(usize, 2048), GoogleVertexEmbeddingModel.max_embeddings_per_call);
}

test "GoogleVertexEmbeddingModel max embeddings constant" {
    try std.testing.expectEqual(@as(usize, 2048), GoogleVertexEmbeddingModel.max_embeddings_per_call);
    try std.testing.expectEqual(true, GoogleVertexEmbeddingModel.supports_parallel_calls);
}

test "Vertex embedding response parsing" {
    const allocator = std.testing.allocator;
    const response_json =
        \\{"predictions":[{"embeddings":{"values":[0.1,0.2,0.3],"statistics":{"token_count":5}}}]}
    ;

    const parsed = try response_types.VertexPredictEmbeddingResponse.fromJson(allocator, response_json);
    defer parsed.deinit();
    const response = parsed.value;

    try std.testing.expect(response.predictions != null);
    try std.testing.expectEqual(@as(usize, 1), response.predictions.?.len);
}
