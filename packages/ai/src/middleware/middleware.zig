const std = @import("std");
const provider_types = @import("provider");
const generate_text = @import("../generate-text/generate-text.zig");

const LanguageModelV3 = provider_types.LanguageModelV3;
const CallSettings = generate_text.CallSettings;

/// Middleware function type for transforming requests
pub const RequestMiddleware = *const fn (
    request: *MiddlewareRequest,
    context: *MiddlewareContext,
) anyerror!void;

/// Middleware function type for transforming responses
pub const ResponseMiddleware = *const fn (
    response: *MiddlewareResponse,
    context: *MiddlewareContext,
) anyerror!void;

/// Request data passed through middleware
pub const MiddlewareRequest = struct {
    /// The prompt/messages
    prompt: ?[]const u8 = null,

    /// Call settings
    settings: CallSettings = .{},

    /// Headers to send
    headers: ?std.StringHashMap([]const u8) = null,

    /// Provider-specific options
    provider_options: ?std.json.Value = null,

    /// Custom metadata
    metadata: ?std.StringHashMap([]const u8) = null,
};

/// Response data passed through middleware
pub const MiddlewareResponse = struct {
    /// Generated text
    text: ?[]const u8 = null,

    /// Usage information
    usage: ?generate_text.LanguageModelUsage = null,

    /// Finish reason
    finish_reason: ?generate_text.FinishReason = null,

    /// Response headers
    headers: ?std.StringHashMap([]const u8) = null,

    /// Custom metadata
    metadata: ?std.StringHashMap([]const u8) = null,
};

