const std = @import("std");
const provider_types = @import("provider");
const generate_text = @import("../generate-text/generate-text.zig");
const generate_object = @import("generate-object.zig");

const LanguageModelV3 = provider_types.LanguageModelV3;
const prompt_types = provider_types.language_model.language_model_v3_prompt;
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
    raw_text: std.ArrayList(u8),

    /// Current partial object (may be null if parsing failed)
    partial_object: ?std.json.Value = null,

    /// Final object (set when complete)
    object: ?std.json.Value = null,

    /// Internal: tracks the current partial parse for cleanup
    _partial_parsed: ?std.json.Parsed(std.json.Value) = null,

    /// Internal: tracks the final parse for cleanup
    _final_parsed: ?std.json.Parsed(std.json.Value) = null,

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
            .raw_text = std.ArrayList(u8).empty,
        };
    }

    pub fn deinit(self: *StreamObjectResult) void {
        if (self._partial_parsed) |p| p.deinit();
        if (self._final_parsed) |p| p.deinit();
        self.raw_text.deinit(self.allocator);
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
                try self.raw_text.appendSlice(self.allocator, delta.text);
                // Try to parse partial JSON; track Parsed for proper cleanup
                if (generate_object.parseJsonOutput(self.allocator, self.raw_text.items)) |parsed| {
                    if (self._partial_parsed) |prev| prev.deinit();
                    self._partial_parsed = parsed;
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

    // Build prompt using arena for temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Build system prompt with schema instructions (same as generateObject)
    var system_parts = std.ArrayList(u8).empty;
    const sys_writer = system_parts.writer(arena_allocator);

    if (options.system) |sys| {
        sys_writer.writeAll(sys) catch return StreamObjectError.OutOfMemory;
        sys_writer.writeAll("\n\n") catch return StreamObjectError.OutOfMemory;
    }

    sys_writer.writeAll("You must respond with a valid JSON object matching the following schema:\n") catch return StreamObjectError.OutOfMemory;
    const schema_json = std.json.Stringify.valueAlloc(arena_allocator, options.schema.json_schema, .{}) catch return StreamObjectError.OutOfMemory;
    sys_writer.writeAll(schema_json) catch return StreamObjectError.OutOfMemory;

    // Build provider-level prompt messages
    var prompt_msgs = std.ArrayList(provider_types.LanguageModelV3Message).empty;

    prompt_msgs.append(arena_allocator, provider_types.language_model.systemMessage(system_parts.items)) catch return StreamObjectError.OutOfMemory;

    if (options.prompt) |prompt| {
        const msg = provider_types.language_model.userTextMessage(arena_allocator, prompt) catch return StreamObjectError.OutOfMemory;
        prompt_msgs.append(arena_allocator, msg) catch return StreamObjectError.OutOfMemory;
    } else if (options.messages) |msgs| {
        for (msgs) |msg| {
            switch (msg.content) {
                .text => |text| {
                    switch (msg.role) {
                        .user => {
                            const m = provider_types.language_model.userTextMessage(arena_allocator, text) catch return StreamObjectError.OutOfMemory;
                            prompt_msgs.append(arena_allocator, m) catch return StreamObjectError.OutOfMemory;
                        },
                        .assistant => {
                            const m = provider_types.language_model.assistantTextMessage(arena_allocator, text) catch return StreamObjectError.OutOfMemory;
                            prompt_msgs.append(arena_allocator, m) catch return StreamObjectError.OutOfMemory;
                        },
                        else => {},
                    }
                },
                .parts => |parts| {
                    switch (msg.role) {
                        .user => {
                            var user_parts = std.ArrayList(prompt_types.UserPart).empty;
                            for (parts) |part| {
                                switch (part) {
                                    .text => |t| {
                                        user_parts.append(arena_allocator, .{ .text = .{ .text = t.text } }) catch return StreamObjectError.OutOfMemory;
                                    },
                                    .file => |f| {
                                        user_parts.append(arena_allocator, .{ .file = .{
                                            .data = .{ .base64 = f.data },
                                            .media_type = f.mime_type,
                                        } }) catch return StreamObjectError.OutOfMemory;
                                    },
                                    else => {},
                                }
                            }
                            if (user_parts.items.len > 0) {
                                prompt_msgs.append(arena_allocator, .{
                                    .role = .user,
                                    .content = .{ .user = user_parts.items },
                                }) catch return StreamObjectError.OutOfMemory;
                            }
                        },
                        .assistant => {
                            var asst_parts = std.ArrayList(prompt_types.AssistantPart).empty;
                            for (parts) |part| {
                                switch (part) {
                                    .text => |t| {
                                        asst_parts.append(arena_allocator, .{ .text = .{ .text = t.text } }) catch return StreamObjectError.OutOfMemory;
                                    },
                                    .file => |f| {
                                        asst_parts.append(arena_allocator, .{ .file = .{
                                            .data = .{ .base64 = f.data },
                                            .media_type = f.mime_type,
                                        } }) catch return StreamObjectError.OutOfMemory;
                                    },
                                    else => {},
                                }
                            }
                            if (asst_parts.items.len > 0) {
                                prompt_msgs.append(arena_allocator, .{
                                    .role = .assistant,
                                    .content = .{ .assistant = asst_parts.items },
                                }) catch return StreamObjectError.OutOfMemory;
                            }
                        },
                        else => {},
                    }
                },
            }
        }
    }

    // Build call options
    const call_options = provider_types.LanguageModelV3CallOptions{
        .prompt = prompt_msgs.items,
        .max_output_tokens = options.settings.max_output_tokens,
        .temperature = if (options.settings.temperature) |t| @as(f32, @floatCast(t)) else null,
        .top_p = if (options.settings.top_p) |t| @as(f32, @floatCast(t)) else null,
        .seed = if (options.settings.seed) |s| @as(i64, @intCast(s)) else null,
    };

    // Bridge: translate provider-level stream parts to ObjectStreamPart
    const BridgeCtx = struct {
        res: *StreamObjectResult,
        cbs: ObjectStreamCallbacks,
        schema: std.json.Value,

        fn onPart(ctx_ptr: ?*anyopaque, part: provider_types.LanguageModelV3StreamPart) void {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr.?));
            switch (part) {
                .text_delta => |d| {
                    const partial = ObjectStreamPart{ .partial = .{ .text = d.delta } };
                    self.res.processPart(partial) catch |err| {
                        self.cbs.on_error(err, self.cbs.context);
                        return;
                    };
                    self.cbs.on_part(partial, self.cbs.context);

                    // If partial parsing succeeded, emit object_update
                    if (self.res.partial_object) |po| {
                        const update = ObjectStreamPart{ .object_update = .{ .partial_object = po } };
                        self.cbs.on_part(update, self.cbs.context);
                    }
                },
                .finish => |f| {
                    const usage = LanguageModelUsage{
                        .input_tokens = f.usage.input_tokens.total,
                        .output_tokens = f.usage.output_tokens.total,
                    };

                    // Parse final JSON from accumulated text
                    if (generate_object.parseJsonOutput(self.res.allocator, self.res.raw_text.items)) |parsed| {
                        // Validate against schema
                        if (!generate_object.validateAgainstSchema(parsed.value, self.schema)) {
                            var p = parsed;
                            p.deinit();
                            const err_part = ObjectStreamPart{ .@"error" = .{ .message = "Schema validation failed" } };
                            self.cbs.on_part(err_part, self.cbs.context);
                            return;
                        }

                        // Store final parsed for proper cleanup; release partial
                        if (self.res._partial_parsed) |prev| prev.deinit();
                        self.res._partial_parsed = null;
                        self.res._final_parsed = parsed;

                        const finish_part = ObjectStreamPart{ .finish = .{ .object = parsed.value, .usage = usage } };
                        self.res.processPart(finish_part) catch |err| {
                            self.cbs.on_error(err, self.cbs.context);
                            return;
                        };
                        self.cbs.on_part(finish_part, self.cbs.context);
                    } else |_| {
                        const err_part = ObjectStreamPart{ .@"error" = .{ .message = "Failed to parse JSON from model output" } };
                        self.cbs.on_part(err_part, self.cbs.context);
                    }
                },
                .@"error" => |e| {
                    const err_part = ObjectStreamPart{ .@"error" = .{ .message = e.message orelse "Unknown model error" } };
                    self.cbs.on_part(err_part, self.cbs.context);
                },
                else => {},
            }
        }

        fn onError(ctx_ptr: ?*anyopaque, err: anyerror) void {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr.?));
            self.cbs.on_error(err, self.cbs.context);
        }

        fn onComplete(ctx_ptr: ?*anyopaque, _: ?LanguageModelV3.StreamCompleteInfo) void {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr.?));
            self.cbs.on_complete(self.cbs.context);
        }
    };

    // Safety: bridge is stack-allocated but this is safe because doStream
    // completes all callbacks synchronously before returning.
    var bridge = BridgeCtx{ .res = result, .cbs = options.callbacks, .schema = options.schema.json_schema };
    const bridge_ptr: *anyopaque = @ptrCast(&bridge);
    options.model.doStream(call_options, allocator, .{
        .on_part = BridgeCtx.onPart,
        .on_error = BridgeCtx.onError,
        .on_complete = BridgeCtx.onComplete,
        .ctx = bridge_ptr,
    });

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

