const std = @import("std");

/// Tool parameter schema
pub const ParameterSchema = struct {
    /// JSON Schema for the parameter
    json_schema: std.json.Value,

    /// Parameter name
    name: ?[]const u8 = null,

    /// Parameter description
    description: ?[]const u8 = null,

    /// Whether the parameter is required
    required: bool = true,
};

/// Tool execution context
pub const ToolExecutionContext = struct {
    /// Messages in the conversation
    messages: ?[]const anyopaque = null,

    /// Abort signal for cancellation
    abort_signal: ?*std.atomic.Value(bool) = null,

    /// User-provided context
    user_context: ?*anyopaque = null,
};

/// Tool execution result
pub const ToolExecutionResult = union(enum) {
    /// Successful result
    success: std.json.Value,

    /// Error result
    @"error": ToolError,
};

pub const ToolError = struct {
    message: []const u8,
    code: ?[]const u8 = null,
    cause: ?anyerror = null,
};

/// Tool execution function type
pub const ExecuteFn = *const fn (
    input: std.json.Value,
    context: ToolExecutionContext,
) anyerror!ToolExecutionResult;

/// Callback when tool input becomes available
pub const OnInputAvailableFn = *const fn (
    input: std.json.Value,
    tool_call_id: []const u8,
    context: ToolExecutionContext,
) anyerror!void;

/// Tool approval requirement
pub const ApprovalRequirement = union(enum) {
    /// Always require approval
    always,
    /// Never require approval
    never,
    /// Custom function to determine approval
    custom: *const fn (input: std.json.Value, context: ToolExecutionContext) bool,
};

/// Tool definition
pub const Tool = struct {
    /// Tool name
    name: []const u8,

    /// Tool description
    description: ?[]const u8 = null,

    /// Parameter schema (JSON Schema)
    parameters: std.json.Value,

    /// Execute function
    execute: ?ExecuteFn = null,

    /// Callback when input is available (before execution)
    on_input_available: ?OnInputAvailableFn = null,

    /// Whether this tool requires approval before execution
    requires_approval: ApprovalRequirement = .never,

    /// Maximum execution time in milliseconds
    max_execution_time_ms: ?u64 = null,

    /// Create a tool with the given configuration
    pub fn create(config: ToolConfig) Tool {
        return .{
            .name = config.name,
            .description = config.description,
            .parameters = config.parameters,
            .execute = config.execute,
            .on_input_available = config.on_input_available,
            .requires_approval = config.requires_approval,
            .max_execution_time_ms = config.max_execution_time_ms,
        };
    }
};

/// Tool configuration for creation
pub const ToolConfig = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    parameters: std.json.Value,
    execute: ?ExecuteFn = null,
    on_input_available: ?OnInputAvailableFn = null,
    requires_approval: ApprovalRequirement = .never,
    max_execution_time_ms: ?u64 = null,
};

/// Dynamic tool (created at runtime by the model)
pub const DynamicTool = struct {
    /// Tool name
    name: []const u8,

    /// Tool description
    description: ?[]const u8 = null,

    /// Parameter schema
    parameters: std.json.Value,

    /// Whether this is a provider-side tool
    provider_executed: bool = false,
};

/// Convert tool to language model format
pub fn toLanguageModelTool(allocator: std.mem.Allocator, tool: Tool) !std.json.Value {
    var obj = std.json.ObjectMap.init(allocator);

    try obj.put("type", std.json.Value{ .string = "function" });

    var func = std.json.ObjectMap.init(allocator);
    try func.put("name", std.json.Value{ .string = tool.name });

    if (tool.description) |desc| {
        try func.put("description", std.json.Value{ .string = desc });
    }

    try func.put("parameters", tool.parameters);

    try obj.put("function", std.json.Value{ .object = func });

    return std.json.Value{ .object = obj };
}

/// Create a simple parameter schema
pub fn createParameterSchema(allocator: std.mem.Allocator, properties: anytype) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);
    try schema.put("type", std.json.Value{ .string = "object" });

    var props = std.json.ObjectMap.init(allocator);
    var required = std.json.Array.init(allocator);

    inline for (std.meta.fields(@TypeOf(properties))) |field| {
        const value = @field(properties, field.name);
        var prop = std.json.ObjectMap.init(allocator);

        if (@hasField(@TypeOf(value), "type")) {
            try prop.put("type", std.json.Value{ .string = value.type });
        }
        if (@hasField(@TypeOf(value), "description")) {
            if (value.description) |desc| {
                try prop.put("description", std.json.Value{ .string = desc });
            }
        }
        if (@hasField(@TypeOf(value), "required")) {
            if (value.required) {
                try required.append(std.json.Value{ .string = field.name });
            }
        }

        try props.put(field.name, std.json.Value{ .object = prop });
    }

    try schema.put("properties", std.json.Value{ .object = props });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

test "Tool creation" {
    const allocator = std.testing.allocator;

    var params = std.json.ObjectMap.init(allocator);
    defer params.deinit();
    try params.put("type", std.json.Value{ .string = "object" });

    const tool = Tool.create(.{
        .name = "test_tool",
        .description = "A test tool",
        .parameters = std.json.Value{ .object = params },
    });

    try std.testing.expectEqualStrings("test_tool", tool.name);
    try std.testing.expectEqualStrings("A test tool", tool.description.?);
}

test "ApprovalRequirement variants" {
    const always = ApprovalRequirement.always;
    try std.testing.expect(always == .always);

    const never = ApprovalRequirement.never;
    try std.testing.expect(never == .never);
}