/// Context passed through middleware chain
pub const MiddlewareContext = struct {
    /// Allocator for middleware operations
    allocator: std.mem.Allocator,

    /// The underlying model
    model: ?*LanguageModelV3 = null,

    /// Whether the request was cancelled
    cancelled: bool = false,

    /// Custom data storage
    data: std.StringHashMap(*anyopaque),

    pub fn init(allocator: std.mem.Allocator) MiddlewareContext {
        return .{
            .allocator = allocator,
            .data = std.StringHashMap(*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *MiddlewareContext) void {
        self.data.deinit();
    }

    /// Store custom data
    pub fn set(self: *MiddlewareContext, key: []const u8, value: *anyopaque) !void {
        try self.data.put(key, value);
    }

    /// Retrieve custom data
    pub fn get(self: *MiddlewareContext, key: []const u8) ?*anyopaque {
        return self.data.get(key);
    }
};

/// Middleware chain for processing requests/responses
pub const MiddlewareChain = struct {
    allocator: std.mem.Allocator,
    request_middleware: std.ArrayList(RequestMiddleware),
    response_middleware: std.ArrayList(ResponseMiddleware),

    pub fn init(allocator: std.mem.Allocator) MiddlewareChain {
        return .{
            .allocator = allocator,
            .request_middleware = std.ArrayList(RequestMiddleware).empty,
            .response_middleware = std.ArrayList(ResponseMiddleware).empty,
        };
    }

    pub fn deinit(self: *MiddlewareChain) void {
        self.request_middleware.deinit(self.allocator);
        self.response_middleware.deinit(self.allocator);
    }

    /// Add request middleware
    pub fn useRequest(self: *MiddlewareChain, middleware: RequestMiddleware) !void {
        try self.request_middleware.append(self.allocator, middleware);
    }

    /// Add response middleware
    pub fn useResponse(self: *MiddlewareChain, middleware: ResponseMiddleware) !void {
        try self.response_middleware.append(self.allocator, middleware);
    }

    /// Process request through all middleware
    pub fn processRequest(
        self: *MiddlewareChain,
        request: *MiddlewareRequest,
        context: *MiddlewareContext,
    ) !void {
        for (self.request_middleware.items) |middleware| {
            try middleware(request, context);
            if (context.cancelled) break;
        }
    }

    /// Process response through all middleware (in reverse order)
    pub fn processResponse(
        self: *MiddlewareChain,
        response: *MiddlewareResponse,
        context: *MiddlewareContext,
    ) !void {
        var i = self.response_middleware.items.len;
        while (i > 0) {
            i -= 1;
            try self.response_middleware.items[i](response, context);
        }
    }
};

/// Default settings middleware - applies default values to requests
pub const DefaultSettingsMiddleware = struct {
    defaults: CallSettings,

    pub fn process(request: *MiddlewareRequest, context: *MiddlewareContext) anyerror!void {
        _ = context;
        _ = request;

        // Apply defaults if not set
        // This is a simplified version - would need proper integration
        // Note: @fieldParentPtr API changed in Zig 0.15
        // Old: @fieldParentPtr(Type, "field", ptr)
        // New: @fieldParentPtr(ptr, @offsetOf(Type, "field"))
        // This middleware needs restructuring to work with the new API
    }
};

/// Logging middleware context - stores the log function
pub const LoggingMiddlewareContext = struct {
    log_fn: *const fn ([]const u8) void,

    const key = "logging_middleware_context";

    pub fn init(log_fn: *const fn ([]const u8) void) LoggingMiddlewareContext {
        return .{ .log_fn = log_fn };
    }

    pub fn store(self: *LoggingMiddlewareContext, context: *MiddlewareContext) !void {
        try context.set(key, @ptrCast(self));
    }

    pub fn retrieve(context: *MiddlewareContext) ?*LoggingMiddlewareContext {
        if (context.get(key)) |ptr| {
            return @ptrCast(@alignCast(ptr));
        }
        return null;
    }
};

/// Logging middleware - logs requests and responses
/// Note: You must store a LoggingMiddlewareContext in the MiddlewareContext before using these middleware functions
pub fn createLoggingMiddleware() struct { request: RequestMiddleware, response: ResponseMiddleware } {
    const RequestLogger = struct {
        fn process(request: *MiddlewareRequest, context: *MiddlewareContext) anyerror!void {
            if (LoggingMiddlewareContext.retrieve(context)) |ctx| {
                if (request.prompt) |p| {
                    ctx.log_fn(p);
                }
            }
        }
    };

    const ResponseLogger = struct {
        fn process(response: *MiddlewareResponse, context: *MiddlewareContext) anyerror!void {
            if (LoggingMiddlewareContext.retrieve(context)) |ctx| {
                if (response.text) |t| {
                    ctx.log_fn(t);
                }
            }
        }
    };

    return .{
        .request = RequestLogger.process,
        .response = ResponseLogger.process,
    };
}

/// Rate limiting middleware using a fixed-window algorithm.
/// Store a RateLimitMiddleware instance in the MiddlewareContext before use.
pub const RateLimitMiddleware = struct {
    requests_per_minute: u32,
    window_start: i64 = 0,
    request_count: u32 = 0,

    const context_key = "rate_limit_middleware";

    pub fn store(self: *RateLimitMiddleware, context: *MiddlewareContext) !void {
        try context.set(context_key, @ptrCast(self));
    }

    fn retrieve(context: *MiddlewareContext) ?*RateLimitMiddleware {
        if (context.get(context_key)) |ptr| {
            return @ptrCast(@alignCast(ptr));
        }
        return null;
    }

    /// Request middleware function that enforces the rate limit.
    pub fn process(request: *MiddlewareRequest, context: *MiddlewareContext) anyerror!void {
        _ = request;
        const self = retrieve(context) orelse return;

        const now = std.time.timestamp();
        const window_elapsed = now - self.window_start;

        // Start a new window if 60 seconds have passed
        if (window_elapsed >= 60) {
            self.window_start = now;
            self.request_count = 0;
        }

        // Check if we've exceeded the limit
        if (self.request_count >= self.requests_per_minute) {
            context.cancelled = true;
            return error.RateLimitExceeded;
        }

        self.request_count += 1;
    }
};

/// Retry middleware configuration
pub const RetryConfig = struct {
    max_retries: u32 = 3,
    initial_delay_ms: u64 = 1000,
    max_delay_ms: u64 = 30000,
    backoff_multiplier: f64 = 2.0,
};

/// Caching middleware configuration
pub const CacheConfig = struct {
    max_entries: usize = 1000,
    ttl_seconds: u64 = 3600,
};

/// Token counter middleware - accumulates token usage across requests.
/// Store a TokenCounter in the MiddlewareContext before use.
pub const TokenCounter = struct {
    total_input_tokens: u64 = 0,
    total_output_tokens: u64 = 0,
    total_requests: u64 = 0,

    const context_key = "token_counter";

    pub fn store(self: *TokenCounter, context: *MiddlewareContext) !void {
        try context.set(context_key, @ptrCast(self));
    }

    fn retrieve(context: *MiddlewareContext) ?*TokenCounter {
        if (context.get(context_key)) |ptr| {
            return @ptrCast(@alignCast(ptr));
        }
        return null;
    }

    /// Response middleware that accumulates token counts from usage data.
    pub fn process(response: *MiddlewareResponse, context: *MiddlewareContext) anyerror!void {
        const self = retrieve(context) orelse return;
        self.total_requests += 1;
        if (response.usage) |usage| {
            self.total_input_tokens += usage.input_tokens orelse 0;
            self.total_output_tokens += usage.output_tokens orelse 0;
        }
    }

    /// Total tokens (input + output)
    pub fn totalTokens(self: *const TokenCounter) u64 {
        return self.total_input_tokens + self.total_output_tokens;
    }

    /// Reset all counters
    pub fn reset(self: *TokenCounter) void {
        self.total_input_tokens = 0;
        self.total_output_tokens = 0;
        self.total_requests = 0;
    }
};

/// Structured log entry emitted by StructuredLoggingMiddleware
pub const StructuredLogEntry = struct {
    timestamp: i64,
    event: []const u8,
    prompt_preview: ?[]const u8 = null,
    text_preview: ?[]const u8 = null,
    input_tokens: ?u64 = null,
    output_tokens: ?u64 = null,
    latency_ms: ?i64 = null,
};

/// Structured logging middleware - logs request/response with timestamps and token usage.
/// Store a StructuredLoggingMiddleware in the MiddlewareContext before use.
pub const StructuredLoggingMiddleware = struct {
    log_fn: *const fn (StructuredLogEntry) void,
    request_start: i64 = 0,

    const context_key = "structured_logging_middleware";
    const preview_max = 100;

    pub fn store(self: *StructuredLoggingMiddleware, context: *MiddlewareContext) !void {
        try context.set(context_key, @ptrCast(self));
    }

    fn retrieve(context: *MiddlewareContext) ?*StructuredLoggingMiddleware {
        if (context.get(context_key)) |ptr| {
            return @ptrCast(@alignCast(ptr));
        }
        return null;
    }

    fn truncate(s: []const u8) []const u8 {
        return if (s.len > preview_max) s[0..preview_max] else s;
    }

    /// Request middleware: records timestamp, logs prompt preview.
    pub fn processRequest(request: *MiddlewareRequest, context: *MiddlewareContext) anyerror!void {
        const self = retrieve(context) orelse return;
        self.request_start = std.time.milliTimestamp();
        self.log_fn(.{
            .timestamp = self.request_start,
            .event = "request",
            .prompt_preview = if (request.prompt) |p| truncate(p) else null,
        });
    }

    /// Response middleware: computes latency, logs response + token counts.
    pub fn processResponse(response: *MiddlewareResponse, context: *MiddlewareContext) anyerror!void {
        const self = retrieve(context) orelse return;
        const now = std.time.milliTimestamp();
        const latency = if (self.request_start > 0) now - self.request_start else null;
        var input_tokens: ?u64 = null;
        var output_tokens: ?u64 = null;
        if (response.usage) |usage| {
            input_tokens = usage.input_tokens;
            output_tokens = usage.output_tokens;
        }
        self.log_fn(.{
            .timestamp = now,
            .event = "response",
            .text_preview = if (response.text) |t| truncate(t) else null,
            .input_tokens = input_tokens,
            .output_tokens = output_tokens,
            .latency_ms = latency,
        });
    }
};

/// Cache entry storing a cached response and metadata
const CacheEntry = struct {
    text: []const u8,
    timestamp: i64,
};

/// Cached response stored in context data on cache hit.
/// Caller can retrieve via `context.get(CacheMiddleware.hit_key)`.
pub const CachedResponse = struct {
    text: []const u8,
};

/// Cache middleware - caches responses keyed by prompt text.
/// On cache hit during request phase, stores CachedResponse in context
/// data under `hit_key` and sets `context.cancelled = true`.
/// On response phase, caches the response for future lookups.
/// Uses `pending_prompt` to carry the prompt from request to response phase.
pub const CacheMiddleware = struct {
    config: CacheConfig,
    entries: std.StringHashMap(CacheEntry),
    allocator: std.mem.Allocator,
    pending_prompt: ?[]const u8 = null,

    const context_key = "cache_middleware";
    pub const hit_key = "cache_hit_response";

    pub fn init(allocator: std.mem.Allocator, config: CacheConfig) CacheMiddleware {
        return .{
            .config = config,
            .entries = std.StringHashMap(CacheEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CacheMiddleware) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*.text);
        }
        self.entries.deinit();
    }

    pub fn store(self: *CacheMiddleware, context: *MiddlewareContext) !void {
        try context.set(context_key, @ptrCast(self));
    }

    fn retrieve(context: *MiddlewareContext) ?*CacheMiddleware {
        if (context.get(context_key)) |ptr| {
            return @ptrCast(@alignCast(ptr));
        }
        return null;
    }

    fn evictExpired(self: *CacheMiddleware, now: i64) void {
        const ttl: i64 = @intCast(self.config.ttl_seconds);
        var to_remove = std.ArrayList([]const u8).empty;
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (now - entry.value_ptr.*.timestamp > ttl) {
                to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }
        for (to_remove.items) |key| {
            if (self.entries.fetchRemove(key)) |kv| {
                self.allocator.free(kv.value.text);
                self.allocator.free(kv.key);
            }
        }
        to_remove.deinit(self.allocator);
    }

    fn evictOldest(self: *CacheMiddleware) void {
        var oldest_key: ?[]const u8 = null;
        var oldest_ts: i64 = std.math.maxInt(i64);
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*.timestamp < oldest_ts) {
                oldest_ts = entry.value_ptr.*.timestamp;
                oldest_key = entry.key_ptr.*;
            }
        }
        if (oldest_key) |key| {
            if (self.entries.fetchRemove(key)) |kv| {
                self.allocator.free(kv.value.text);
                self.allocator.free(kv.key);
            }
        }
    }

    /// Request middleware: check cache, on hit store response in context and cancel.
    /// Stores prompt in `pending_prompt` for use in processResponse.
    pub fn processRequest(request: *MiddlewareRequest, context: *MiddlewareContext) anyerror!void {
        const self = retrieve(context) orelse return;
        const prompt = request.prompt orelse return;

        self.pending_prompt = prompt;

        if (self.entries.get(prompt)) |entry| {
            const now = std.time.timestamp();
            const ttl: i64 = @intCast(self.config.ttl_seconds);
            if (now - entry.timestamp <= ttl) {
                const cached = try context.allocator.create(CachedResponse);
                cached.* = .{ .text = entry.text };
                try context.set(hit_key, @ptrCast(cached));
                context.cancelled = true;
                self.pending_prompt = null;
                return;
            }
            if (self.entries.fetchRemove(prompt)) |kv| {
                self.allocator.free(kv.value.text);
                self.allocator.free(kv.key);
            }
        }
    }

    /// Response middleware: cache the response text keyed by the prompt from processRequest.
    pub fn processResponse(response: *MiddlewareResponse, context: *MiddlewareContext) anyerror!void {
        const self = retrieve(context) orelse return;
        const text = response.text orelse return;
        const prompt = self.pending_prompt orelse return;
        self.pending_prompt = null;

        self.evictExpired(std.time.timestamp());
        if (self.entries.count() >= self.config.max_entries) {
            self.evictOldest();
        }

        const key = try self.allocator.dupe(u8, prompt);
        errdefer self.allocator.free(key);
        const val = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(val);

        try self.entries.put(key, .{ .text = val, .timestamp = std.time.timestamp() });
    }
};