test "streamObject delivers partial deltas and final object" {
    const allocator = std.testing.allocator;

    const MockModel = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-stream-obj";
        }

        pub fn getSupportedUrls(
            _: *const Self,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.SupportedUrlsResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.Unsupported });
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.NotImplemented });
        }

        pub fn doStream(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callbacks: LanguageModelV3.StreamCallbacks,
        ) void {
            // Stream a JSON object in chunks
            callbacks.on_part(callbacks.ctx, provider_types.language_model.textDelta("t1", "{\"name\""));
            callbacks.on_part(callbacks.ctx, provider_types.language_model.textDelta("t1", ":\"Alice\","));
            callbacks.on_part(callbacks.ctx, provider_types.language_model.textDelta("t1", "\"age\":30}"));
            callbacks.on_part(callbacks.ctx, provider_types.language_model.finish(
                provider_types.LanguageModelV3Usage.initWithTotals(10, 20),
                .stop,
            ));
            callbacks.on_complete(callbacks.ctx, null);
        }
    };

    const TestCtx = struct {
        partial_count: u32 = 0,
        got_finish: bool = false,
        got_complete: bool = false,

        fn onPart(part: ObjectStreamPart, ctx_raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx_raw.?));
            switch (part) {
                .partial => self.partial_count += 1,
                .finish => self.got_finish = true,
                .object_update => {},
                .@"error" => {},
            }
        }

        fn onError(_: anyerror, _: ?*anyopaque) void {}
        fn onComplete(ctx_raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx_raw.?));
            self.got_complete = true;
        }
    };

    var test_ctx = TestCtx{};

    var mock = MockModel{};
    var model = provider_types.asLanguageModel(MockModel, &mock);

    const schema = try std.json.parseFromSlice(std.json.Value, allocator,
        \\{"type":"object"}
    , .{});
    defer schema.deinit();

    const result = try streamObject(allocator, .{
        .model = &model,
        .prompt = "Generate a person",
        .schema = .{ .json_schema = schema.value },
        .callbacks = .{
            .on_part = TestCtx.onPart,
            .on_error = TestCtx.onError,
            .on_complete = TestCtx.onComplete,
            .context = @ptrCast(&test_ctx),
        },
    });
    defer {
        result.deinit();
        allocator.destroy(result);
    }

    // 3 text deltas should produce 3 partial events
    try std.testing.expectEqual(@as(u32, 3), test_ctx.partial_count);
    try std.testing.expect(test_ctx.got_finish);
    try std.testing.expect(test_ctx.got_complete);
    try std.testing.expect(result.is_complete);
    try std.testing.expectEqualStrings("{\"name\":\"Alice\",\"age\":30}", result.getRawText());
}

