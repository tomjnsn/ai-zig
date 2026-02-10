const std = @import("std");

/// Configurable retry policy with exponential backoff and jitter.
pub const RetryPolicy = struct {
    /// Maximum number of retry attempts
    max_retries: u32 = 2,

    /// Initial delay in milliseconds before first retry
    initial_delay_ms: u64 = 1000,

    /// Maximum delay in milliseconds between retries
    max_delay_ms: u64 = 30000,

    /// Multiplier for exponential backoff
    backoff_multiplier: f32 = 2.0,

    /// Whether to add random jitter to delays
    jitter: bool = true,

    /// Retry on rate limit (429) errors
    retry_on_rate_limit: bool = true,

    /// Retry on server (5xx) errors
    retry_on_server_error: bool = true,

    /// Retry on timeout errors
    retry_on_timeout: bool = true,

    /// Determine if a request should be retried based on attempt count and error.
    pub fn shouldRetry(self: *const RetryPolicy, attempt: u32, status_code: ?u16) bool {
        if (attempt >= self.max_retries) return false;

        const code = status_code orelse return false;

        if (code == 429 and self.retry_on_rate_limit) return true;
        if (code == 408 and self.retry_on_timeout) return true;
        if (code >= 500 and self.retry_on_server_error) return true;

        return false;
    }

    /// Calculate the delay in milliseconds for a given retry attempt.
    /// Uses exponential backoff with optional jitter.
    pub fn delayMs(self: *const RetryPolicy, attempt: u32, rand: ?*std.Random) u64 {
        // Calculate base exponential backoff
        var multiplier: f32 = 1.0;
        for (0..attempt) |_| {
            multiplier *= self.backoff_multiplier;
        }

        var delay_f: f64 = @as(f64, @floatFromInt(self.initial_delay_ms)) * @as(f64, multiplier);

        // Add jitter: random value between 0 and current delay
        if (self.jitter) {
            if (rand) |r| {
                const jitter_factor = r.float(f64); // 0.0 to 1.0
                delay_f = delay_f * (0.5 + jitter_factor * 0.5); // 50% to 100% of delay
            }
        }

        // Clamp to max_delay_ms
        const delay: u64 = @intFromFloat(@min(delay_f, @as(f64, @floatFromInt(self.max_delay_ms))));
        return delay;
    }

    /// Default policy: 2 retries with exponential backoff
    pub const default_policy = RetryPolicy{};

    /// Aggressive policy: more retries, longer delays
    pub const aggressive = RetryPolicy{
        .max_retries = 5,
        .initial_delay_ms = 2000,
        .max_delay_ms = 60000,
        .backoff_multiplier = 3.0,
    };

    /// No retry policy
    pub const none = RetryPolicy{
        .max_retries = 0,
    };
};

// ============================================================================
// Tests
// ============================================================================

test "shouldRetry returns true for retryable status codes" {
    const policy = RetryPolicy{};

    try std.testing.expect(policy.shouldRetry(0, 429));
    try std.testing.expect(policy.shouldRetry(0, 500));
    try std.testing.expect(policy.shouldRetry(0, 503));
    try std.testing.expect(policy.shouldRetry(0, 408));
}

test "shouldRetry returns false for non-retryable status codes" {
    const policy = RetryPolicy{};

    try std.testing.expect(!policy.shouldRetry(0, 400));
    try std.testing.expect(!policy.shouldRetry(0, 401));
    try std.testing.expect(!policy.shouldRetry(0, 404));
    try std.testing.expect(!policy.shouldRetry(0, null));
}

test "shouldRetry returns false when max retries exceeded" {
    const policy = RetryPolicy{ .max_retries = 2 };

    try std.testing.expect(policy.shouldRetry(0, 500));
    try std.testing.expect(policy.shouldRetry(1, 500));
    try std.testing.expect(!policy.shouldRetry(2, 500));
    try std.testing.expect(!policy.shouldRetry(3, 500));
}

test "shouldRetry respects disabled retry categories" {
    const no_rate_limit = RetryPolicy{ .retry_on_rate_limit = false };
    try std.testing.expect(!no_rate_limit.shouldRetry(0, 429));
    try std.testing.expect(no_rate_limit.shouldRetry(0, 500));

    const no_server_error = RetryPolicy{ .retry_on_server_error = false };
    try std.testing.expect(!no_server_error.shouldRetry(0, 500));
    try std.testing.expect(no_server_error.shouldRetry(0, 429));

    const no_timeout = RetryPolicy{ .retry_on_timeout = false };
    try std.testing.expect(!no_timeout.shouldRetry(0, 408));
    try std.testing.expect(no_timeout.shouldRetry(0, 429));
}

test "delayMs implements exponential backoff" {
    const policy = RetryPolicy{ .jitter = false };

    // attempt 0: 1000 * 2^0 = 1000
    try std.testing.expectEqual(@as(u64, 1000), policy.delayMs(0, null));
    // attempt 1: 1000 * 2^1 = 2000
    try std.testing.expectEqual(@as(u64, 2000), policy.delayMs(1, null));
    // attempt 2: 1000 * 2^2 = 4000
    try std.testing.expectEqual(@as(u64, 4000), policy.delayMs(2, null));
    // attempt 3: 1000 * 2^3 = 8000
    try std.testing.expectEqual(@as(u64, 8000), policy.delayMs(3, null));
}

test "delayMs respects max_delay" {
    const policy = RetryPolicy{
        .jitter = false,
        .initial_delay_ms = 10000,
        .max_delay_ms = 15000,
    };

    // attempt 0: 10000 (within max)
    try std.testing.expectEqual(@as(u64, 10000), policy.delayMs(0, null));
    // attempt 1: 20000 → clamped to 15000
    try std.testing.expectEqual(@as(u64, 15000), policy.delayMs(1, null));
    // attempt 2: 40000 → clamped to 15000
    try std.testing.expectEqual(@as(u64, 15000), policy.delayMs(2, null));
}

test "delayMs adds jitter when enabled" {
    const policy = RetryPolicy{ .jitter = true };

    var prng = std.Random.DefaultPrng.init(42);
    var rand = prng.random();

    // With jitter, delay should be between 50% and 100% of base
    const delay = policy.delayMs(0, &rand);
    try std.testing.expect(delay >= 500); // 50% of 1000
    try std.testing.expect(delay <= 1000); // 100% of 1000
}

test "preset policies" {
    // Default
    try std.testing.expectEqual(@as(u32, 2), RetryPolicy.default_policy.max_retries);
    try std.testing.expectEqual(@as(u64, 1000), RetryPolicy.default_policy.initial_delay_ms);

    // Aggressive
    try std.testing.expectEqual(@as(u32, 5), RetryPolicy.aggressive.max_retries);
    try std.testing.expectEqual(@as(u64, 2000), RetryPolicy.aggressive.initial_delay_ms);

    // None
    try std.testing.expectEqual(@as(u32, 0), RetryPolicy.none.max_retries);
    try std.testing.expect(!RetryPolicy.none.shouldRetry(0, 500));
}