test "MiddlewareChain init and deinit" {
    const allocator = std.testing.allocator;
    var chain = MiddlewareChain.init(allocator);
    defer chain.deinit();

    try std.testing.expectEqual(@as(usize, 0), chain.request_middleware.items.len);
}

test "MiddlewareContext init and deinit" {
    const allocator = std.testing.allocator;
    var context = MiddlewareContext.init(allocator);
    defer context.deinit();

    try std.testing.expect(!context.cancelled);
}

test "MiddlewareChain add middleware" {
    const allocator = std.testing.allocator;
    var chain = MiddlewareChain.init(allocator);
    defer chain.deinit();

    const testMiddleware = struct {
        fn process(_: *MiddlewareRequest, _: *MiddlewareContext) anyerror!void {}
    }.process;

    try chain.useRequest(testMiddleware);
    try std.testing.expectEqual(@as(usize, 1), chain.request_middleware.items.len);
}

test "RateLimitMiddleware allows requests within limit" {
    const allocator = std.testing.allocator;

    var rate_limiter = RateLimitMiddleware{ .requests_per_minute = 5 };
    var context = MiddlewareContext.init(allocator);
    defer context.deinit();
    try rate_limiter.store(&context);

    var request = MiddlewareRequest{};

    // Should allow up to 5 requests
    for (0..5) |_| {
        try RateLimitMiddleware.process(&request, &context);
    }

    try std.testing.expectEqual(@as(u32, 5), rate_limiter.request_count);
    try std.testing.expect(!context.cancelled);
}

