const std = @import("std");
const em = @import("provider").embedding_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");

const api = @import("openai-embedding-api.zig");
const options_mod = @import("openai-embedding-options.zig");
const config_mod = @import("../openai-config.zig");
const error_mod = @import("../openai-error.zig");

/// OpenAI Embedding Model implementation
pub const OpenAIEmbeddingModel = struct {
    const Self = @This();

    /// Model ID
    model_id: []const u8,

    /// Configuration
    config: config_mod.OpenAIConfig,

    /// Allocator for internal operations
    allocator: std.mem.Allocator,

    /// Maximum embeddings per call
    pub const max_embeddings_per_call: usize = 2048;

    /// Supports parallel calls
    pub const supports_parallel_calls: bool = true;

    pub const specification_version = "v3";

    /// Initialize a new OpenAI embedding model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.OpenAIConfig,
    ) Self {
        return .{
            .model_id = model_id,
            .config = config,
            .allocator = allocator,
        };
    }

    /// Get the provider name
    pub fn getProvider(self: *const Self) []const u8 {
        return self.config.provider;
    }

    /// Get the model ID
    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    /// Get max embeddings per call
    pub fn getMaxEmbeddingsPerCall(self: *const Self) usize {
        _ = self;
        return max_embeddings_per_call;
    }

    /// Generate embeddings
    pub fn doEmbed(
        self: *const Self,
        values: []const []const u8,
        options: EmbedOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, EmbedResult) void,
        context: ?*anyopaque,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Check max embeddings
        if (values.len > max_embeddings_per_call) {
            callback(context, .{
                .err = error.TooManyEmbeddingValues,
            });
            return;
        }

        const result = self.doEmbedInternal(request_allocator, result_allocator, values, options) catch |err| {
            callback(context, .{ .failure = err });
            return;
        };

        callback(context, .{ .success = result });
    }

    fn doEmbedInternal(
        self: *const Self,
        request_allocator: std.mem.Allocator,
        result_allocator: std.mem.Allocator,
        values: []const []const u8,
        options: EmbedOptions,
    ) !EmbedResultOk {
        // Build request
        const request = api.OpenAITextEmbeddingRequest{
            .model = self.model_id,
            .input = values,
            .encoding_format = "float",
            .dimensions = options.dimensions,
            .user = options.user,
        };

        // Build URL
        const url = try self.config.buildUrl(request_allocator, "/embeddings", self.model_id);

        // Get headers
        var headers = self.config.getHeaders(request_allocator);
        if (options.headers) |user_headers| {
            var iter = user_headers.iterator();
            while (iter.next()) |entry| {
                try headers.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Make HTTP request
        const http_client = self.config.http_client orelse return error.NoHttpClient;

        // Serialize request body
        const body = try serializeRequest(request_allocator, request);

        // Make the request
        var response_data: ?[]const u8 = null;
        var response_headers: ?std.StringHashMap([]const u8) = null;

        http_client.post(url, headers, body, request_allocator, struct {
            fn onResponse(ctx: *anyopaque, resp_headers: std.StringHashMap([]const u8), resp_body: []const u8) void {
                const data = @as(*struct { body: *?[]const u8, headers: *?std.StringHashMap([]const u8) }, @ptrCast(@alignCast(ctx)));
                data.body.* = resp_body;
                data.headers.* = resp_headers;
            }
            fn onError(_: *anyopaque, _: anyerror) void {}
        }.onResponse, struct {
            fn onError(_: *anyopaque, _: anyerror) void {}
        }.onError, &.{ .body = &response_data, .headers = &response_headers });

        const response_body = response_data orelse return error.NoResponse;

        // Parse response
        const parsed = std.json.parseFromSlice(api.OpenAITextEmbeddingResponse, request_allocator, response_body, .{}) catch {
            return error.InvalidResponse;
        };
        const response = parsed.value;

        // Extract embeddings and sort by index
        var embeddings = try result_allocator.alloc(em.Embedding, response.data.len);
        for (response.data) |item| {
            embeddings[item.index] = .{
                .values = try result_allocator.dupe(f32, item.embedding),
            };
        }

        // Convert usage
        const usage: ?em.EmbeddingUsage = if (response.usage) |u| .{
            .tokens = u.prompt_tokens,
        } else null;

        return .{
            .embeddings = embeddings,
            .usage = usage,
            .warnings = &[_]shared.SharedV3Warning{},
        };
    }

    /// Convert to EmbeddingModelV3 interface
    pub fn asEmbeddingModel(self: *Self) em.EmbeddingModelV3 {
        return .{
            .vtable = &vtable,
            .impl = self,
        };
    }

    const vtable = em.EmbeddingModelV3.VTable{
        .getProvider = getProviderVtable,
        .getModelId = getModelIdVtable,
        .getMaxEmbeddingsPerCall = getMaxEmbeddingsPerCallVtable,
        .doEmbed = doEmbedVtable,
    };

    fn getProviderVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getProvider();
    }

    fn getModelIdVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getModelId();
    }

    fn getMaxEmbeddingsPerCallVtable(impl: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getMaxEmbeddingsPerCall();
    }

    fn doEmbedVtable(
        impl: *anyopaque,
        values: []const []const u8,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, EmbedResult) void,
        context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doEmbed(values, .{}, allocator, callback, context);
    }
};

/// Options for embedding
pub const EmbedOptions = struct {
    dimensions: ?u32 = null,
    user: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
};

/// Result of embed call
pub const EmbedResult = union(enum) {
    ok: EmbedResultOk,
    err: anyerror,
};

pub const EmbedResultOk = struct {
    embeddings: []em.Embedding,
    usage: ?em.EmbeddingUsage,
    warnings: []shared.SharedV3Warning,
};

/// Serialize request to JSON
fn serializeRequest(allocator: std.mem.Allocator, request: api.OpenAITextEmbeddingRequest) ![]const u8 {
    var buffer = std.array_list.Managed(u8).init(allocator);
    try std.json.stringify(request, .{}, buffer.writer());
    return buffer.toOwnedSlice();
}

test "OpenAIEmbeddingModel basic" {
    const allocator = std.testing.allocator;

    const config = config_mod.OpenAIConfig{
        .provider = "openai.embedding",
        .base_url = "https://api.openai.com/v1",
        .headers_fn = struct {
            fn getHeaders(_: *const config_mod.OpenAIConfig) std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(std.testing.allocator);
            }
        }.getHeaders,
    };

    const model = OpenAIEmbeddingModel.init(allocator, "text-embedding-3-small", config);
    try std.testing.expectEqualStrings("openai.embedding", model.getProvider());
    try std.testing.expectEqualStrings("text-embedding-3-small", model.getModelId());
    try std.testing.expectEqual(@as(usize, 2048), model.getMaxEmbeddingsPerCall());
}
