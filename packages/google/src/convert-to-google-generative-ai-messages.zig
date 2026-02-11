const std = @import("std");
const lm = @import("provider").language_model;
const prompt_types = @import("google-generative-ai-prompt.zig");
const UserPart = @import("provider").language_model.language_model_v3_prompt.UserPart;

/// Options for converting messages
pub const ConvertOptions = struct {
    /// Whether the model is a Gemma model (affects system message handling)
    is_gemma_model: bool = false,
};

/// Result of converting messages
pub const ConvertResult = struct {
    /// System instruction (separate from messages)
    system_instruction: ?prompt_types.GoogleGenerativeAIPrompt.SystemInstruction,

    /// Converted contents
    contents: []prompt_types.GoogleGenerativeAIContent,
};

/// Convert language model prompt to Google Generative AI messages format
pub fn convertToGoogleGenerativeAIMessages(
    allocator: std.mem.Allocator,
    prompt: lm.LanguageModelV3Prompt,
    options: ConvertOptions,
) !ConvertResult {
    var system_instruction_parts = std.ArrayList(prompt_types.GoogleGenerativeAIPrompt.SystemInstruction.TextPart).empty;
    var contents = std.ArrayList(prompt_types.GoogleGenerativeAIContent).empty;
    var system_messages_allowed = true;

    for (prompt) |msg| {
        switch (msg.role) {
            .system => {
                if (!system_messages_allowed) {
                    return error.SystemMessageNotAllowed;
                }
                try system_instruction_parts.append(allocator, .{ .text = msg.content.system });
            },
            .user => {
                system_messages_allowed = false;

                var parts = std.ArrayList(prompt_types.GoogleGenerativeAIContentPart).empty;

                for (msg.content.user) |part| {
                    switch (part) {
                        .text => |t| {
                            try parts.append(allocator, .{
                                .text = .{ .text = t.text },
                            });
                        },
                        .file => |f| {
                            // Determine media type
                            const media_type = if (std.mem.eql(u8, f.media_type, "image/*"))
                                "image/jpeg"
                            else
                                f.media_type;

                            // Check if it's a URL or base64 data
                            switch (f.data) {
                                .url => |url| {
                                    try parts.append(allocator, .{
                                        .file_data = .{
                                            .mime_type = media_type,
                                            .file_uri = url,
                                        },
                                    });
                                },
                                .base64 => |data| {
                                    try parts.append(allocator, .{
                                        .inline_data = .{
                                            .mime_type = media_type,
                                            .data = data,
                                        },
                                    });
                                },
                                .binary => {
                                    // Would need to base64 encode
                                    return error.BinaryDataNotSupported;
                                },
                            }
                        },
                    }
                }

                try contents.append(allocator, .{
                    .role = "user",
                    .parts = try parts.toOwnedSlice(allocator),
                });
            },
            .assistant => {
                system_messages_allowed = false;

                var parts = std.ArrayList(prompt_types.GoogleGenerativeAIContentPart).empty;

                for (msg.content.assistant) |part| {
                    switch (part) {
                        .text => |t| {
                            if (t.text.len > 0) {
                                try parts.append(allocator, .{
                                    .text = .{
                                        .text = t.text,
                                        .thought = false,
                                    },
                                });
                            }
                        },
                        .reasoning => |r| {
                            if (r.text.len > 0) {
                                try parts.append(allocator, .{
                                    .text = .{
                                        .text = r.text,
                                        .thought = true,
                                    },
                                });
                            }
                        },
                        .tool_call => |tc| {
                            // Convert JsonValue to std.json.Value
                            const std_json_args = try tc.input.toStdJson(allocator);
                            try parts.append(allocator, .{
                                .function_call = .{
                                    .name = tc.tool_name,
                                    .args = std_json_args,
                                },
                            });
                        },
                        .file => |f| {
                            switch (f.data) {
                                .base64 => |data| {
                                    try parts.append(allocator, .{
                                        .inline_data = .{
                                            .mime_type = f.media_type,
                                            .data = data,
                                        },
                                    });
                                },
                                else => return error.UnsupportedFileData,
                            }
                        },
                        else => {},
                    }
                }

                try contents.append(allocator, .{
                    .role = "model",
                    .parts = try parts.toOwnedSlice(allocator),
                });
            },
            .tool => {
                system_messages_allowed = false;

                var parts = std.ArrayList(prompt_types.GoogleGenerativeAIContentPart).empty;

                for (msg.content.tool) |part| {
                    const output_text = switch (part.output) {
                        .text => |t| t.value,
                        .json => |j| try j.value.stringify(allocator),
                        .error_text => |e| e.value,
                        .error_json => |e| try e.value.stringify(allocator),
                        .execution_denied => |d| d.reason orelse "Tool execution denied.",
                        .content => "Content output not yet supported",
                    };

                    try parts.append(allocator, .{
                        .function_response = .{
                            .name = part.tool_name,
                            .response = .{
                                .name = part.tool_name,
                                .content = output_text,
                            },
                        },
                    });
                }

                try contents.append(allocator, .{
                    .role = "user",
                    .parts = try parts.toOwnedSlice(allocator),
                });
            },
        }
    }

    // For Gemma models, prepend system text to first user message
    if (options.is_gemma_model and system_instruction_parts.items.len > 0 and contents.items.len > 0) {
        if (std.mem.eql(u8, contents.items[0].role, "user") and contents.items[0].parts.len > 0) {
            // Build system text
            var system_text = std.ArrayList(u8).empty;
            for (system_instruction_parts.items, 0..) |part, i| {
                if (i > 0) try system_text.appendSlice(allocator, "\n\n");
                try system_text.appendSlice(allocator, part.text);
            }
            try system_text.appendSlice(allocator, "\n\n");

            // Prepend to first user message
            const first_part = contents.items[0].parts[0];
            switch (first_part) {
                .text => |t| {
                    try system_text.appendSlice(allocator, t.text);
                    // Create new parts array with modified first element
                    var new_parts = try allocator.alloc(prompt_types.GoogleGenerativeAIContentPart, contents.items[0].parts.len);
                    new_parts[0] = .{ .text = .{ .text = try system_text.toOwnedSlice(allocator) } };
                    for (contents.items[0].parts[1..], 1..) |p, j| {
                        new_parts[j] = p;
                    }
                    contents.items[0].parts = new_parts;
                },
                else => {},
            }
        }
    }

    // Build system instruction
    const system_instruction: ?prompt_types.GoogleGenerativeAIPrompt.SystemInstruction =
        if (system_instruction_parts.items.len > 0 and !options.is_gemma_model)
        .{ .parts = try system_instruction_parts.toOwnedSlice(allocator) }
    else
        null;

    return .{
        .system_instruction = system_instruction,
        .contents = try contents.toOwnedSlice(allocator),
    };
}