test "RateLimitMiddleware rejects requests over limit" {
    const allocator = std.testing.allocator;

    var rate_limiter = RateLimitMiddleware{ .requests_per_minute = 2 };
    var context = MiddlewareContext.init(allocator);
    defer context.deinit();
    try rate_limiter.store(&context);

    var request = MiddlewareRequest{};

    // Allow first 2
    try RateLimitMiddleware.process(&request, &context);
    try RateLimitMiddleware.process(&request, &context);

    // Third should fail
    const result = RateLimitMiddleware.process(&request, &context);
    try std.testing.expectError(error.RateLimitExceeded, result);
    try std.testing.expect(context.cancelled);
}

test "RateLimitMiddleware resets after window" {
    const allocator = std.testing.allocator;

    var rate_limiter = RateLimitMiddleware{ .requests_per_minute = 1 };
    var context = MiddlewareContext.init(allocator);
    defer context.deinit();
    try rate_limiter.store(&context);

    var request = MiddlewareRequest{};

    // First request should work
    try RateLimitMiddleware.process(&request, &context);

    // Simulate window expiry by setting window_start to 61 seconds ago
    rate_limiter.window_start = std.time.timestamp() - 61;

    // Should work again after window reset
    context.cancelled = false;
    try RateLimitMiddleware.process(&request, &context);
    try std.testing.expectEqual(@as(u32, 1), rate_limiter.request_count);
}