test "streamObject emits error on schema validation failure" {
    const allocator = std.testing.allocator;

    const MockModel = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-bad-schema";
        }

        pub fn getSupportedUrls(
            _: *const Self,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.SupportedUrlsResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.Unsupported });
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.NotImplemented });
        }

        pub fn doStream(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callbacks: LanguageModelV3.StreamCallbacks,
        ) void {
            // Stream JSON missing required "name" field
            callbacks.on_part(callbacks.ctx, provider_types.language_model.textDelta("t1", "{\"wrong\":\"field\"}"));
            callbacks.on_part(callbacks.ctx, provider_types.language_model.finish(
                provider_types.LanguageModelV3Usage.initWithTotals(5, 10),
                .stop,
            ));
            callbacks.on_complete(callbacks.ctx, null);
        }
    };

    const TestCtx = struct {
        got_error: bool = false,
        got_finish: bool = false,

        fn onPart(part: ObjectStreamPart, ctx_raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx_raw.?));
            switch (part) {
                .@"error" => self.got_error = true,
                .finish => self.got_finish = true,
                else => {},
            }
        }

        fn onError(_: anyerror, _: ?*anyopaque) void {}
        fn onComplete(_: ?*anyopaque) void {}
    };

    var test_ctx = TestCtx{};

    var mock = MockModel{};
    var model = provider_types.asLanguageModel(MockModel, &mock);

    // Schema requires "name" field
    const schema = try std.json.parseFromSlice(std.json.Value, allocator,
        \\{"type":"object","required":["name"]}
    , .{});
    defer schema.deinit();

    const result = try streamObject(allocator, .{
        .model = &model,
        .prompt = "Generate a person",
        .schema = .{ .json_schema = schema.value },
        .callbacks = .{
            .on_part = TestCtx.onPart,
            .on_error = TestCtx.onError,
            .on_complete = TestCtx.onComplete,
            .context = @ptrCast(&test_ctx),
        },
    });
    defer {
        result.deinit();
        allocator.destroy(result);
    }

    // Should get error (validation failed), not finish
    try std.testing.expect(test_ctx.got_error);
    try std.testing.expect(!test_ctx.got_finish);
}

