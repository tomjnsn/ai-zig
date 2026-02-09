const std = @import("std");
const shared = @import("../../shared/v3/index.zig");
const json_value = @import("../../json-value/index.zig");
const EmbeddingModelV3Embedding = @import("embedding-model-v3-embedding.zig").EmbeddingModelV3Embedding;

/// Call options for embedding generation
pub const EmbeddingModelCallOptions = struct {
    /// List of text values to generate embeddings for.
    values: []const []const u8,

    /// Additional provider-specific options.
    provider_options: ?shared.SharedV3ProviderOptions = null,

    /// Additional HTTP headers to be sent with the request.
    headers: ?shared.SharedV3Headers = null,
};

/// Specification for an embedding model that implements version 3.
/// It is specific to text embeddings.
///
/// ## Lifetime Requirements
/// This is a type-erased interface using vtable dispatch. The caller must ensure:
/// - `impl` must outlive every use of this `EmbeddingModelV3` value.
/// - `vtable` should point to a `const` with static lifetime (typically a file-level `const`).
/// - Do not store an `EmbeddingModelV3` beyond the lifetime of the concrete model it wraps.
pub const EmbeddingModelV3 = struct {
    /// VTable for dynamic dispatch (must have static lifetime)
    vtable: *const VTable,
    /// Type-erased implementation pointer (must outlive this struct)
    impl: *anyopaque,

    pub const specification_version = "v3";

    /// Virtual function table for embedding model operations
    pub const VTable = struct {
        /// Get the provider name
        getProvider: *const fn (*anyopaque) []const u8,

        /// Get the model ID
        getModelId: *const fn (*anyopaque) []const u8,

        /// Get max embeddings per call
        getMaxEmbeddingsPerCall: *const fn (
            *anyopaque,
            *const fn (?*anyopaque, ?u32) void,
            ?*anyopaque,
        ) void,

        /// Check if parallel calls are supported
        getSupportsParallelCalls: *const fn (
            *anyopaque,
            *const fn (?*anyopaque, bool) void,
            ?*anyopaque,
        ) void,

        /// Generate embeddings
        doEmbed: *const fn (
            *anyopaque,
            EmbeddingModelCallOptions,
            std.mem.Allocator,
            *const fn (?*anyopaque, EmbedResult) void,
            ?*anyopaque,
        ) void,
    };

    /// Result of embedding generation
    pub const EmbedResult = union(enum) {
        success: EmbedSuccess,
        failure: anyerror,
    };

    /// Successful embedding result
    pub const EmbedSuccess = struct {
        /// Generated embeddings in the same order as input values.
        embeddings: []const EmbeddingModelV3Embedding,

        /// Token usage (input tokens only for embeddings).
        usage: ?Usage = null,

        /// Additional provider-specific metadata.
        provider_metadata: ?shared.SharedV3ProviderMetadata = null,

        /// Optional response information.
        response: ?ResponseInfo = null,

        /// Warnings for the call.
        warnings: []const shared.SharedV3Warning = &[_]shared.SharedV3Warning{},
    };

    /// Token usage for embeddings
    pub const Usage = struct {
        tokens: u64,
    };

    /// Response information
    pub const ResponseInfo = struct {
        headers: ?shared.SharedV3Headers = null,
        body: ?json_value.JsonValue = null,
    };

    const Self = @This();

    /// Get the provider name
    pub fn getProvider(self: Self) []const u8 {
        return self.vtable.getProvider(self.impl);
    }

    /// Get the model ID
    pub fn getModelId(self: Self) []const u8 {
        return self.vtable.getModelId(self.impl);
    }

    /// Get max embeddings per call (async)
    pub fn getMaxEmbeddingsPerCall(
        self: Self,
        callback: *const fn (?*anyopaque, ?u32) void,
        ctx: ?*anyopaque,
    ) void {
        self.vtable.getMaxEmbeddingsPerCall(self.impl, callback, ctx);
    }

    /// Check if parallel calls are supported (async)
    pub fn getSupportsParallelCalls(
        self: Self,
        callback: *const fn (?*anyopaque, bool) void,
        ctx: ?*anyopaque,
    ) void {
        self.vtable.getSupportsParallelCalls(self.impl, callback, ctx);
    }

    /// Generate embeddings
    pub fn doEmbed(
        self: Self,
        options: EmbeddingModelCallOptions,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, EmbedResult) void,
        ctx: ?*anyopaque,
    ) void {
        self.vtable.doEmbed(self.impl, options, allocator, callback, ctx);
    }

    /// Get a string identifier for this model
    pub fn getId(self: Self, allocator: std.mem.Allocator) ![]u8 {
        const provider = self.getProvider();
        const model_id = self.getModelId();
        return std.fmt.allocPrint(allocator, "{s}:{s}", .{ provider, model_id });
    }
};

/// Helper to implement an embedding model from a concrete type
pub fn implementEmbeddingModel(comptime T: type) EmbeddingModelV3.VTable {
    return .{
        .getProvider = struct {
            fn getProvider(ptr: *anyopaque) []const u8 {
                const self: *T = @ptrCast(@alignCast(ptr));
                return self.getProvider();
            }
        }.getProvider,

        .getModelId = struct {
            fn getModelId(ptr: *anyopaque) []const u8 {
                const self: *T = @ptrCast(@alignCast(ptr));
                return self.getModelId();
            }
        }.getModelId,

        .getMaxEmbeddingsPerCall = struct {
            fn getMaxEmbeddingsPerCall(
                ptr: *anyopaque,
                callback: *const fn (?*anyopaque, ?u32) void,
                ctx: ?*anyopaque,
            ) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.getMaxEmbeddingsPerCall(callback, ctx);
            }
        }.getMaxEmbeddingsPerCall,

        .getSupportsParallelCalls = struct {
            fn getSupportsParallelCalls(
                ptr: *anyopaque,
                callback: *const fn (?*anyopaque, bool) void,
                ctx: ?*anyopaque,
            ) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.getSupportsParallelCalls(callback, ctx);
            }
        }.getSupportsParallelCalls,

        .doEmbed = struct {
            fn doEmbed(
                ptr: *anyopaque,
                options: EmbeddingModelCallOptions,
                allocator: std.mem.Allocator,
                callback: *const fn (?*anyopaque, EmbeddingModelV3.EmbedResult) void,
                ctx: ?*anyopaque,
            ) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.doEmbed(options, allocator, callback, ctx);
            }
        }.doEmbed,
    };
}

/// Create an EmbeddingModelV3 from a concrete implementation
pub fn asEmbeddingModel(comptime T: type, impl: *T) EmbeddingModelV3 {
    const vtable = comptime implementEmbeddingModel(T);
    return .{
        .vtable = &vtable,
        .impl = impl,
    };
}

test "EmbeddingModelV3 specification_version" {
    try std.testing.expectEqualStrings("v3", EmbeddingModelV3.specification_version);
}