test "RateLimitMiddleware no-op without stored context" {
    const allocator = std.testing.allocator;

    var context = MiddlewareContext.init(allocator);
    defer context.deinit();

    var request = MiddlewareRequest{};

    // Should not error when no rate limiter is stored
    try RateLimitMiddleware.process(&request, &context);
}

// -- TokenCounter tests --

test "TokenCounter accumulates tokens" {
    const allocator = std.testing.allocator;

    var counter = TokenCounter{};
    var context = MiddlewareContext.init(allocator);
    defer context.deinit();
    try counter.store(&context);

    var response = MiddlewareResponse{
        .usage = .{ .input_tokens = 10, .output_tokens = 20 },
    };
    try TokenCounter.process(&response, &context);

    try std.testing.expectEqual(@as(u64, 10), counter.total_input_tokens);
    try std.testing.expectEqual(@as(u64, 20), counter.total_output_tokens);
    try std.testing.expectEqual(@as(u64, 30), counter.totalTokens());
    try std.testing.expectEqual(@as(u64, 1), counter.total_requests);

    // Accumulate more
    var response2 = MiddlewareResponse{
        .usage = .{ .input_tokens = 5, .output_tokens = 15 },
    };
    try TokenCounter.process(&response2, &context);

    try std.testing.expectEqual(@as(u64, 15), counter.total_input_tokens);
    try std.testing.expectEqual(@as(u64, 35), counter.total_output_tokens);
    try std.testing.expectEqual(@as(u64, 2), counter.total_requests);
}

