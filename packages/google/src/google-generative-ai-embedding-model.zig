const std = @import("std");
const embedding = @import("provider").embedding_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");

const config_mod = @import("google-config.zig");
const options_mod = @import("google-generative-ai-options.zig");
const response_types = @import("google-generative-ai-response.zig");

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
        var headers = if (self.config.headers_fn) |headers_fn|
            headers_fn(&self.config, request_allocator)
        else
            std.StringHashMap([]const u8).init(request_allocator);

        headers.put("Content-Type", "application/json") catch {};

        // Serialize request body
        var body_buffer = std.ArrayList(u8).init(request_allocator);
        std.json.stringify(.{ .object = body }, .{}, body_buffer.writer()) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Get HTTP client
        const http_client = self.config.http_client orelse {
            callback(callback_context, .{ .failure = error.NoHttpClient });
            return;
        };

        // Convert headers to slice
        var header_list = std.ArrayList(provider_utils.HttpHeader).init(request_allocator);
        var header_iter = headers.iterator();
        while (header_iter.next()) |entry| {
            header_list.append(.{
                .name = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            }) catch {};
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

        // Parse response and extract embeddings
        var embed_list = std.ArrayList(embedding.EmbeddingModelV3Embedding).init(result_allocator);

        if (values.len == 1) {
            // Parse single embedding response
            const parsed = response_types.GoogleEmbedContentResponse.fromJson(request_allocator, response_body) catch {
                callback(callback_context, .{ .failure = error.InvalidResponse });
                return;
            };
            const response = parsed.value;

            if (response.embedding) |emb| {
                if (emb.values) |emb_values| {
                    const values_copy = result_allocator.dupe(f32, emb_values) catch {
                        callback(callback_context, .{ .failure = error.OutOfMemory });
                        return;
                    };
                    embed_list.append(.{ .embedding = .{ .float = values_copy } }) catch {};
                }
            }
        } else {
            // Parse batch embedding response
            const parsed = response_types.GoogleBatchEmbedContentsResponse.fromJson(request_allocator, response_body) catch {
                callback(callback_context, .{ .failure = error.InvalidResponse });
                return;
            };
            const response = parsed.value;

            if (response.embeddings) |embeddings| {
                for (embeddings) |emb| {
                    if (emb.values) |emb_values| {
                        const values_copy = result_allocator.dupe(f32, emb_values) catch continue;
                        embed_list.append(.{ .embedding = .{ .float = values_copy } }) catch {};
                    }
                }
            }
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
