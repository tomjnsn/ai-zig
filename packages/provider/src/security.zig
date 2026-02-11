const std = @import("std");

/// API key prefixes that indicate sensitive tokens
const sensitive_prefixes = [_][]const u8{
    "sk-proj-",
    "sk-",
    "anthropic-sk-ant-",
    "AIza",
    "AKIA",
    "msk-",
    "co-",
    "gsk_",
    "xai-",
};

/// Redacts sensitive API keys and tokens from text.
/// Replaces patterns like "Bearer sk-..." with "Bearer [REDACTED]"
/// This is used to prevent API keys from appearing in error messages and logs.
/// Caller owns the returned slice if it differs from input.
pub fn redactApiKey(text: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    if (text.len == 0) return text;
    if (!containsApiKey(text)) return text;

    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < text.len) {
        if (findKeyStart(text, i)) |key_start| {
            // Append everything before the key
            try result.appendSlice(allocator, text[i..key_start]);
            // Append redaction marker
            try result.appendSlice(allocator, "[REDACTED]");
            // Skip past the key (consume until whitespace, comma, quote, or end)
            var end = key_start;
            while (end < text.len and !isKeyTerminator(text[end])) {
                end += 1;
            }
            i = end;
        } else {
            // No more keys, append rest
            try result.appendSlice(allocator, text[i..]);
            break;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Checks if a string contains what appears to be an API key
pub fn containsApiKey(text: []const u8) bool {
    for (sensitive_prefixes) |prefix| {
        if (std.mem.indexOf(u8, text, prefix) != null) return true;
    }
    return false;
}

/// Find the start position of the next API key in text starting from `from`.
fn findKeyStart(text: []const u8, from: usize) ?usize {
    var pos = from;
    while (pos < text.len) {
        // Check each prefix at this position
        for (sensitive_prefixes) |prefix| {
            if (pos + prefix.len <= text.len and
                std.mem.eql(u8, text[pos .. pos + prefix.len], prefix))
            {
                return pos;
            }
        }
        pos += 1;
    }
    return null;
}

/// Returns true if the character terminates an API key token.
fn isKeyTerminator(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or
        c == ',' or c == '"' or c == '\'' or c == ';' or c == ')' or c == ']' or c == '}';
}

// ============================================================================
// Tests
// ============================================================================

test "redactApiKey masks Bearer tokens with sk- prefix" {
    const allocator = std.testing.allocator;
    const input = "Authorization: Bearer sk-abc123xyz789";
    const result = try redactApiKey(input, allocator);
    defer if (result.ptr != input.ptr) allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "sk-abc123xyz789") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[REDACTED]") != null);
}

test "redactApiKey masks Bearer tokens with anthropic prefix" {
    const allocator = std.testing.allocator;
    const input = "x-api-key: anthropic-sk-ant-12345";
    const result = try redactApiKey(input, allocator);
    defer if (result.ptr != input.ptr) allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "anthropic-sk-ant-12345") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[REDACTED]") != null);
}

test "redactApiKey preserves non-sensitive text" {
    const allocator = std.testing.allocator;
    const input = "This is a normal error message without any keys";
    const result = try redactApiKey(input, allocator);
    defer if (result.ptr != input.ptr) allocator.free(result);

    try std.testing.expectEqualStrings(input, result);
}

test "redactApiKey handles multiple keys in text" {
    const allocator = std.testing.allocator;
    const input = "First: Bearer sk-first123 and second: Bearer sk-second456";
    const result = try redactApiKey(input, allocator);
    defer if (result.ptr != input.ptr) allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "sk-first123") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "sk-second456") == null);
}

test "redactApiKey handles empty string" {
    const allocator = std.testing.allocator;
    const input = "";
    const result = try redactApiKey(input, allocator);

    try std.testing.expectEqualStrings("", result);
}

test "containsApiKey detects sk- prefix" {
    try std.testing.expect(containsApiKey("Bearer sk-abc123"));
    try std.testing.expect(containsApiKey("sk-proj-abc123"));
}

test "containsApiKey detects anthropic prefix" {
    try std.testing.expect(containsApiKey("anthropic-sk-ant-12345"));
}

test "containsApiKey detects additional provider prefixes" {
    try std.testing.expect(containsApiKey("AIzaSyA1234567890abcdef")); // Google
    try std.testing.expect(containsApiKey("AKIAIOSFODNN7EXAMPLE")); // AWS
    try std.testing.expect(containsApiKey("msk-abc123")); // Mistral
    try std.testing.expect(containsApiKey("co-abc123")); // Cohere
    try std.testing.expect(containsApiKey("gsk_abc123")); // Groq
    try std.testing.expect(containsApiKey("xai-abc123")); // xAI
}

test "containsApiKey returns false for normal text" {
    try std.testing.expect(!containsApiKey("This is normal text"));
    try std.testing.expect(!containsApiKey("error: something went wrong"));
}