test "TokenCounter no-op without usage" {
    const allocator = std.testing.allocator;

    var counter = TokenCounter{};
    var context = MiddlewareContext.init(allocator);
    defer context.deinit();
    try counter.store(&context);

    var response = MiddlewareResponse{};
    try TokenCounter.process(&response, &context);

    try std.testing.expectEqual(@as(u64, 0), counter.totalTokens());
    try std.testing.expectEqual(@as(u64, 1), counter.total_requests);
}

test "TokenCounter no-op without stored context" {
    const allocator = std.testing.allocator;

    var context = MiddlewareContext.init(allocator);
    defer context.deinit();

    var response = MiddlewareResponse{
        .usage = .{ .input_tokens = 10, .output_tokens = 20 },
    };
    try TokenCounter.process(&response, &context);
}

test "TokenCounter reset" {
    const allocator = std.testing.allocator;

    var counter = TokenCounter{};
    var context = MiddlewareContext.init(allocator);
    defer context.deinit();
    try counter.store(&context);

    var response = MiddlewareResponse{
        .usage = .{ .input_tokens = 10, .output_tokens = 20 },
    };
    try TokenCounter.process(&response, &context);
    try std.testing.expectEqual(@as(u64, 30), counter.totalTokens());

    counter.reset();
    try std.testing.expectEqual(@as(u64, 0), counter.totalTokens());
    try std.testing.expectEqual(@as(u64, 0), counter.total_requests);
}

// -- StructuredLoggingMiddleware tests --

test "StructuredLoggingMiddleware logs request and response" {
    const allocator = std.testing.allocator;

    const State = struct {
        var last_event: ?[]const u8 = null;
        var last_prompt_preview: ?[]const u8 = null;
        var last_text_preview: ?[]const u8 = null;
        var last_input_tokens: ?u64 = null;

        fn log(entry: StructuredLogEntry) void {
            last_event = entry.event;
            last_prompt_preview = entry.prompt_preview;
            last_text_preview = entry.text_preview;
            last_input_tokens = entry.input_tokens;
        }
    };

    var logger = StructuredLoggingMiddleware{ .log_fn = State.log };
    var context = MiddlewareContext.init(allocator);
    defer context.deinit();
    try logger.store(&context);

    // Request
    var request = MiddlewareRequest{ .prompt = "Hello, world!" };
    try StructuredLoggingMiddleware.processRequest(&request, &context);
    try std.testing.expectEqualStrings("request", State.last_event.?);
    try std.testing.expectEqualStrings("Hello, world!", State.last_prompt_preview.?);

    // Response
    var response = MiddlewareResponse{
        .text = "Hi there!",
        .usage = .{ .input_tokens = 5, .output_tokens = 10 },
    };
    try StructuredLoggingMiddleware.processResponse(&response, &context);
    try std.testing.expectEqualStrings("response", State.last_event.?);
    try std.testing.expectEqualStrings("Hi there!", State.last_text_preview.?);
    try std.testing.expectEqual(@as(u64, 5), State.last_input_tokens.?);
}

test "StructuredLoggingMiddleware truncates long prompts" {
    const allocator = std.testing.allocator;

    const State = struct {
        var last_preview_len: usize = 0;

        fn log(entry: StructuredLogEntry) void {
            if (entry.prompt_preview) |p| {
                last_preview_len = p.len;
            }
        }
    };

    var logger = StructuredLoggingMiddleware{ .log_fn = State.log };
    var context = MiddlewareContext.init(allocator);
    defer context.deinit();
    try logger.store(&context);

    var request = MiddlewareRequest{ .prompt = "a" ** 200 };
    try StructuredLoggingMiddleware.processRequest(&request, &context);
    try std.testing.expectEqual(@as(usize, 100), State.last_preview_len);
}

