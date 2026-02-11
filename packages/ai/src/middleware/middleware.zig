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

/// Rate limiting middleware
pub const RateLimitMiddleware = struct {
    requests_per_minute: u32,
    last_request_time: i64 = 0,
    request_count: u32 = 0,

    pub fn process(request: *MiddlewareRequest, context: *MiddlewareContext) anyerror!void {
        _ = request;
        _ = context;
        // TODO: Implement rate limiting logic
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
