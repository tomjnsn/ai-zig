const std = @import("std");
const ai_sdk_error = @import("ai-sdk-error.zig");

pub const AiSdkError = ai_sdk_error.AiSdkError;
pub const AiSdkErrorInfo = ai_sdk_error.AiSdkErrorInfo;
pub const TooManyEmbeddingValuesContext = ai_sdk_error.TooManyEmbeddingValuesContext;

/// Too Many Embedding Values For Call Error - thrown when too many values are passed for embedding
pub const TooManyEmbeddingValuesForCallError = struct {
    info: AiSdkErrorInfo,

    const Self = @This();

    pub const Options = struct {
        provider: []const u8,
        model_id: []const u8,
        max_embeddings_per_call: u32,
        values_count: usize,
    };

    /// Create a new too many embedding values error
    pub fn init(options: Options) Self {
        return Self{
            .info = .{
                .kind = .too_many_embedding_values,
                .message = "Too many values for a single embedding call",
                .context = .{ .too_many_embedding_values = .{
                    .provider = options.provider,
                    .model_id = options.model_id,
                    .max_embeddings_per_call = options.max_embeddings_per_call,
                    .values_count = options.values_count,
                } },
            },
        };
    }

    /// Get the provider name
    pub fn provider(self: Self) []const u8 {
        if (self.info.context) |ctx| {
            if (ctx == .too_many_embedding_values) {
                return ctx.too_many_embedding_values.provider;
            }
        }
        return "";
    }

    /// Get the model ID
    pub fn modelId(self: Self) []const u8 {
        if (self.info.context) |ctx| {
            if (ctx == .too_many_embedding_values) {
                return ctx.too_many_embedding_values.model_id;
            }
        }
        return "";
    }

    /// Get the maximum embeddings per call
    pub fn maxEmbeddingsPerCall(self: Self) u32 {
        if (self.info.context) |ctx| {
            if (ctx == .too_many_embedding_values) {
                return ctx.too_many_embedding_values.max_embeddings_per_call;
            }
        }
        return 0;
    }

    /// Get the number of values that were provided
    pub fn valuesCount(self: Self) usize {
        if (self.info.context) |ctx| {
            if (ctx == .too_many_embedding_values) {
                return ctx.too_many_embedding_values.values_count;
            }
        }
        return 0;
    }

    /// Get the error message
    pub fn message(self: Self) []const u8 {
        return self.info.message;
    }

    /// Convert to AiSdkError
    pub fn toError(self: Self) AiSdkError {
        _ = self;
        return error.TooManyEmbeddingValuesForCallError;
    }

    /// Format the error with context
    pub fn format(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        const writer = list.writer(allocator);

        try writer.print(
            "Too many values for a single embedding call. " ++
                "The {s} model \"{s}\" can only embed up to {d} values per call, " ++
                "but {d} values were provided.",
            .{
                self.provider(),
                self.modelId(),
                self.maxEmbeddingsPerCall(),
                self.valuesCount(),
            },
        );

        return list.toOwnedSlice(allocator);
    }
};

test "TooManyEmbeddingValuesForCallError creation" {
    const err = TooManyEmbeddingValuesForCallError.init(.{
        .provider = "openai",
        .model_id = "text-embedding-3-small",
        .max_embeddings_per_call = 2048,
        .values_count = 5000,
    });

    try std.testing.expectEqualStrings("openai", err.provider());
    try std.testing.expectEqualStrings("text-embedding-3-small", err.modelId());
    try std.testing.expectEqual(@as(u32, 2048), err.maxEmbeddingsPerCall());
    try std.testing.expectEqual(@as(usize, 5000), err.valuesCount());
}
