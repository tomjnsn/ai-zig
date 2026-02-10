const std = @import("std");

/// RequestContext provides timeout and cancellation support for API calls.
/// It also stores arbitrary metadata as key-value pairs.
pub const RequestContext = struct {
    allocator: std.mem.Allocator,
    deadline_ms: ?i64 = null,
    cancelled: std.atomic.Value(bool),
    metadata: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) RequestContext {
        return .{
            .allocator = allocator,
            .deadline_ms = null,
            .cancelled = std.atomic.Value(bool).init(false),
            .metadata = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *RequestContext) void {
        self.metadata.deinit();
    }

    /// Set a timeout in milliseconds from now.
    pub fn withTimeout(self: *RequestContext, timeout_ms: u64) void {
        const now = std.time.milliTimestamp();
        self.deadline_ms = now + @as(i64, @intCast(timeout_ms));
    }

    /// Cancel the request. Thread-safe.
    pub fn cancel(self: *RequestContext) void {
        self.cancelled.store(true, .release);
    }

    /// Check if the request has been cancelled. Thread-safe.
    pub fn isCancelled(self: *const RequestContext) bool {
        return self.cancelled.load(.acquire);
    }

    /// Check if the deadline has passed.
    pub fn isExpired(self: *const RequestContext) bool {
        const deadline = self.deadline_ms orelse return false;
        return std.time.milliTimestamp() >= deadline;
    }

    /// Returns true if the request should stop (cancelled or expired).
    pub fn isDone(self: *const RequestContext) bool {
        return self.isCancelled() or self.isExpired();
    }

    /// Store a metadata key-value pair.
    pub fn setMetadata(self: *RequestContext, key: []const u8, value: []const u8) !void {
        try self.metadata.put(key, value);
    }

    /// Retrieve a metadata value by key.
    pub fn getMetadata(self: *const RequestContext, key: []const u8) ?[]const u8 {
        return self.metadata.get(key);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "RequestContext init and deinit" {
    var ctx = RequestContext.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expect(!ctx.isCancelled());
    try std.testing.expect(!ctx.isExpired());
    try std.testing.expect(!ctx.isDone());
    try std.testing.expect(ctx.deadline_ms == null);
}

test "RequestContext cancellation" {
    var ctx = RequestContext.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expect(!ctx.isCancelled());
    ctx.cancel();
    try std.testing.expect(ctx.isCancelled());
    try std.testing.expect(ctx.isDone());
}

test "RequestContext timeout expires" {
    var ctx = RequestContext.init(std.testing.allocator);
    defer ctx.deinit();

    // Set a deadline in the past (already expired)
    ctx.deadline_ms = 0;
    try std.testing.expect(ctx.isExpired());
    try std.testing.expect(ctx.isDone());
}

test "RequestContext timeout not yet expired" {
    var ctx = RequestContext.init(std.testing.allocator);
    defer ctx.deinit();

    // Set a timeout far in the future
    ctx.withTimeout(60_000); // 60 seconds
    try std.testing.expect(!ctx.isExpired());
    try std.testing.expect(!ctx.isDone());
}

test "RequestContext metadata storage" {
    var ctx = RequestContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.setMetadata("request_id", "abc-123");
    try ctx.setMetadata("user", "test-user");

    try std.testing.expectEqualStrings("abc-123", ctx.getMetadata("request_id").?);
    try std.testing.expectEqualStrings("test-user", ctx.getMetadata("user").?);
    try std.testing.expect(ctx.getMetadata("nonexistent") == null);
}

test "RequestContext metadata overwrite" {
    var ctx = RequestContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.setMetadata("key", "value1");
    try ctx.setMetadata("key", "value2");

    try std.testing.expectEqualStrings("value2", ctx.getMetadata("key").?);
}

test "RequestContext isDone combines cancelled and expired" {
    var ctx = RequestContext.init(std.testing.allocator);
    defer ctx.deinit();

    // Neither cancelled nor expired
    ctx.withTimeout(60_000);
    try std.testing.expect(!ctx.isDone());

    // Cancel makes isDone true even when not expired
    ctx.cancel();
    try std.testing.expect(ctx.isDone());
}

test "RequestContext isExpired returns false without deadline" {
    var ctx = RequestContext.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expect(!ctx.isExpired());
}