test "StructuredLoggingMiddleware no-op without stored context" {
    const allocator = std.testing.allocator;

    var context = MiddlewareContext.init(allocator);
    defer context.deinit();

    var request = MiddlewareRequest{ .prompt = "test" };
    try StructuredLoggingMiddleware.processRequest(&request, &context);
}

// -- CacheMiddleware tests --

test "CacheMiddleware cache miss then hit" {
    const allocator = std.testing.allocator;

    var cache = CacheMiddleware.init(allocator, .{ .max_entries = 10, .ttl_seconds = 3600 });
    defer cache.deinit();

    var context = MiddlewareContext.init(allocator);
    defer context.deinit();
    try cache.store(&context);

    // First request: cache miss
    var request = MiddlewareRequest{ .prompt = "What is AI?" };
    try CacheMiddleware.processRequest(&request, &context);
    try std.testing.expect(!context.cancelled);

    // Simulate response
    var response = MiddlewareResponse{ .text = "AI is artificial intelligence." };
    try CacheMiddleware.processResponse(&response, &context);

    // Second request: cache hit
    var context2 = MiddlewareContext.init(allocator);
    defer context2.deinit();
    try cache.store(&context2);

    var request2 = MiddlewareRequest{ .prompt = "What is AI?" };
    try CacheMiddleware.processRequest(&request2, &context2);
    try std.testing.expect(context2.cancelled);

    // Verify cached response is retrievable
    if (context2.get(CacheMiddleware.hit_key)) |ptr| {
        const cached: *CachedResponse = @ptrCast(@alignCast(ptr));
        try std.testing.expectEqualStrings("AI is artificial intelligence.", cached.text);
        // Clean up the allocated CachedResponse
        allocator.destroy(cached);
    } else {
        return error.TestExpectedEqual;
    }
}

test "CacheMiddleware evicts when full" {
    const allocator = std.testing.allocator;

    var cache = CacheMiddleware.init(allocator, .{ .max_entries = 2, .ttl_seconds = 3600 });
    defer cache.deinit();

    // Insert 2 entries
    var context1 = MiddlewareContext.init(allocator);
    defer context1.deinit();
    try cache.store(&context1);
    var req1 = MiddlewareRequest{ .prompt = "q1" };
    try CacheMiddleware.processRequest(&req1, &context1);
    var resp1 = MiddlewareResponse{ .text = "a1" };
    try CacheMiddleware.processResponse(&resp1, &context1);

    var context2 = MiddlewareContext.init(allocator);
    defer context2.deinit();
    try cache.store(&context2);
    var req2 = MiddlewareRequest{ .prompt = "q2" };
    try CacheMiddleware.processRequest(&req2, &context2);
    var resp2 = MiddlewareResponse{ .text = "a2" };
    try CacheMiddleware.processResponse(&resp2, &context2);

    try std.testing.expectEqual(@as(u32, 2), cache.entries.count());

    // Insert 3rd entry, should evict oldest
    var context3 = MiddlewareContext.init(allocator);
    defer context3.deinit();
    try cache.store(&context3);
    var req3 = MiddlewareRequest{ .prompt = "q3" };
    try CacheMiddleware.processRequest(&req3, &context3);
    var resp3 = MiddlewareResponse{ .text = "a3" };
    try CacheMiddleware.processResponse(&resp3, &context3);

    try std.testing.expectEqual(@as(u32, 2), cache.entries.count());
}

test "CacheMiddleware no-op without stored context" {
    const allocator = std.testing.allocator;

    var context = MiddlewareContext.init(allocator);
    defer context.deinit();

    var request = MiddlewareRequest{ .prompt = "test" };
    try CacheMiddleware.processRequest(&request, &context);
    try std.testing.expect(!context.cancelled);
}
