const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;
const api = @import("openai-chat-api.zig");

/// Options for preparing tools
pub const PrepareToolsOptions = struct {
    /// The tools from call options
    tools: ?[]const lm.LanguageModelV3CallOptions.Tool = null,

    /// The tool choice from call options
    tool_choice: ?lm.LanguageModelV3ToolChoice = null,
};

/// Result of preparing tools
pub const PrepareToolsResult = struct {
    /// OpenAI format tools
    tools: ?[]api.OpenAIChatRequest.Tool = null,

    /// OpenAI format tool choice
    tool_choice: ?api.OpenAIChatRequest.ToolChoice = null,

    /// Any warnings generated
    tool_warnings: []shared.SharedV3Warning = &[_]shared.SharedV3Warning{},
};

/// Prepare tools for OpenAI chat API
pub fn prepareChatTools(
    allocator: std.mem.Allocator,
    options: PrepareToolsOptions,
) !PrepareToolsResult {
    var warnings = std.ArrayList(shared.SharedV3Warning).empty;

    // Convert tools
    var openai_tools: ?[]api.OpenAIChatRequest.Tool = null;
    if (options.tools) |tools| {
        var tool_list = try allocator.alloc(api.OpenAIChatRequest.Tool, tools.len);
        var valid_count: usize = 0;

        for (tools) |tool| {
            switch (tool) {
                .function => |func| {
                    tool_list[valid_count] = .{
                        .function = .{
                            .name = func.name,
                            .description = func.description,
                            .parameters = func.input_schema,
                            .strict = if (func.strict) func.strict else null,
                        },
                    };
                    valid_count += 1;
                },
                .provider => |prov| {
                    // Provider tools are not directly supported in chat API
                    try warnings.append(allocator, .{
                        .other = .{
                            .message = try std.fmt.allocPrint(
                                allocator,
                                "Provider tool '{s}' is not supported in chat API",
                                .{prov.name},
                            ),
                        },
                    });
                },
            }
        }

        if (valid_count > 0) {
            openai_tools = tool_list[0..valid_count];
        } else {
            allocator.free(tool_list);
        }
    }

    // Convert tool choice
    var openai_tool_choice: ?api.OpenAIChatRequest.ToolChoice = null;
    if (options.tool_choice) |choice| {
        openai_tool_choice = switch (choice) {
            .auto => .{ .auto = "auto" },
            .none => .{ .none = "none" },
            .required => .{ .required = "required" },
            .tool => |t| .{
                .function = .{
                    .function = .{
                        .name = t.tool_name,
                    },
                },
            },
        };
    }

    return .{
        .tools = openai_tools,
        .tool_choice = openai_tool_choice,
        .tool_warnings = try warnings.toOwnedSlice(allocator),
    };
}

/// Free the prepared tools result
pub fn freePrepareToolsResult(allocator: std.mem.Allocator, result: *PrepareToolsResult) void {
    if (result.tools) |tools| {
        allocator.free(tools);
    }
    allocator.free(result.tool_warnings);
}

test "prepareChatTools with function tools" {
    const allocator = std.testing.allocator;
    const json_value = @import("provider").json_value;

    const schema = json_value.JsonValue{ .object = json_value.JsonObject.init(allocator) };

    const tools = [_]lm.LanguageModelV3CallOptions.Tool{
        .{
            .function = .{
                .name = "search",
                .description = "Search the web",
                .input_schema = schema,
            },
        },
    };

    var result = try prepareChatTools(allocator, .{
        .tools = &tools,
        .tool_choice = .auto,
    });
    defer freePrepareToolsResult(allocator, &result);

    try std.testing.expect(result.tools != null);
    try std.testing.expectEqual(@as(usize, 1), result.tools.?.len);
    try std.testing.expectEqualStrings("search", result.tools.?[0].function.name);
}

test "prepareChatTools with tool choice" {
    const allocator = std.testing.allocator;

    var result = try prepareChatTools(allocator, .{
        .tools = null,
        .tool_choice = lm.LanguageModelV3ToolChoice.toolChoice("specific_tool"),
    });
    defer freePrepareToolsResult(allocator, &result);

    try std.testing.expect(result.tool_choice != null);
    switch (result.tool_choice.?) {
        .function => |f| {
            try std.testing.expectEqualStrings("specific_tool", f.function.name);
        },
        else => unreachable,
    }
}
