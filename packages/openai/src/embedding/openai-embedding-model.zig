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

    /// Get max embeddings per call (async callback-based)
    pub fn getMaxEmbeddingsPerCall(
        self: *const Self,
        callback: *const fn (?*anyopaque, ?u32) void,
        context: ?*anyopaque,
    ) void {
        _ = self;
        callback(context, max_embeddings_per_call);
    }

    /// Get supports parallel calls (async callback-based)
    pub fn getSupportsParallelCalls(
        self: *const Self,
        callback: *const fn (?*anyopaque, bool) void,
        context: ?*anyopaque,
    ) void {
        _ = self;
        callback(context, supports_parallel_calls);
    }

    /// Generate embeddings
    pub fn doEmbed(
        self: *const Self,
        call_options: em.EmbeddingModelCallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, em.EmbeddingModelV3.EmbedResult) void,
        context: ?*anyopaque,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Check max embeddings
        if (call_options.values.len > max_embeddings_per_call) {
            callback(context, .{
                .failure = error.TooManyEmbeddingValues,
            });
            return;
        }

        const result = self.doEmbedInternal(request_allocator, result_allocator, call_options) catch |err| {
            callback(context, .{ .failure = err });
            return;
        };

        callback(context, .{ .success = result });
    }

    fn doEmbedInternal(
        self: *const Self,
        request_allocator: std.mem.Allocator,
        result_allocator: std.mem.Allocator,
        call_options: em.EmbeddingModelCallOptions,
    ) !em.EmbeddingModelV3.EmbedSuccess {
        // Dimensions would come from provider-specific options
        // For now, we don't extract dimensions from provider_options
        const dimensions: ?u32 = null;

        // Build request
        const request = api.OpenAITextEmbeddingRequest{
            .model = self.model_id,
            .input = call_options.values,
            .encoding_format = "float",
            .dimensions = dimensions,
            .user = null,
        };

        // Build URL
        const url = try self.config.buildUrl(request_allocator, "/embeddings", self.model_id);

        // Get headers
        var headers = try self.config.getHeaders(request_allocator);
        if (call_options.headers) |user_headers| {
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
        var call_response: ?provider_utils.HttpResponse = null;

        try http_client.post(url, headers, body, request_allocator,
            struct {
                fn onResponse(ctx: ?*anyopaque, resp: provider_utils.HttpResponse) void {
                    const r: *?provider_utils.HttpResponse = @ptrCast(@alignCast(ctx.?));
                    r.* = resp;
                }
            }.onResponse,
            struct {
                fn onError(_: ?*anyopaque, _: provider_utils.HttpError) void {}
            }.onError,
            @as(?*anyopaque, @ptrCast(&call_response)),
        );

        const http_response = call_response orelse return error.NoResponse;
        if (!http_response.isSuccess()) return error.ApiCallError;
        const response_body = http_response.body;

        // Parse response
        const parsed = std.json.parseFromSlice(api.OpenAITextEmbeddingResponse, request_allocator, response_body, .{}) catch {
            return error.InvalidResponse;
        };
        const response = parsed.value;

        // Extract embeddings and sort by index
        var embeddings = try result_allocator.alloc(em.EmbeddingModelV3Embedding, response.data.len);
        for (response.data) |item| {
            embeddings[item.index] = try result_allocator.dupe(f32, item.embedding);
        }

        // Convert usage
        const usage: ?em.EmbeddingModelV3.Usage = if (response.usage) |u| .{
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
        .getSupportsParallelCalls = getSupportsParallelCallsVtable,
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

    fn getMaxEmbeddingsPerCallVtable(
        impl: *anyopaque,
        callback: *const fn (?*anyopaque, ?u32) void,
        context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.getMaxEmbeddingsPerCall(callback, context);
    }

    fn getSupportsParallelCallsVtable(
        impl: *anyopaque,
        callback: *const fn (?*anyopaque, bool) void,
        context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.getSupportsParallelCalls(callback, context);
    }

    fn doEmbedVtable(
        impl: *anyopaque,
        call_options: em.EmbeddingModelCallOptions,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, em.EmbeddingModelV3.EmbedResult) void,
        context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doEmbed(call_options, allocator, callback, context);
    }
};

/// Options for embedding (legacy compatibility)
pub const EmbedOptions = struct {
    dimensions: ?u32 = null,
    user: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
};

/// Result of embed call (legacy compatibility)
pub const EmbedResult = em.EmbeddingModelV3.EmbedResult;

/// Serialize request to JSON
fn serializeRequest(allocator: std.mem.Allocator, request: api.OpenAITextEmbeddingRequest) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, request, .{});
}

test "OpenAIEmbeddingModel basic" {
    const allocator = std.testing.allocator;

    const config = config_mod.OpenAIConfig{
        .provider = "openai.embedding",
        .base_url = "https://api.openai.com/v1",
        .headers_fn = struct {
            fn getHeaders(_: *const config_mod.OpenAIConfig, alloc: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(alloc);
            }
        }.getHeaders,
    };

    const model = OpenAIEmbeddingModel.init(allocator, "text-embedding-3-small", config);
    try std.testing.expectEqualStrings("openai.embedding", model.getProvider());
    try std.testing.expectEqualStrings("text-embedding-3-small", model.getModelId());
}
