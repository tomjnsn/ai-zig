// Structured Output Example
//
// This example demonstrates how to generate structured JSON objects
// using the generateObject API. This is useful for extracting
// structured data from text or generating type-safe responses.

const std = @import("std");
const ai = @import("ai");
const openai = @import("openai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Structured Output Example\n", .{});
    std.debug.print("=========================\n\n", .{});

    // Create OpenAI provider
    var provider = openai.createOpenAI(allocator);
    defer provider.deinit();

    var model = provider.languageModel("gpt-4o");
    std.debug.print("Using model: {s}\n\n", .{model.getModelId()});

    // Example 1: Person extraction schema
    std.debug.print("1. Person Extraction Schema\n", .{});
    std.debug.print("----------------------------\n", .{});

    const person_schema = try createPersonSchema(allocator);
    std.debug.print("Schema for extracting person information:\n", .{});
    printSchema(person_schema);
    std.debug.print("\n", .{});

    // Example usage (requires API key)
    // const result = try ai.generateObject(allocator, .{
    //     .model = &model,
    //     .schema = person_schema,
    //     .prompt = "Extract: John Smith is a 32 year old software engineer living in Seattle.",
    // });
    // std.debug.print("Extracted: {s}\n", .{result.object});

    // Example 2: Recipe schema
    std.debug.print("2. Recipe Schema\n", .{});
    std.debug.print("-----------------\n", .{});

    const recipe_schema = try createRecipeSchema(allocator);
    std.debug.print("Schema for generating recipes:\n", .{});
    printSchema(recipe_schema);
    std.debug.print("\n", .{});

    // Example 3: Event extraction schema
    std.debug.print("3. Calendar Event Schema\n", .{});
    std.debug.print("--------------------------\n", .{});

    const event_schema = try createEventSchema(allocator);
    std.debug.print("Schema for extracting calendar events:\n", .{});
    printSchema(event_schema);
    std.debug.print("\n", .{});

    // Example 4: Output modes
    std.debug.print("4. Output Modes\n", .{});
    std.debug.print("----------------\n", .{});
    std.debug.print("The SDK supports different output modes:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  json        - Model returns valid JSON (default)\n", .{});
    std.debug.print("  tool        - Uses tool calling for structured output\n", .{});
    std.debug.print("  grammar     - Uses grammar-based generation (when supported)\n", .{});
    std.debug.print("\n", .{});

    // Example 5: Streaming structured output
    std.debug.print("5. Streaming Structured Output\n", .{});
    std.debug.print("-------------------------------\n", .{});
    std.debug.print("Use streamObject() for streaming structured generation:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  - Receive partial objects as they're generated\n", .{});
    std.debug.print("  - Useful for large objects or real-time updates\n", .{});
    std.debug.print("  - Callbacks receive ObjectStreamPart events\n", .{});
    std.debug.print("\n", .{});

    // Example 6: Validation
    std.debug.print("6. Schema Validation\n", .{});
    std.debug.print("---------------------\n", .{});
    std.debug.print("The SDK validates output against the schema:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  - Required fields must be present\n", .{});
    std.debug.print("  - Types must match (string, number, boolean, etc.)\n", .{});
    std.debug.print("  - Enums are restricted to defined values\n", .{});
    std.debug.print("  - Arrays and nested objects are supported\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example complete!\n", .{});
}

/// Create a schema for extracting person information
fn createPersonSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });
    try schema.put("description", std.json.Value{ .string = "Information about a person" });

    var properties = std.json.ObjectMap.init(allocator);

    // Name
    var name = std.json.ObjectMap.init(allocator);
    try name.put("type", std.json.Value{ .string = "string" });
    try name.put("description", std.json.Value{ .string = "The person's full name" });
    try properties.put("name", std.json.Value{ .object = name });

    // Age
    var age = std.json.ObjectMap.init(allocator);
    try age.put("type", std.json.Value{ .string = "integer" });
    try age.put("description", std.json.Value{ .string = "The person's age in years" });
    try properties.put("age", std.json.Value{ .object = age });

    // Occupation
    var occupation = std.json.ObjectMap.init(allocator);
    try occupation.put("type", std.json.Value{ .string = "string" });
    try occupation.put("description", std.json.Value{ .string = "The person's job or occupation" });
    try properties.put("occupation", std.json.Value{ .object = occupation });

    // Location
    var location = std.json.ObjectMap.init(allocator);
    try location.put("type", std.json.Value{ .string = "string" });
    try location.put("description", std.json.Value{ .string = "Where the person lives" });
    try properties.put("location", std.json.Value{ .object = location });

    try schema.put("properties", std.json.Value{ .object = properties });

    // Required fields
    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "name" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

