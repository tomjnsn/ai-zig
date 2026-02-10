const std = @import("std");
const provider_types = @import("provider");
const generate_text = @import("../generate-text/generate-text.zig");
const generate_object = @import("generate-object.zig");

const LanguageModelV3 = provider_types.LanguageModelV3;
const LanguageModelUsage = generate_text.LanguageModelUsage;
const ResponseMetadata = generate_text.ResponseMetadata;
const CallSettings = generate_text.CallSettings;
const Message = generate_text.Message;
const Schema = generate_object.Schema;
const OutputMode = generate_object.OutputMode;

/// Stream part types for object streaming
pub const ObjectStreamPart = union(enum) {
    /// Partial JSON delta
    partial: PartialDelta,

    /// Object update (new partial parse available)
    object_update: ObjectUpdate,

    /// Stream finished
    finish: ObjectFinish,

    /// Error occurred
    @"error": ObjectError,
};

pub const PartialDelta = struct {
    text: []const u8,
};

pub const ObjectUpdate = struct {
    /// The current partial object (may be incomplete)
    partial_object: std.json.Value,
};

pub const ObjectFinish = struct {
    /// The final complete object
    object: std.json.Value,
    /// Token usage
    usage: LanguageModelUsage,
};

pub const ObjectError = struct {
    message: []const u8,
    code: ?[]const u8 = null,
};

/// Callbacks for streaming object generation
pub const ObjectStreamCallbacks = struct {
    /// Called for each stream part
    on_part: *const fn (part: ObjectStreamPart, context: ?*anyopaque) void,

    /// Called when an error occurs
    on_error: *const fn (err: anyerror, context: ?*anyopaque) void,

    /// Called when streaming completes
    on_complete: *const fn (context: ?*anyopaque) void,

    /// User context passed to callbacks
    context: ?*anyopaque = null,
};

/// Options for streamObject
pub const StreamObjectOptions = struct {
    /// The language model to use
    model: *LanguageModelV3,

    /// Schema defining the expected object structure
    schema: Schema,

    /// System prompt
    system: ?[]const u8 = null,

    /// Simple text prompt (use this OR messages, not both)
    prompt: ?[]const u8 = null,

    /// Conversation messages (use this OR prompt, not both)
    messages: ?[]const Message = null,

    /// Output mode
    mode: OutputMode = .auto,

    /// Call settings
    settings: CallSettings = .{},

    /// Maximum retries on failure
    max_retries: u32 = 2,

    /// Stream callbacks
    callbacks: ObjectStreamCallbacks,

    /// Request context for timeout/cancellation
    request_context: ?*const @import("../context.zig").RequestContext = null,

    /// Retry policy for automatic retries
    retry_policy: ?@import("../retry.zig").RetryPolicy = null,
};

/// Result handle for streaming object generation
pub const StreamObjectResult = struct {
    allocator: std.mem.Allocator,
    options: StreamObjectOptions,

    /// The accumulated raw text
    raw_text: std.array_list.Managed(u8),

    /// Current partial object (may be null if parsing failed)
    partial_object: ?std.json.Value = null,

    /// Final object (set when complete)
    object: ?std.json.Value = null,

    /// Current usage
    usage: LanguageModelUsage = .{},

    /// Response metadata
    response: ?ResponseMetadata = null,

    /// Whether streaming is complete
    is_complete: bool = false,

    pub fn init(allocator: std.mem.Allocator, options: StreamObjectOptions) StreamObjectResult {
        return .{
            .allocator = allocator,
            .options = options,
            .raw_text = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *StreamObjectResult) void {
        self.raw_text.deinit();
    }

    /// Get the current partial object
    pub fn getPartialObject(self: *const StreamObjectResult) ?std.json.Value {
        return self.partial_object;
    }

    /// Get the final object (only valid after completion)
    pub fn getObject(self: *const StreamObjectResult) ?std.json.Value {
        return self.object;
    }

    /// Get the accumulated raw text
    pub fn getRawText(self: *const StreamObjectResult) []const u8 {
        return self.raw_text.items;
    }

    /// Process a stream part (internal use)
    pub fn processPart(self: *StreamObjectResult, part: ObjectStreamPart) !void {
        switch (part) {
            .partial => |delta| {
                try self.raw_text.appendSlice(delta.text);
                // Try to parse partial JSON
                // Note: We extract .value and leak the Parsed wrapper here.
                // The memory will be cleaned up when self.allocator is freed.
                if (generate_object.parseJsonOutput(self.allocator, self.raw_text.items)) |parsed| {
                    self.partial_object = parsed.value;
                } else |_| {
                    self.partial_object = null;
                }
            },
            .object_update => |update| {
                self.partial_object = update.partial_object;
            },
            .finish => |finish| {
                self.object = finish.object;
                self.usage = finish.usage;
                self.is_complete = true;
            },
            .@"error" => {},
        }
    }
};

/// Error types for stream object
pub const StreamObjectError = error{
    ModelError,
    NetworkError,
    InvalidPrompt,
    InvalidSchema,
    ParseError,
    Cancelled,
    OutOfMemory,
};

/// Stream object generation using a language model
/// This function is non-blocking and uses callbacks for streaming
pub fn streamObject(
    allocator: std.mem.Allocator,
    options: StreamObjectOptions,
) StreamObjectError!*StreamObjectResult {
    // Check request context for cancellation/timeout
    if (options.request_context) |ctx| {
        if (ctx.isDone()) return StreamObjectError.Cancelled;
    }

    // Validate options
    if (options.prompt == null and options.messages == null) {
        return StreamObjectError.InvalidPrompt;
    }
    if (options.prompt != null and options.messages != null) {
        return StreamObjectError.InvalidPrompt;
    }

    // Create result handle
    const result = allocator.create(StreamObjectResult) catch return StreamObjectError.OutOfMemory;
    result.* = StreamObjectResult.init(allocator, options);

    // TODO: Start actual streaming
    // For now, emit a placeholder finish event
    const finish_part = ObjectStreamPart{
        .finish = .{
            .object = std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
            .usage = .{},
        },
    };

    result.processPart(finish_part) catch return StreamObjectError.OutOfMemory;
    options.callbacks.on_part(finish_part, options.callbacks.context);
    options.callbacks.on_complete(options.callbacks.context);

    return result;
}

test "StreamObjectResult init and deinit" {
    const allocator = std.testing.allocator;
    const callbacks = ObjectStreamCallbacks{
        .on_part = struct {
            fn f(_: ObjectStreamPart, _: ?*anyopaque) void {}
        }.f,
        .on_error = struct {
            fn f(_: anyerror, _: ?*anyopaque) void {}
        }.f,
        .on_complete = struct {
            fn f(_: ?*anyopaque) void {}
        }.f,
    };

    const model: LanguageModelV3 = undefined;
    var result = StreamObjectResult.init(allocator, .{
        .model = @constCast(&model),
        .prompt = "Generate a user",
        .schema = .{
            .json_schema = std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
        },
        .callbacks = callbacks,
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.raw_text.items.len);
}
