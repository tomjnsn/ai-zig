const std = @import("std");
const lm = @import("../../provider/src/language-model/v3/index.zig");

/// Map Groq finish reason to language model finish reason
pub fn mapGroqFinishReason(
    finish_reason: ?[]const u8,
) lm.LanguageModelV3FinishReason {
    if (finish_reason == null) return .unknown;

    const reason = finish_reason.?;

    if (std.mem.eql(u8, reason, "stop")) {
        return .stop;
    } else if (std.mem.eql(u8, reason, "length")) {
        return .length;
    } else if (std.mem.eql(u8, reason, "content_filter")) {
        return .content_filter;
    } else if (std.mem.eql(u8, reason, "function_call") or std.mem.eql(u8, reason, "tool_calls")) {
        return .tool_calls;
    }

    return .unknown;
}

test "mapGroqFinishReason stop" {
    const result = mapGroqFinishReason("stop");
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.stop, result);
}

test "mapGroqFinishReason length" {
    const result = mapGroqFinishReason("length");
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.length, result);
}

test "mapGroqFinishReason content_filter" {
    const result = mapGroqFinishReason("content_filter");
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.content_filter, result);
}

test "mapGroqFinishReason tool_calls" {
    const result = mapGroqFinishReason("tool_calls");
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.tool_calls, result);
}

test "mapGroqFinishReason null" {
    const result = mapGroqFinishReason(null);
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.unknown, result);
}

test "mapGroqFinishReason function_call" {
    const result = mapGroqFinishReason("function_call");
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.tool_calls, result);
}

test "mapGroqFinishReason unknown reason" {
    const result = mapGroqFinishReason("unknown_reason");
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.unknown, result);
}

test "mapGroqFinishReason empty string" {
    const result = mapGroqFinishReason("");
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.unknown, result);
}

test "mapGroqFinishReason case sensitivity" {
    // Should be case sensitive
    const result_upper = mapGroqFinishReason("STOP");
    const result_mixed = mapGroqFinishReason("Stop");

    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.unknown, result_upper);
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.unknown, result_mixed);
}

test "mapGroqFinishReason with whitespace" {
    const result = mapGroqFinishReason(" stop ");
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.unknown, result);
}

test "mapGroqFinishReason all valid reasons" {
    // Test all valid finish reasons
    const stop = mapGroqFinishReason("stop");
    const length = mapGroqFinishReason("length");
    const content_filter = mapGroqFinishReason("content_filter");
    const tool_calls = mapGroqFinishReason("tool_calls");
    const function_call = mapGroqFinishReason("function_call");

    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.stop, stop);
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.length, length);
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.content_filter, content_filter);
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.tool_calls, tool_calls);
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.tool_calls, function_call);
}

test "mapGroqFinishReason multiple invalid reasons" {
    const invalid_reasons = [_][]const u8{
        "error",
        "timeout",
        "cancelled",
        "rejected",
        "invalid",
        "123",
        "tool_call", // Note: singular, should be plural
        "content-filter", // Note: hyphen instead of underscore
    };

    for (invalid_reasons) |reason| {
        const result = mapGroqFinishReason(reason);
        try std.testing.expectEqual(lm.LanguageModelV3FinishReason.unknown, result);
    }
}
