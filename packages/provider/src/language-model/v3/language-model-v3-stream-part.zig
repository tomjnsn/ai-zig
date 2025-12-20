const std = @import("std");
const shared = @import("../../shared/v3/index.zig");
const json_value = @import("../../json-value/index.zig");
const LanguageModelV3File = @import("language-model-v3-file.zig").LanguageModelV3File;
const LanguageModelV3Source = @import("language-model-v3-source.zig").LanguageModelV3Source;
const LanguageModelV3ToolCall = @import("language-model-v3-tool-call.zig").LanguageModelV3ToolCall;
const LanguageModelV3ToolResult = @import("language-model-v3-tool-result.zig").LanguageModelV3ToolResult;
const LanguageModelV3Usage = @import("language-model-v3-usage.zig").LanguageModelV3Usage;
const LanguageModelV3FinishReason = @import("language-model-v3-finish-reason.zig").LanguageModelV3FinishReason;
const LanguageModelV3ResponseMetadata = @import("language-model-v3-response-metadata.zig").LanguageModelV3ResponseMetadata;

/// Stream parts emitted during language model streaming.
pub const LanguageModelV3StreamPart = union(enum) {
    // Text blocks
    text_start: TextStart,
    text_delta: TextDelta,
    text_end: TextEnd,

    // Reasoning blocks
    reasoning_start: ReasoningStart,
    reasoning_delta: ReasoningDelta,
    reasoning_end: ReasoningEnd,

    // Tool calls
    tool_input_start: ToolInputStart,
    tool_input_delta: ToolInputDelta,
    tool_input_end: ToolInputEnd,
    tool_call: LanguageModelV3ToolCall,
    tool_result: LanguageModelV3ToolResult,

    // Files and sources
    file: LanguageModelV3File,
    source: LanguageModelV3Source,

    // Stream lifecycle
    stream_start: StreamStart,
    response_metadata: ResponseMetadata,
    finish: Finish,

    // Raw chunks
    raw: Raw,

    // Errors
    @"error": Error,

    pub const TextStart = struct {
        id: []const u8,
        provider_metadata: ?shared.SharedV3ProviderMetadata = null,
    };

    pub const TextDelta = struct {
        id: []const u8,
        delta: []const u8,
        provider_metadata: ?shared.SharedV3ProviderMetadata = null,
    };

    pub const TextEnd = struct {
        id: []const u8,
        provider_metadata: ?shared.SharedV3ProviderMetadata = null,
    };

    pub const ReasoningStart = struct {
        id: []const u8,
        provider_metadata: ?shared.SharedV3ProviderMetadata = null,
    };

    pub const ReasoningDelta = struct {
        id: []const u8,
        delta: []const u8,
        provider_metadata: ?shared.SharedV3ProviderMetadata = null,
    };

    pub const ReasoningEnd = struct {
        id: []const u8,
        provider_metadata: ?shared.SharedV3ProviderMetadata = null,
    };

    pub const ToolInputStart = struct {
        id: []const u8,
        tool_name: []const u8,
        provider_metadata: ?shared.SharedV3ProviderMetadata = null,
        provider_executed: bool = false,
        dynamic: bool = false,
        title: ?[]const u8 = null,
    };

    pub const ToolInputDelta = struct {
        id: []const u8,
        delta: []const u8,
        provider_metadata: ?shared.SharedV3ProviderMetadata = null,
    };

    pub const ToolInputEnd = struct {
        id: []const u8,
        provider_metadata: ?shared.SharedV3ProviderMetadata = null,
    };

    pub const StreamStart = struct {
        warnings: []const shared.SharedV3Warning,
    };

    pub const ResponseMetadata = struct {
        id: ?[]const u8 = null,
        timestamp: ?i64 = null,
        model_id: ?[]const u8 = null,
    };

    pub const Finish = struct {
        usage: LanguageModelV3Usage,
        finish_reason: LanguageModelV3FinishReason,
        provider_metadata: ?shared.SharedV3ProviderMetadata = null,
    };

    pub const Raw = struct {
        raw_value: json_value.JsonValue,
    };

    pub const Error = struct {
        err: anyerror,
        message: ?[]const u8 = null,
    };

    const Self = @This();

    /// Get the type string for this stream part
    pub fn getType(self: Self) []const u8 {
        return switch (self) {
            .text_start => "text-start",
            .text_delta => "text-delta",
            .text_end => "text-end",
            .reasoning_start => "reasoning-start",
            .reasoning_delta => "reasoning-delta",
            .reasoning_end => "reasoning-end",
            .tool_input_start => "tool-input-start",
            .tool_input_delta => "tool-input-delta",
            .tool_input_end => "tool-input-end",
            .tool_call => "tool-call",
            .tool_result => "tool-result",
            .file => "file",
            .source => "source",
            .stream_start => "stream-start",
            .response_metadata => "response-metadata",
            .finish => "finish",
            .raw => "raw",
            .@"error" => "error",
        };
    }

    /// Check if this is a text-related part
    pub fn isTextPart(self: Self) bool {
        return switch (self) {
            .text_start, .text_delta, .text_end => true,
            else => false,
        };
    }

    /// Check if this is a tool-related part
    pub fn isToolPart(self: Self) bool {
        return switch (self) {
            .tool_input_start, .tool_input_delta, .tool_input_end, .tool_call, .tool_result => true,
            else => false,
        };
    }

    /// Check if this is a lifecycle event
    pub fn isLifecycleEvent(self: Self) bool {
        return switch (self) {
            .stream_start, .finish, .@"error" => true,
            else => false,
        };
    }

    /// Get the text delta if this is a text delta part
    pub fn getTextDelta(self: Self) ?[]const u8 {
        return switch (self) {
            .text_delta => |td| td.delta,
            else => null,
        };
    }

    /// Get the reasoning delta if this is a reasoning delta part
    pub fn getReasoningDelta(self: Self) ?[]const u8 {
        return switch (self) {
            .reasoning_delta => |rd| rd.delta,
            else => null,
        };
    }
};

// Factory functions for common stream parts

/// Create a text start stream part
pub fn textStart(id: []const u8) LanguageModelV3StreamPart {
    return .{ .text_start = .{ .id = id } };
}

/// Create a text delta stream part
pub fn textDelta(id: []const u8, delta: []const u8) LanguageModelV3StreamPart {
    return .{ .text_delta = .{ .id = id, .delta = delta } };
}

/// Create a text end stream part
pub fn textEnd(id: []const u8) LanguageModelV3StreamPart {
    return .{ .text_end = .{ .id = id } };
}

/// Create a finish stream part
pub fn finish(usage: LanguageModelV3Usage, finish_reason: LanguageModelV3FinishReason) LanguageModelV3StreamPart {
    return .{ .finish = .{ .usage = usage, .finish_reason = finish_reason } };
}

/// Create an error stream part
pub fn streamError(err: anyerror, message: ?[]const u8) LanguageModelV3StreamPart {
    return .{ .@"error" = .{ .err = err, .message = message } };
}

test "LanguageModelV3StreamPart text_delta" {
    const part = textDelta("text-1", "Hello");
    try std.testing.expectEqualStrings("text-delta", part.getType());
    try std.testing.expect(part.isTextPart());
    try std.testing.expectEqualStrings("Hello", part.getTextDelta().?);
}

test "LanguageModelV3StreamPart finish" {
    const usage = LanguageModelV3Usage.initWithTotals(100, 50);
    const part = finish(usage, .stop);
    try std.testing.expectEqualStrings("finish", part.getType());
    try std.testing.expect(part.isLifecycleEvent());
}