test "streamObject with empty prompt returns InvalidPrompt" {
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

    const result = streamObject(std.testing.allocator, .{
        .model = @constCast(&model),
        .schema = .{
            .json_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.testing.allocator) },
        },
        .callbacks = callbacks,
    });

    try std.testing.expectError(StreamObjectError.InvalidPrompt, result);
}

test "streamObject emits error on unparseable JSON" {
    const allocator = std.testing.allocator;

    const MockModel = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-bad-json";
        }

        pub fn getSupportedUrls(
            _: *const Self,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.SupportedUrlsResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.Unsupported });
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, LanguageModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.NotImplemented });
        }

        pub fn doStream(
            _: *const Self,
            _: provider_types.LanguageModelV3CallOptions,
            _: std.mem.Allocator,
            callbacks: LanguageModelV3.StreamCallbacks,
        ) void {
            // Stream non-JSON text
            callbacks.on_part(callbacks.ctx, provider_types.language_model.textDelta("t1", "not json at all"));
            callbacks.on_part(callbacks.ctx, provider_types.language_model.finish(
                provider_types.LanguageModelV3Usage.initWithTotals(3, 5),
                .stop,
            ));
            callbacks.on_complete(callbacks.ctx, null);
        }
    };

    const TestCtx = struct {
        got_error: bool = false,

        fn onPart(part: ObjectStreamPart, ctx_raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx_raw.?));
            switch (part) {
                .@"error" => self.got_error = true,
                else => {},
            }
        }

        fn onError(_: anyerror, _: ?*anyopaque) void {}
        fn onComplete(_: ?*anyopaque) void {}
    };

    var test_ctx = TestCtx{};

    var mock = MockModel{};
    var model = provider_types.asLanguageModel(MockModel, &mock);

    const result = try streamObject(allocator, .{
        .model = &model,
        .prompt = "Generate something",
        .schema = .{
            .json_schema = std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
        },
        .callbacks = .{
            .on_part = TestCtx.onPart,
            .on_error = TestCtx.onError,
            .on_complete = TestCtx.onComplete,
            .context = @ptrCast(&test_ctx),
        },
    });
    defer {
        result.deinit();
        allocator.destroy(result);
    }

    try std.testing.expect(test_ctx.got_error);
}