/// Create a schema for recipe generation
fn createRecipeSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    // Title
    var title = std.json.ObjectMap.init(allocator);
    try title.put("type", std.json.Value{ .string = "string" });
    try properties.put("title", std.json.Value{ .object = title });

    // Prep time
    var prep_time = std.json.ObjectMap.init(allocator);
    try prep_time.put("type", std.json.Value{ .string = "integer" });
    try prep_time.put("description", std.json.Value{ .string = "Preparation time in minutes" });
    try properties.put("prep_time_minutes", std.json.Value{ .object = prep_time });

    // Ingredients (array)
    var ingredients = std.json.ObjectMap.init(allocator);
    try ingredients.put("type", std.json.Value{ .string = "array" });
    var items = std.json.ObjectMap.init(allocator);
    try items.put("type", std.json.Value{ .string = "string" });
    try ingredients.put("items", std.json.Value{ .object = items });
    try properties.put("ingredients", std.json.Value{ .object = ingredients });

    // Instructions (array)
    var instructions = std.json.ObjectMap.init(allocator);
    try instructions.put("type", std.json.Value{ .string = "array" });
    var inst_items = std.json.ObjectMap.init(allocator);
    try inst_items.put("type", std.json.Value{ .string = "string" });
    try instructions.put("items", std.json.Value{ .object = inst_items });
    try properties.put("instructions", std.json.Value{ .object = instructions });

    // Servings
    var servings = std.json.ObjectMap.init(allocator);
    try servings.put("type", std.json.Value{ .string = "integer" });
    try properties.put("servings", std.json.Value{ .object = servings });

    try schema.put("properties", std.json.Value{ .object = properties });

    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "title" });
    try required.append(std.json.Value{ .string = "ingredients" });
    try required.append(std.json.Value{ .string = "instructions" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

/// Create a schema for calendar event extraction
fn createEventSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    // Title
    var title = std.json.ObjectMap.init(allocator);
    try title.put("type", std.json.Value{ .string = "string" });
    try properties.put("title", std.json.Value{ .object = title });

    // Date
    var date = std.json.ObjectMap.init(allocator);
    try date.put("type", std.json.Value{ .string = "string" });
    try date.put("format", std.json.Value{ .string = "date" });
    try date.put("description", std.json.Value{ .string = "Event date in YYYY-MM-DD format" });
    try properties.put("date", std.json.Value{ .object = date });

    // Time
    var time = std.json.ObjectMap.init(allocator);
    try time.put("type", std.json.Value{ .string = "string" });
    try time.put("description", std.json.Value{ .string = "Event time in HH:MM format" });
    try properties.put("time", std.json.Value{ .object = time });

    // Duration
    var duration = std.json.ObjectMap.init(allocator);
    try duration.put("type", std.json.Value{ .string = "integer" });
    try duration.put("description", std.json.Value{ .string = "Duration in minutes" });
    try properties.put("duration_minutes", std.json.Value{ .object = duration });

    // Location
    var location = std.json.ObjectMap.init(allocator);
    try location.put("type", std.json.Value{ .string = "string" });
    try properties.put("location", std.json.Value{ .object = location });

    // Attendees (array)
    var attendees = std.json.ObjectMap.init(allocator);
    try attendees.put("type", std.json.Value{ .string = "array" });
    var att_items = std.json.ObjectMap.init(allocator);
    try att_items.put("type", std.json.Value{ .string = "string" });
    try attendees.put("items", std.json.Value{ .object = att_items });
    try properties.put("attendees", std.json.Value{ .object = attendees });

    try schema.put("properties", std.json.Value{ .object = properties });

    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "title" });
    try required.append(std.json.Value{ .string = "date" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

/// Print a schema in a readable format
fn printSchema(schema: std.json.Value) void {
    const obj = schema.object;

    if (obj.get("description")) |desc| {
        std.debug.print("  Description: {s}\n", .{desc.string});
    }

    if (obj.get("properties")) |props| {
        std.debug.print("  Properties:\n", .{});
        var iter = props.object.iterator();
        while (iter.next()) |entry| {
            const prop_type = if (entry.value_ptr.object.get("type")) |t| t.string else "unknown";
            const prop_desc = if (entry.value_ptr.object.get("description")) |d| d.string else "";
            std.debug.print("    - {s}: {s}", .{ entry.key_ptr.*, prop_type });
            if (prop_desc.len > 0) {
                std.debug.print(" ({s})", .{prop_desc});
            }
            std.debug.print("\n", .{});
        }
    }

    if (obj.get("required")) |req| {
        std.debug.print("  Required: ", .{});
        for (req.array.items, 0..) |item, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{item.string});
        }
        std.debug.print("\n", .{});
    }
}