/// Free the converted result
pub fn freeConvertResult(allocator: std.mem.Allocator, result: *ConvertResult) void {
    if (result.system_instruction) |si| {
        allocator.free(si.parts);
    }
    for (result.contents) |content| {
        allocator.free(content.parts);
    }
    allocator.free(result.contents);
}

test "convertToGoogleGenerativeAIMessages system message" {
    const allocator = std.testing.allocator;

    var messages: [1]lm.LanguageModelV3Message = .{
        .{
            .role = .system,
            .content = .{ .system = "You are helpful." },
        },
    };

    var result = try convertToGoogleGenerativeAIMessages(allocator, &messages, .{});
    defer freeConvertResult(allocator, &result);

    try std.testing.expect(result.system_instruction != null);
    try std.testing.expectEqual(@as(usize, 1), result.system_instruction.?.parts.len);
    try std.testing.expectEqualStrings("You are helpful.", result.system_instruction.?.parts[0].text);
    try std.testing.expectEqual(@as(usize, 0), result.contents.len);
}

test "convertToGoogleGenerativeAIMessages user message" {
    const allocator = std.testing.allocator;

    var user_parts: [1]UserPart = .{
        .{ .text = .{ .text = "Hello!" } },
    };

    var messages: [1]lm.LanguageModelV3Message = .{
        .{
            .role = .user,
            .content = .{ .user = &user_parts },
        },
    };

    var result = try convertToGoogleGenerativeAIMessages(allocator, &messages, .{});
    defer freeConvertResult(allocator, &result);

    try std.testing.expect(result.system_instruction == null);
    try std.testing.expectEqual(@as(usize, 1), result.contents.len);
    try std.testing.expectEqualStrings("user", result.contents[0].role);
}
