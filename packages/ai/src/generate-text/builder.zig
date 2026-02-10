const std = @import("std");
const provider_types = @import("provider");
const generate_text = @import("generate-text.zig");
const stream_text = @import("stream-text.zig");
const context = @import("../context.zig");
const retry = @import("../retry.zig");

const LanguageModelV3 = provider_types.LanguageModelV3;
const GenerateTextOptions = generate_text.GenerateTextOptions;
const GenerateTextResult = generate_text.GenerateTextResult;
const GenerateTextError = generate_text.GenerateTextError;
const StreamTextOptions = stream_text.StreamTextOptions;
const StreamTextResult = stream_text.StreamTextResult;
const StreamTextError = stream_text.StreamTextError;
const StreamCallbacks = stream_text.StreamCallbacks;
const CallSettings = generate_text.CallSettings;
const Message = generate_text.Message;
const RequestContext = context.RequestContext;
const RetryPolicy = retry.RetryPolicy;

/// Fluent builder for text generation requests.
pub const TextGenerationBuilder = struct {
    allocator: std.mem.Allocator,
    _model: ?*LanguageModelV3 = null,
    _prompt: ?[]const u8 = null,
    _system: ?[]const u8 = null,
    _messages: ?[]const Message = null,
    _settings: CallSettings = .{},
    _max_steps: u32 = 1,
    _max_retries: u32 = 2,
    _request_context: ?*const RequestContext = null,
    _retry_policy: ?RetryPolicy = null,

    pub fn init(allocator: std.mem.Allocator) TextGenerationBuilder {
        return .{ .allocator = allocator };
    }

    pub fn model(self: *TextGenerationBuilder, m: *LanguageModelV3) *TextGenerationBuilder {
        self._model = m;
        return self;
    }

    pub fn prompt(self: *TextGenerationBuilder, p: []const u8) *TextGenerationBuilder {
        self._prompt = p;
        return self;
    }

    pub fn system(self: *TextGenerationBuilder, s: []const u8) *TextGenerationBuilder {
        self._system = s;
        return self;
    }

    pub fn messages(self: *TextGenerationBuilder, msgs: []const Message) *TextGenerationBuilder {
        self._messages = msgs;
        return self;
    }

    pub fn temperature(self: *TextGenerationBuilder, t: f64) *TextGenerationBuilder {
        self._settings.temperature = t;
        return self;
    }

    pub fn maxTokens(self: *TextGenerationBuilder, n: u32) *TextGenerationBuilder {
        self._settings.max_output_tokens = n;
        return self;
    }

    pub fn topP(self: *TextGenerationBuilder, p: f64) *TextGenerationBuilder {
        self._settings.top_p = p;
        return self;
    }

    pub fn maxSteps(self: *TextGenerationBuilder, n: u32) *TextGenerationBuilder {
        self._max_steps = n;
        return self;
    }

    pub fn maxRetries(self: *TextGenerationBuilder, n: u32) *TextGenerationBuilder {
        self._max_retries = n;
        return self;
    }

    pub fn withContext(self: *TextGenerationBuilder, ctx: *const RequestContext) *TextGenerationBuilder {
        self._request_context = ctx;
        return self;
    }

    pub fn withRetry(self: *TextGenerationBuilder, policy: RetryPolicy) *TextGenerationBuilder {
        self._retry_policy = policy;
        return self;
    }

    /// Build the options struct without executing
    pub fn build(self: *const TextGenerationBuilder) GenerateTextOptions {
        return .{
            .model = self._model.?,
            .system = self._system,
            .prompt = self._prompt,
            .messages = self._messages,
            .settings = self._settings,
            .max_steps = self._max_steps,
            .max_retries = self._max_retries,
            .request_context = self._request_context,
            .retry_policy = self._retry_policy,
        };
    }

    /// Build and execute the text generation request
    pub fn execute(self: *const TextGenerationBuilder) GenerateTextError!GenerateTextResult {
        const options = self.build();
        return generate_text.generateText(self.allocator, options);
    }
};

