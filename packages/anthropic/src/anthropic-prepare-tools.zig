const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;
const api = @import("anthropic-messages-api.zig");

/// Options for preparing tools
pub const PrepareToolsOptions = struct {
    /// The tools from call options
    tools: ?[]const lm.LanguageModelV3CallOptions.Tool = null,

    /// The tool choice from call options
    tool_choice: ?lm.LanguageModelV3ToolChoice = null,

    /// Whether to disable parallel tool use
    disable_parallel_tool_use: ?bool = null,
};

/// Result of preparing tools
pub const PrepareToolsResult = struct {
    /// Anthropic format tools
    tools: ?[]api.AnthropicMessagesRequest.Tool = null,

    /// Anthropic format tool choice
    tool_choice: ?api.AnthropicMessagesRequest.ToolChoice = null,

    /// Any warnings generated
    tool_warnings: []shared.SharedV3Warning = &[_]shared.SharedV3Warning{},

    /// Beta features required
    betas: std.StringHashMap(void),
};

/// Prepare tools for Anthropic messages API
pub fn prepareTools(
    allocator: std.mem.Allocator,
    options: PrepareToolsOptions,
) !PrepareToolsResult {
    var warnings = std.ArrayList(shared.SharedV3Warning).empty;
    var betas = std.StringHashMap(void).init(allocator);

    // Convert tools
    var anthropic_tools: ?[]api.AnthropicMessagesRequest.Tool = null;
    if (options.tools) |tools| {
        var tool_list = try allocator.alloc(api.AnthropicMessagesRequest.Tool, tools.len);
        var valid_count: usize = 0;

        for (tools) |tool| {
            switch (tool) {
                .function => |func| {
                    tool_list[valid_count] = .{
                        .name = func.name,
                        .description = func.description,
                        .input_schema = func.input_schema,
                    };
                    valid_count += 1;
                },
                .provider => |prov| {
                    // Handle Anthropic provider tools
                    if (std.mem.startsWith(u8, prov.name, "anthropic.")) {
                        // Computer use tool
                        if (std.mem.indexOf(u8, prov.name, "computer") != null) {
                            try betas.put("computer-use-2024-10-22", {});
                        }
                        // Code execution tool
                        if (std.mem.indexOf(u8, prov.name, "code_execution") != null) {
                            try betas.put("code-execution-2025-05-22", {});
                        }
                        // Web search tool
                        if (std.mem.indexOf(u8, prov.name, "web_search") != null) {
                            try betas.put("web-search-2025-03-05", {});
                        }
                        // Text editor tool
                        if (std.mem.indexOf(u8, prov.name, "text_editor") != null) {
                            try betas.put("computer-use-2024-10-22", {});
                        }
                        // Bash tool
                        if (std.mem.indexOf(u8, prov.name, "bash") != null) {
                            try betas.put("computer-use-2024-10-22", {});
                        }
                    } else {
                        try warnings.append(allocator, shared.SharedV3Warning.otherWarning(
                            try std.fmt.allocPrint(
                                allocator,
                                "Provider tool '{s}' is not supported in Anthropic messages API",
                                .{prov.name},
                            )
                        ));
                    }
                },
            }
        }

        if (valid_count > 0) {
            anthropic_tools = tool_list[0..valid_count];
        } else {
            allocator.free(tool_list);
        }
    }

    // Convert tool choice
    var anthropic_tool_choice: ?api.AnthropicMessagesRequest.ToolChoice = null;
    if (options.tool_choice) |choice| {
        anthropic_tool_choice = switch (choice) {
            .auto => .{
                .auto = .{
                    .type = "auto",
                    .disable_parallel_tool_use = options.disable_parallel_tool_use,
                },
            },
            .none => .{
                .none = .{ .type = "none" },
            },
            .required => .{
                .any = .{
                    .type = "any",
                    .disable_parallel_tool_use = options.disable_parallel_tool_use,
                },
            },
            .tool => |t| .{
                .tool = .{
                    .type = "tool",
                    .name = t.tool_name,
                    .disable_parallel_tool_use = options.disable_parallel_tool_use,
                },
            },
        };
    }

    return .{
        .tools = anthropic_tools,
        .tool_choice = anthropic_tool_choice,
        .tool_warnings = try warnings.toOwnedSlice(allocator),
        .betas = betas,
    };
}

/// Free the prepared tools result
pub fn freePrepareToolsResult(allocator: std.mem.Allocator, result: *PrepareToolsResult) void {
    if (result.tools) |tools| {
        allocator.free(tools);
    }
    allocator.free(result.tool_warnings);
    result.betas.deinit();
}

test "prepareTools with function tools" {
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

    var result = try prepareTools(allocator, .{
        .tools = &tools,
        .tool_choice = .auto,
    });
    defer freePrepareToolsResult(allocator, &result);

    try std.testing.expect(result.tools != null);
    try std.testing.expectEqual(@as(usize, 1), result.tools.?.len);
    try std.testing.expectEqualStrings("search", result.tools.?[0].name);
}

test "prepareTools with tool choice" {
    const allocator = std.testing.allocator;

    var result = try prepareTools(allocator, .{
        .tools = null,
        .tool_choice = lm.LanguageModelV3ToolChoice.toolChoice("specific_tool"),
    });
    defer freePrepareToolsResult(allocator, &result);

    try std.testing.expect(result.tool_choice != null);
    switch (result.tool_choice.?) {
        .tool => |t| {
            try std.testing.expectEqualStrings("specific_tool", t.name);
        },
        else => unreachable,
    }
}
