const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;
const api = @import("openai-chat-api.zig");

/// Options for converting messages
pub const ConvertOptions = struct {
    /// The prompt to convert
    prompt: lm.LanguageModelV3Prompt,

    /// System message mode
    system_message_mode: SystemMessageMode = .system,

    pub const SystemMessageMode = enum {
        system,
        developer,
        remove,
    };
};

/// Result of converting messages
pub const ConvertResult = struct {
    /// The converted messages
    messages: []api.OpenAIChatRequest.RequestMessage,

    /// Any warnings generated during conversion
    warnings: []shared.SharedV3Warning,
};

/// Convert language model prompt to OpenAI chat messages
pub fn convertToOpenAIChatMessages(
    allocator: std.mem.Allocator,
    options: ConvertOptions,
) !ConvertResult {
    var messages = std.array_list.Managed(api.OpenAIChatRequest.RequestMessage).init(allocator);
    var warnings = std.array_list.Managed(shared.SharedV3Warning).init(allocator);

    for (options.prompt) |msg| {
        const converted = try convertMessage(allocator, msg, options.system_message_mode, &warnings);
        if (converted) |m| {
            try messages.append(m);
        }
    }

    return .{
        .messages = try messages.toOwnedSlice(),
        .warnings = try warnings.toOwnedSlice(),
    };
}

fn convertMessage(
    allocator: std.mem.Allocator,
    message: lm.LanguageModelV3Message,
    system_mode: ConvertOptions.SystemMessageMode,
    warnings: *std.array_list.Managed(shared.SharedV3Warning),
) !?api.OpenAIChatRequest.RequestMessage {
    _ = warnings;

    switch (message.role) {
        .system => {
            // Handle system message based on mode
            switch (system_mode) {
                .remove => return null,
                .system => return .{
                    .role = "system",
                    .content = .{ .text = message.content.system },
                },
                .developer => return .{
                    .role = "developer",
                    .content = .{ .text = message.content.system },
                },
            }
        },
        .user => {
            const parts = message.content.user;
            if (parts.len == 1) {
                // Single text part can be sent as simple string
                switch (parts[0]) {
                    .text => |t| return .{
                        .role = "user",
                        .content = .{ .text = t.text },
                    },
                    .file => {
                        // File parts need multipart content
                        var content_parts = try allocator.alloc(api.OpenAIChatRequest.ContentPart, parts.len);
                        for (parts, 0..) |part, i| {
                            content_parts[i] = try convertUserPart(allocator, part);
                        }
                        return .{
                            .role = "user",
                            .content = .{ .parts = content_parts },
                        };
                    },
                }
            } else {
                // Multiple parts need array content
                var content_parts = try allocator.alloc(api.OpenAIChatRequest.ContentPart, parts.len);
                for (parts, 0..) |part, i| {
                    content_parts[i] = try convertUserPart(allocator, part);
                }
                return .{
                    .role = "user",
                    .content = .{ .parts = content_parts },
                };
            }
        },
        .assistant => {
            const parts = message.content.assistant;
            var text_content: ?[]const u8 = null;
            var tool_calls = std.array_list.Managed(api.OpenAIChatResponse.ToolCall).init(allocator);

            for (parts) |part| {
                switch (part) {
                    .text => |t| {
                        // Accumulate text content
                        if (text_content) |existing| {
                            text_content = try std.fmt.allocPrint(allocator, "{s}{s}", .{ existing, t.text });
                        } else {
                            text_content = t.text;
                        }
                    },
                    .tool_call => |tc| {
                        // Stringify the JsonValue input
                        const input_str = try tc.input.stringify(allocator);
                        try tool_calls.append(.{
                            .id = tc.tool_call_id,
                            .type = "function",
                            .function = .{
                                .name = tc.tool_name,
                                .arguments = input_str,
                            },
                        });
                    },
                    else => {}, // Skip other parts for now
                }
            }

            return .{
                .role = "assistant",
                .content = if (text_content) |t| .{ .text = t } else null,
                .tool_calls = if (tool_calls.items.len > 0) try tool_calls.toOwnedSlice() else null,
            };
        },
        .tool => {
            const parts = message.content.tool;
            if (parts.len > 0) {
                const part = parts[0];
                const output_text = switch (part.output) {
                    .text => |t| t.value,
                    .json => |j| try j.value.stringify(allocator),
                    .error_text => |e| e.value,
                    .error_json => |e| try e.value.stringify(allocator),
                    .execution_denied => |d| d.reason orelse "Execution denied",
                    .content => "Content output not yet supported",
                };

                return .{
                    .role = "tool",
                    .content = .{ .text = output_text },
                    .tool_call_id = part.tool_call_id,
                };
            }
            return null;
        },
    }
}

fn convertUserPart(allocator: std.mem.Allocator, part: lm.language_model_v3_prompt.UserPart) !api.OpenAIChatRequest.ContentPart {
    _ = allocator;

    switch (part) {
        .text => |t| {
            return .{
                .text = .{
                    .text = t.text,
                },
            };
        },
        .file => |f| {
            // Convert file to image_url if it's an image
            const data_url = switch (f.data) {
                .url => |u| u,
                .base64 => |b64| b64, // Would need to prepend data URI
                .binary => "binary data not directly supported",
            };

            return .{
                .image_url = .{
                    .image_url = .{
                        .url = data_url,
                    },
                },
            };
        },
    }
}

/// Free the converted result
pub fn freeConvertResult(allocator: std.mem.Allocator, result: *ConvertResult) void {
    allocator.free(result.messages);
    allocator.free(result.warnings);
}

test "convertToOpenAIChatMessages system message" {
    const allocator = std.testing.allocator;

    var messages: [1]lm.LanguageModelV3Message = .{
        .{
            .role = .system,
            .content = .{ .system = "You are helpful." },
        },
    };

    const result = try convertToOpenAIChatMessages(allocator, .{
        .prompt = &messages,
        .system_message_mode = .system,
    });
    defer allocator.free(result.messages);
    defer allocator.free(result.warnings);

    try std.testing.expectEqual(@as(usize, 1), result.messages.len);
    try std.testing.expectEqualStrings("system", result.messages[0].role);
}

test "convertToOpenAIChatMessages remove system" {
    const allocator = std.testing.allocator;

    var messages: [1]lm.LanguageModelV3Message = .{
        .{
            .role = .system,
            .content = .{ .system = "You are helpful." },
        },
    };

    const result = try convertToOpenAIChatMessages(allocator, .{
        .prompt = &messages,
        .system_message_mode = .remove,
    });
    defer allocator.free(result.messages);
    defer allocator.free(result.warnings);

    try std.testing.expectEqual(@as(usize, 0), result.messages.len);
}
