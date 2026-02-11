const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;
const api = @import("anthropic-messages-api.zig");

/// Options for converting messages
pub const ConvertOptions = struct {
    /// The prompt to convert
    prompt: lm.LanguageModelV3Prompt,

    /// Whether to send reasoning content
    send_reasoning: bool = true,
};

/// Result of converting messages
pub const ConvertResult = struct {
    /// System content
    system: ?[]api.AnthropicMessagesRequest.SystemContent,

    /// The converted messages
    messages: []api.AnthropicMessagesRequest.RequestMessage,

    /// Any warnings generated during conversion
    warnings: []shared.SharedV3Warning,

    /// Beta features used
    betas: std.StringHashMap(void),
};

/// Convert language model prompt to Anthropic messages format
pub fn convertToAnthropicMessagesPrompt(
    allocator: std.mem.Allocator,
    options: ConvertOptions,
) !ConvertResult {
    var messages = std.ArrayList(api.AnthropicMessagesRequest.RequestMessage).empty;
    var warnings = std.ArrayList(shared.SharedV3Warning).empty;
    var system_content: ?[]api.AnthropicMessagesRequest.SystemContent = null;
    var betas = std.StringHashMap(void).init(allocator);

    for (options.prompt) |msg| {
        switch (msg.role) {
            .system => {
                // System messages become separate system content
                var sys = try allocator.alloc(api.AnthropicMessagesRequest.SystemContent, 1);
                sys[0] = .{
                    .type = "text",
                    .text = msg.content.system,
                };
                system_content = sys;
            },
            .user => {
                // Convert user message
                var content_parts = std.ArrayList(api.AnthropicMessagesRequest.MessageContent).empty;

                for (msg.content.user) |part| {
                    switch (part) {
                        .text => |t| {
                            try content_parts.append(allocator, .{
                                .text = .{
                                    .type = "text",
                                    .text = t.text,
                                },
                            });
                        },
                        .file => |f| {
                            // Convert file to image if applicable
                            if (std.mem.startsWith(u8, f.media_type, "image/")) {
                                const data = switch (f.data) {
                                    .base64 => |b64| b64,
                                    .url => |url| url, // Would need to download
                                    .binary => "", // Would need to encode
                                };

                                try content_parts.append(allocator, .{
                                    .image = .{
                                        .type = "image",
                                        .source = .{
                                            .type = "base64",
                                            .media_type = f.media_type,
                                            .data = data,
                                        },
                                    },
                                });

                                // Add beta for PDF support
                                if (std.mem.eql(u8, f.media_type, "application/pdf")) {
                                    try betas.put("pdfs-2024-09-25", {});
                                }
                            }
                        },
                    }
                }

                try messages.append(allocator, .{
                    .role = "user",
                    .content = try content_parts.toOwnedSlice(allocator),
                });
            },
            .assistant => {
                // Convert assistant message
                var content_parts = std.ArrayList(api.AnthropicMessagesRequest.MessageContent).empty;

                for (msg.content.assistant) |part| {
                    switch (part) {
                        .text => |t| {
                            try content_parts.append(allocator, .{
                                .text = .{
                                    .type = "text",
                                    .text = t.text,
                                },
                            });
                        },
                        .tool_call => |tc| {
                            try content_parts.append(allocator, .{
                                .tool_use = .{
                                    .type = "tool_use",
                                    .id = tc.tool_call_id,
                                    .name = tc.tool_name,
                                    .input = tc.input,
                                },
                            });
                        },
                        .reasoning => |r| {
                            if (options.send_reasoning) {
                                // Reasoning is sent as text with special handling
                                try content_parts.append(allocator, .{
                                    .text = .{
                                        .type = "text",
                                        .text = r.text,
                                    },
                                });
                            }
                        },
                        else => {},
                    }
                }

                try messages.append(allocator, .{
                    .role = "assistant",
                    .content = try content_parts.toOwnedSlice(allocator),
                });
            },
            .tool => {
                // Convert tool result message
                var content_parts = std.ArrayList(api.AnthropicMessagesRequest.MessageContent).empty;

                for (msg.content.tool) |part| {
                    const output_text = switch (part.output) {
                        .text => |t| t.value,
                        .json => |j| try j.value.stringify(allocator),
                        .error_text => |e| e.value,
                        .error_json => |e| try e.value.stringify(allocator),
                        .execution_denied => |d| d.reason orelse "Execution denied",
                        .content => "Content output not yet supported",
                    };

                    try content_parts.append(allocator, .{
                        .tool_result = .{
                            .type = "tool_result",
                            .tool_use_id = part.tool_call_id,
                            .content = output_text,
                            .is_error = switch (part.output) {
                                .error_text, .error_json, .execution_denied => true,
                                else => null,
                            },
                        },
                    });
                }

                try messages.append(allocator, .{
                    .role = "user",
                    .content = try content_parts.toOwnedSlice(allocator),
                });
            },
        }
    }

    return .{
        .system = system_content,
        .messages = try messages.toOwnedSlice(allocator),
        .warnings = try warnings.toOwnedSlice(allocator),
        .betas = betas,
    };
}

/// Free the converted result
pub fn freeConvertResult(allocator: std.mem.Allocator, result: *ConvertResult) void {
    if (result.system) |sys| {
        allocator.free(sys);
    }
    for (result.messages) |msg| {
        allocator.free(msg.content);
    }
    allocator.free(result.messages);
    allocator.free(result.warnings);
    result.betas.deinit();
}

test "convertToAnthropicMessagesPrompt system message" {
    const allocator = std.testing.allocator;

    var messages: [1]lm.LanguageModelV3Message = .{
        .{
            .role = .system,
            .content = .{ .system = "You are helpful." },
        },
    };

    var result = try convertToAnthropicMessagesPrompt(allocator, .{
        .prompt = &messages,
    });
    defer freeConvertResult(allocator, &result);

    try std.testing.expect(result.system != null);
    try std.testing.expectEqual(@as(usize, 1), result.system.?.len);
    try std.testing.expectEqualStrings("You are helpful.", result.system.?[0].text);
    try std.testing.expectEqual(@as(usize, 0), result.messages.len);
}
