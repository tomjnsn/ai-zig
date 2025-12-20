// Tool Calling Example
//
// This example demonstrates how to define and use tools (function calling)
// with the Zig AI SDK. Tools allow the model to call functions you define.

const std = @import("std");
const ai = @import("ai");
const openai = @import("openai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Tool Calling Example\n", .{});
    std.debug.print("====================\n\n", .{});

    // Create OpenAI provider
    var provider = openai.createOpenAI(allocator);
    defer provider.deinit();

    var model = provider.languageModel("gpt-4o");
    std.debug.print("Using model: {s}\n\n", .{model.getModelId()});

    // Define tool schemas
    std.debug.print("1. Defining Tool Schemas\n", .{});
    std.debug.print("-------------------------\n", .{});

    const weather_schema = try createWeatherSchema(allocator);
    const calculator_schema = try createCalculatorSchema(allocator);

    // Create tools
    const weather_tool = ai.Tool.create(.{
        .name = "get_weather",
        .description = "Get the current weather for a location",
        .parameters = weather_schema,
        .execute = getWeather,
    });

    const calculator_tool = ai.Tool.create(.{
        .name = "calculate",
        .description = "Perform a mathematical calculation",
        .parameters = calculator_schema,
        .execute = calculate,
    });

    const tools = [_]ai.Tool{ weather_tool, calculator_tool };

    std.debug.print("Defined tools:\n", .{});
    for (tools) |tool| {
        std.debug.print("  - {s}: {s}\n", .{ tool.name, tool.description orelse "No description" });
    }
    std.debug.print("\n", .{});

    // Show how to use tools with text generation
    std.debug.print("2. Using Tools with Text Generation\n", .{});
    std.debug.print("-------------------------------------\n", .{});
    std.debug.print("To use tools, pass them to generateText or streamText:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const result = try ai.generateText(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"What's the weather in Tokyo?\",\n", .{});
    std.debug.print("      .tools = &tools,\n", .{});
    std.debug.print("      .max_steps = 5,  // Allow multiple tool calls\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("\n", .{});

    // Show tool execution flow
    std.debug.print("3. Tool Execution Flow\n", .{});
    std.debug.print("-----------------------\n", .{});
    std.debug.print("  1. User sends a prompt\n", .{});
    std.debug.print("  2. Model decides to call a tool\n", .{});
    std.debug.print("  3. SDK invokes the tool's execute function\n", .{});
    std.debug.print("  4. Tool result is sent back to the model\n", .{});
    std.debug.print("  5. Model generates final response\n", .{});
    std.debug.print("\n", .{});

    // Demonstrate tool execution directly
    std.debug.print("4. Direct Tool Execution Demo\n", .{});
    std.debug.print("------------------------------\n", .{});

    // Simulate a tool call from the model
    var input_obj = std.json.ObjectMap.init(allocator);
    try input_obj.put("location", std.json.Value{ .string = "San Francisco, CA" });
    try input_obj.put("unit", std.json.Value{ .string = "fahrenheit" });
    const input = std.json.Value{ .object = input_obj };

    std.debug.print("Simulating tool call: get_weather({{location: 'San Francisco, CA', unit: 'fahrenheit'}})\n", .{});

    const context = ai.ToolExecutionContext{};
    const result = try getWeather(input, context);

    switch (result) {
        .success => |value| {
            std.debug.print("Tool returned successfully:\n", .{});
            if (value.object.get("temperature")) |temp| {
                if (value.object.get("conditions")) |cond| {
                    std.debug.print("  Temperature: {d}F, Conditions: {s}\n", .{ temp.integer, cond.string });
                }
            }
        },
        .@"error" => |err| {
            std.debug.print("Tool error: {s}\n", .{err.message});
        },
    }
    std.debug.print("\n", .{});

    // Show approval requirement options
    std.debug.print("5. Tool Approval Requirements\n", .{});
    std.debug.print("------------------------------\n", .{});
    std.debug.print("Tools can require approval before execution:\n", .{});
    std.debug.print("  .requires_approval = .never   // Execute immediately\n", .{});
    std.debug.print("  .requires_approval = .always  // Always ask for approval\n", .{});
    std.debug.print("  .requires_approval = .custom  // Custom approval function\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example complete!\n", .{});
}

/// Create the weather tool parameter schema
fn createWeatherSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    // Location property
    var location = std.json.ObjectMap.init(allocator);
    try location.put("type", std.json.Value{ .string = "string" });
    try location.put("description", std.json.Value{ .string = "The city and state, e.g. San Francisco, CA" });
    try properties.put("location", std.json.Value{ .object = location });

    // Unit property
    var unit = std.json.ObjectMap.init(allocator);
    try unit.put("type", std.json.Value{ .string = "string" });
    try unit.put("description", std.json.Value{ .string = "Temperature unit: celsius or fahrenheit" });
    var unit_enum = std.json.Array.init(allocator);
    try unit_enum.append(std.json.Value{ .string = "celsius" });
    try unit_enum.append(std.json.Value{ .string = "fahrenheit" });
    try unit.put("enum", std.json.Value{ .array = unit_enum });
    try properties.put("unit", std.json.Value{ .object = unit });

    try schema.put("properties", std.json.Value{ .object = properties });

    // Required fields
    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "location" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

/// Create the calculator tool parameter schema
fn createCalculatorSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    // Expression property
    var expression = std.json.ObjectMap.init(allocator);
    try expression.put("type", std.json.Value{ .string = "string" });
    try expression.put("description", std.json.Value{ .string = "The mathematical expression to evaluate, e.g. '2 + 2'" });
    try properties.put("expression", std.json.Value{ .object = expression });

    try schema.put("properties", std.json.Value{ .object = properties });

    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "expression" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

/// Execute the weather tool
fn getWeather(input: std.json.Value, context: ai.ToolExecutionContext) anyerror!ai.ToolExecutionResult {
    _ = context;

    // Parse the input
    const location = if (input.object.get("location")) |loc| loc.string else "Unknown";
    const unit = if (input.object.get("unit")) |u| u.string else "fahrenheit";

    // Simulate weather data (in a real app, you'd call a weather API)
    const temp: i32 = if (std.mem.eql(u8, unit, "celsius")) 22 else 72;
    const unit_symbol: []const u8 = if (std.mem.eql(u8, unit, "celsius")) "C" else "F";

    // Create result
    var result = std.json.ObjectMap.init(std.heap.page_allocator);
    try result.put("location", std.json.Value{ .string = location });
    try result.put("temperature", std.json.Value{ .integer = temp });
    try result.put("unit", std.json.Value{ .string = unit_symbol });
    try result.put("conditions", std.json.Value{ .string = "Sunny" });
    try result.put("humidity", std.json.Value{ .integer = 65 });

    return .{ .success = std.json.Value{ .object = result } };
}

/// Execute the calculator tool
fn calculate(input: std.json.Value, context: ai.ToolExecutionContext) anyerror!ai.ToolExecutionResult {
    _ = context;

    const expression = if (input.object.get("expression")) |expr| expr.string else "";

    // Simple expression parser (in a real app, use a proper math parser)
    // This is just a placeholder that handles simple cases
    const result_value: f64 = 42.0; // Placeholder result

    var result = std.json.ObjectMap.init(std.heap.page_allocator);
    try result.put("expression", std.json.Value{ .string = expression });
    try result.put("result", std.json.Value{ .float = result_value });

    return .{ .success = std.json.Value{ .object = result } };
}
