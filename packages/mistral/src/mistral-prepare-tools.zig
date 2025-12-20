const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;
const options_mod = @import("mistral-options.zig");

/// Prepared tools result
pub const PreparedTools = struct {
    /// Mistral-formatted tools
    tools: ?[]const MistralTool,

    /// Tool choice
    tool_choice: ?options_mod.MistralToolChoice,

    /// Warnings generated during preparation
    warnings: []const shared.SharedV3Warning,
};

/// Mistral tool format
pub const MistralTool = struct {
    type: []const u8 = "function",
    function: MistralFunction,
};

/// Mistral function definition
pub const MistralFunction = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    parameters: std.json.Value,
    strict: ?bool = null,
};

/// Prepare tools for Mistral API
pub fn prepareTools(
    allocator: std.mem.Allocator,
    tools: ?[]const lm.LanguageModelV3Tool,
    tool_choice: ?lm.LanguageModelV3ToolChoice,
) !PreparedTools {
    var warnings = std.array_list.Managed(shared.SharedV3Warning).init(allocator);

    // Handle empty or null tools
    if (tools == null or tools.?.len == 0) {
        return .{
            .tools = null,
            .tool_choice = null,
            .warnings = &[_]shared.SharedV3Warning{},
        };
    }

    const tool_list = tools.?;
    var mistral_tools = try allocator.alloc(MistralTool, tool_list.len);
    var tool_count: usize = 0;

    for (tool_list) |tool| {
        switch (tool) {
            .function => |func| {
                mistral_tools[tool_count] = .{
                    .type = "function",
                    .function = .{
                        .name = func.name,
                        .description = func.description,
                        .parameters = func.input_schema,
                        .strict = func.strict,
                    },
                };
                tool_count += 1;
            },
            .provider => |prov| {
                try warnings.append(.{
                    .type = .unsupported,
                    .feature = try std.fmt.allocPrint(
                        allocator,
                        "provider-defined tool {s}",
                        .{prov.id},
                    ),
                });
            },
        }
    }

    // Resize to actual count
    mistral_tools = try allocator.realloc(mistral_tools, tool_count);

    // Convert tool choice
    var mistral_tool_choice: ?options_mod.MistralToolChoice = null;
    if (tool_choice) |choice| {
        mistral_tool_choice = switch (choice.type) {
            .auto => .auto,
            .none => .none,
            .required => .any,
            .tool => blk: {
                // Filter tools to only the specified one
                const tool_name = choice.tool_name orelse break :blk .any;
                var filtered = std.array_list.Managed(MistralTool).init(allocator);
                for (mistral_tools) |t| {
                    if (std.mem.eql(u8, t.function.name, tool_name)) {
                        try filtered.append(t);
                    }
                }
                mistral_tools = try filtered.toOwnedSlice();
                break :blk .any;
            },
        };
    }

    return .{
        .tools = if (tool_count > 0) mistral_tools else null,
        .tool_choice = mistral_tool_choice,
        .warnings = try warnings.toOwnedSlice(),
    };
}

/// Serialize tools to JSON
pub fn serializeToolsToJson(
    allocator: std.mem.Allocator,
    tools: []const MistralTool,
) !std.json.Value {
    var array = std.json.Array.init(allocator);

    for (tools) |tool| {
        var obj = std.json.ObjectMap.init(allocator);
        try obj.put("type", .{ .string = tool.type });

        var func_obj = std.json.ObjectMap.init(allocator);
        try func_obj.put("name", .{ .string = tool.function.name });
        if (tool.function.description) |desc| {
            try func_obj.put("description", .{ .string = desc });
        }
        try func_obj.put("parameters", tool.function.parameters);
        if (tool.function.strict) |strict| {
            try func_obj.put("strict", .{ .bool = strict });
        }

        try obj.put("function", .{ .object = func_obj });
        try array.append(.{ .object = obj });
    }

    return .{ .array = array };
}

test "prepareTools empty" {
    const allocator = std.testing.allocator;
    const result = try prepareTools(allocator, null, null);
    try std.testing.expect(result.tools == null);
    try std.testing.expect(result.tool_choice == null);
}