/// Fluent builder for streaming text generation requests.
pub const StreamTextBuilder = struct {
    allocator: std.mem.Allocator,
    _model: ?*LanguageModelV3 = null,
    _prompt: ?[]const u8 = null,
    _system: ?[]const u8 = null,
    _messages: ?[]const Message = null,
    _settings: CallSettings = .{},
    _max_steps: u32 = 1,
    _max_retries: u32 = 2,
    _callbacks: ?StreamCallbacks = null,
    _request_context: ?*const RequestContext = null,
    _retry_policy: ?RetryPolicy = null,

    pub fn init(allocator: std.mem.Allocator) StreamTextBuilder {
        return .{ .allocator = allocator };
    }

    pub fn model(self: *StreamTextBuilder, m: *LanguageModelV3) *StreamTextBuilder {
        self._model = m;
        return self;
    }

    pub fn prompt(self: *StreamTextBuilder, p: []const u8) *StreamTextBuilder {
        self._prompt = p;
        return self;
    }

    pub fn system(self: *StreamTextBuilder, s: []const u8) *StreamTextBuilder {
        self._system = s;
        return self;
    }

    pub fn messages(self: *StreamTextBuilder, msgs: []const Message) *StreamTextBuilder {
        self._messages = msgs;
        return self;
    }

    pub fn temperature(self: *StreamTextBuilder, t: f64) *StreamTextBuilder {
        self._settings.temperature = t;
        return self;
    }

    pub fn maxTokens(self: *StreamTextBuilder, n: u32) *StreamTextBuilder {
        self._settings.max_output_tokens = n;
        return self;
    }

    pub fn callbacks(self: *StreamTextBuilder, cbs: StreamCallbacks) *StreamTextBuilder {
        self._callbacks = cbs;
        return self;
    }

    pub fn withContext(self: *StreamTextBuilder, ctx: *const RequestContext) *StreamTextBuilder {
        self._request_context = ctx;
        return self;
    }

    pub fn withRetry(self: *StreamTextBuilder, policy: RetryPolicy) *StreamTextBuilder {
        self._retry_policy = policy;
        return self;
    }

    /// Build the options struct without executing
    pub fn build(self: *const StreamTextBuilder) StreamTextOptions {
        return .{
            .model = self._model.?,
            .system = self._system,
            .prompt = self._prompt,
            .messages = self._messages,
            .settings = self._settings,
            .max_steps = self._max_steps,
            .max_retries = self._max_retries,
            .callbacks = self._callbacks.?,
            .request_context = self._request_context,
            .retry_policy = self._retry_policy,
        };
    }

    /// Build and execute the streaming request
    pub fn execute(self: *const StreamTextBuilder) StreamTextError!*StreamTextResult {
        const options = self.build();
        return stream_text.streamText(self.allocator, options);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "TextGenerationBuilder creates valid options" {
    var builder = TextGenerationBuilder.init(std.testing.allocator);

    const model: LanguageModelV3 = undefined;
    _ = builder
        .model(@constCast(&model))
        .prompt("Hello, world!")
        .system("You are a helpful assistant")
        .temperature(0.7)
        .maxTokens(100);

    const options = builder.build();
    try std.testing.expectEqualStrings("Hello, world!", options.prompt.?);
    try std.testing.expectEqualStrings("You are a helpful assistant", options.system.?);
    try std.testing.expectApproxEqAbs(@as(f64, 0.7), options.settings.temperature.?, 0.001);
    try std.testing.expectEqual(@as(?u32, 100), options.settings.max_output_tokens);
}

test "TextGenerationBuilder chains methods fluently" {
    var builder = TextGenerationBuilder.init(std.testing.allocator);

    const model: LanguageModelV3 = undefined;
    // Verify chaining returns self
    const result = builder
        .model(@constCast(&model))
        .prompt("test")
        .temperature(0.5)
        .maxTokens(50)
        .maxSteps(3)
        .maxRetries(5)
        .topP(0.9);

    try std.testing.expect(@intFromPtr(result) == @intFromPtr(&builder));
    try std.testing.expectEqual(@as(u32, 3), builder._max_steps);
    try std.testing.expectEqual(@as(u32, 5), builder._max_retries);
}

test "TextGenerationBuilder with context and retry" {
    var builder = TextGenerationBuilder.init(std.testing.allocator);

    const model: LanguageModelV3 = undefined;
    var ctx = RequestContext.init(std.testing.allocator);
    defer ctx.deinit();

    const policy = RetryPolicy{ .max_retries = 5 };

    _ = builder
        .model(@constCast(&model))
        .prompt("test")
        .withContext(&ctx)
        .withRetry(policy);

    const options = builder.build();
    try std.testing.expect(options.request_context != null);
    try std.testing.expect(options.retry_policy != null);
    try std.testing.expectEqual(@as(u32, 5), options.retry_policy.?.max_retries);
}

test "StreamTextBuilder creates valid options" {
    var builder = StreamTextBuilder.init(std.testing.allocator);

    const model: LanguageModelV3 = undefined;
    const cbs = StreamCallbacks{
        .on_part = struct {
            fn f(_: stream_text.StreamPart, _: ?*anyopaque) void {}
        }.f,
        .on_error = struct {
            fn f(_: anyerror, _: ?*anyopaque) void {}
        }.f,
        .on_complete = struct {
            fn f(_: ?*anyopaque) void {}
        }.f,
    };

    _ = builder
        .model(@constCast(&model))
        .prompt("Stream this")
        .callbacks(cbs)
        .temperature(0.8);

    const options = builder.build();
    try std.testing.expectEqualStrings("Stream this", options.prompt.?);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8), options.settings.temperature.?, 0.001);
}

test "TextGenerationBuilder defaults" {
    const builder = TextGenerationBuilder.init(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 1), builder._max_steps);
    try std.testing.expectEqual(@as(u32, 2), builder._max_retries);
    try std.testing.expect(builder._model == null);
    try std.testing.expect(builder._prompt == null);
    try std.testing.expect(builder._system == null);
    try std.testing.expect(builder._request_context == null);
    try std.testing.expect(builder._retry_policy == null);
}
