const std = @import("std");
const provider_types = @import("provider");
const embed_mod = @import("embed.zig");
const context = @import("../context.zig");
const retry = @import("../retry.zig");

const EmbeddingModelV3 = provider_types.EmbeddingModelV3;
const EmbedOptions = embed_mod.EmbedOptions;
const EmbedResult = embed_mod.EmbedResult;
const EmbedManyOptions = embed_mod.EmbedManyOptions;
const EmbedManyResult = embed_mod.EmbedManyResult;
const EmbedError = embed_mod.EmbedError;
const RequestContext = context.RequestContext;
const RetryPolicy = retry.RetryPolicy;

/// Fluent builder for embedding requests.
pub const EmbedBuilder = struct {
    allocator: std.mem.Allocator,
    _model: ?*EmbeddingModelV3 = null,
    _value: ?[]const u8 = null,
    _values: ?[]const []const u8 = null,
    _max_retries: u32 = 2,
    _request_context: ?*const RequestContext = null,
    _retry_policy: ?RetryPolicy = null,

    pub fn init(allocator: std.mem.Allocator) EmbedBuilder {
        return .{ .allocator = allocator };
    }

    pub fn model(self: *EmbedBuilder, m: *EmbeddingModelV3) *EmbedBuilder {
        self._model = m;
        return self;
    }

    pub fn value(self: *EmbedBuilder, v: []const u8) *EmbedBuilder {
        self._value = v;
        return self;
    }

    pub fn values(self: *EmbedBuilder, v: []const []const u8) *EmbedBuilder {
        self._values = v;
        return self;
    }

    pub fn maxRetries(self: *EmbedBuilder, n: u32) *EmbedBuilder {
        self._max_retries = n;
        return self;
    }

    pub fn withContext(self: *EmbedBuilder, ctx: *const RequestContext) *EmbedBuilder {
        self._request_context = ctx;
        return self;
    }

    pub fn withRetry(self: *EmbedBuilder, policy: RetryPolicy) *EmbedBuilder {
        self._retry_policy = policy;
        return self;
    }

    /// Build single embed options
    pub fn buildEmbed(self: *const EmbedBuilder) EmbedOptions {
        return .{
            .model = self._model.?,
            .value = self._value.?,
            .max_retries = self._max_retries,
            .request_context = self._request_context,
            .retry_policy = self._retry_policy,
        };
    }

    /// Build embed-many options
    pub fn buildEmbedMany(self: *const EmbedBuilder) EmbedManyOptions {
        return .{
            .model = self._model.?,
            .values = self._values.?,
            .max_retries = self._max_retries,
            .request_context = self._request_context,
            .retry_policy = self._retry_policy,
        };
    }

    /// Execute single embedding
    pub fn embed(self: *const EmbedBuilder) EmbedError!EmbedResult {
        const options = self.buildEmbed();
        return embed_mod.embed(self.allocator, options);
    }

    /// Execute batch embedding
    pub fn embedMany(self: *const EmbedBuilder) EmbedError!EmbedManyResult {
        const options = self.buildEmbedMany();
        return embed_mod.embedMany(self.allocator, options);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "EmbedBuilder creates valid embed options" {
    var builder = EmbedBuilder.init(std.testing.allocator);

    const model_val: EmbeddingModelV3 = undefined;
    _ = builder
        .model(@constCast(&model_val))
        .value("Hello, world!")
        .maxRetries(5);

    const options = builder.buildEmbed();
    try std.testing.expectEqualStrings("Hello, world!", options.value);
    try std.testing.expectEqual(@as(u32, 5), options.max_retries);
}

test "EmbedBuilder creates valid embed-many options" {
    var builder = EmbedBuilder.init(std.testing.allocator);

    const model_val: EmbeddingModelV3 = undefined;
    const vals = [_][]const u8{ "Hello", "World" };
    _ = builder
        .model(@constCast(&model_val))
        .values(&vals);

    const options = builder.buildEmbedMany();
    try std.testing.expectEqual(@as(usize, 2), options.values.len);
}

test "EmbedBuilder chains methods fluently" {
    var builder = EmbedBuilder.init(std.testing.allocator);

    const model_val: EmbeddingModelV3 = undefined;
    const result = builder
        .model(@constCast(&model_val))
        .value("test")
        .maxRetries(3);

    try std.testing.expect(@intFromPtr(result) == @intFromPtr(&builder));
}

test "EmbedBuilder with context and retry" {
    var builder = EmbedBuilder.init(std.testing.allocator);

    const model_val: EmbeddingModelV3 = undefined;
    var ctx = RequestContext.init(std.testing.allocator);
    defer ctx.deinit();
    const policy = RetryPolicy{ .max_retries = 3 };

    _ = builder
        .model(@constCast(&model_val))
        .value("test")
        .withContext(&ctx)
        .withRetry(policy);

    const options = builder.buildEmbed();
    try std.testing.expect(options.request_context != null);
    try std.testing.expect(options.retry_policy != null);
}

test "EmbedBuilder defaults" {
    const builder = EmbedBuilder.init(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 2), builder._max_retries);
    try std.testing.expect(builder._model == null);
    try std.testing.expect(builder._value == null);
    try std.testing.expect(builder._request_context == null);
    try std.testing.expect(builder._retry_policy == null);
}
