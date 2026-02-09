const std = @import("std");

/// Generic streaming callback interface.
/// This provides a type-safe way to handle streaming events.
pub fn StreamCallbacks(comptime T: type) type {
    return struct {
        /// Called for each item in the stream
        on_item: *const fn (ctx: ?*anyopaque, item: T) void,
        /// Called when an error occurs
        on_error: *const fn (ctx: ?*anyopaque, err: anyerror) void,
        /// Called when the stream completes successfully
        on_complete: *const fn (ctx: ?*anyopaque) void,
        /// User context passed to all callbacks
        ctx: ?*anyopaque = null,

        const Self = @This();

        /// Emit an item to the stream
        pub fn emit(self: Self, item: T) void {
            self.on_item(self.ctx, item);
        }

        /// Signal an error
        pub fn fail(self: Self, err: anyerror) void {
            self.on_error(self.ctx, err);
        }

        /// Signal completion
        pub fn complete(self: Self) void {
            self.on_complete(self.ctx);
        }
    };
}

/// Builder pattern for creating stream callbacks
pub fn CallbackBuilder(comptime T: type) type {
    return struct {
        callbacks: StreamCallbacks(T),

        const Self = @This();

        /// Create a new callback builder with no-op defaults
        pub fn init() Self {
            return .{
                .callbacks = .{
                    .on_item = noopItem,
                    .on_error = noopError,
                    .on_complete = noopComplete,
                    .ctx = null,
                },
            };
        }

        /// Set the item handler
        pub fn onItem(self: *Self, handler: *const fn (ctx: ?*anyopaque, item: T) void) *Self {
            self.callbacks.on_item = handler;
            return self;
        }

        /// Set the error handler
        pub fn onError(self: *Self, handler: *const fn (ctx: ?*anyopaque, err: anyerror) void) *Self {
            self.callbacks.on_error = handler;
            return self;
        }

        /// Set the completion handler
        pub fn onComplete(self: *Self, handler: *const fn (ctx: ?*anyopaque) void) *Self {
            self.callbacks.on_complete = handler;
            return self;
        }

        /// Set the context
        pub fn withContext(self: *Self, ctx: *anyopaque) *Self {
            self.callbacks.ctx = ctx;
            return self;
        }

        /// Build the final callbacks struct
        pub fn build(self: Self) StreamCallbacks(T) {
            return self.callbacks;
        }

        fn noopItem(_: ?*anyopaque, _: T) void {}
        fn noopError(_: ?*anyopaque, _: anyerror) void {}
        fn noopComplete(_: ?*anyopaque) void {}
    };
}

/// Streaming text callbacks - specialized for text streaming
pub const TextStreamCallbacks = struct {
    /// Called for each text delta
    on_text: ?*const fn (ctx: ?*anyopaque, text: []const u8) void = null,
    /// Called when all text is complete
    on_text_complete: ?*const fn (ctx: ?*anyopaque, full_text: []const u8) void = null,
    /// Called when an error occurs
    on_error: *const fn (ctx: ?*anyopaque, err: anyerror) void,
    /// Called when the stream completes
    on_complete: *const fn (ctx: ?*anyopaque) void,
    /// User context
    ctx: ?*anyopaque = null,
};

/// Tool call streaming callbacks
pub const ToolCallStreamCallbacks = struct {
    /// Called when a tool call starts
    on_tool_call_start: ?*const fn (ctx: ?*anyopaque, tool_name: []const u8, tool_call_id: []const u8) void = null,
    /// Called for each tool input delta
    on_tool_input_delta: ?*const fn (ctx: ?*anyopaque, tool_call_id: []const u8, delta: []const u8) void = null,
    /// Called when a tool call completes
    on_tool_call_complete: ?*const fn (ctx: ?*anyopaque, tool_call_id: []const u8, input: []const u8) void = null,
    /// Called when an error occurs
    on_error: *const fn (ctx: ?*anyopaque, err: anyerror) void,
    /// Called when the stream completes
    on_complete: *const fn (ctx: ?*anyopaque) void,
    /// User context
    ctx: ?*anyopaque = null,
};

/// Combined language model stream callbacks
pub const LanguageModelStreamCallbacks = struct {
    /// Text callbacks
    on_text_delta: ?*const fn (ctx: ?*anyopaque, text: []const u8) void = null,
    on_text_complete: ?*const fn (ctx: ?*anyopaque, full_text: []const u8) void = null,

    /// Tool call callbacks
    on_tool_call_start: ?*const fn (ctx: ?*anyopaque, tool_name: []const u8, tool_call_id: []const u8) void = null,
    on_tool_input_delta: ?*const fn (ctx: ?*anyopaque, tool_call_id: []const u8, delta: []const u8) void = null,
    on_tool_call_complete: ?*const fn (ctx: ?*anyopaque, tool_call_id: []const u8, input: []const u8) void = null,

    /// Metadata callbacks
    on_usage: ?*const fn (ctx: ?*anyopaque, input_tokens: u64, output_tokens: u64) void = null,
    on_finish_reason: ?*const fn (ctx: ?*anyopaque, reason: []const u8) void = null,

    /// Error and completion
    on_error: *const fn (ctx: ?*anyopaque, err: anyerror) void,
    on_complete: *const fn (ctx: ?*anyopaque) void,

    /// User context
    ctx: ?*anyopaque = null,

    const Self = @This();

    /// Create with just required callbacks
    pub fn init(
        on_error: *const fn (ctx: ?*anyopaque, err: anyerror) void,
        on_complete: *const fn (ctx: ?*anyopaque) void,
    ) Self {
        return .{
            .on_error = on_error,
            .on_complete = on_complete,
        };
    }
};

/// Accumulator for building up streaming content
pub const StreamAccumulator = struct {
    text: std.array_list.Managed(u8),
    tool_calls: std.array_list.Managed(AccumulatedToolCall),
    allocator: std.mem.Allocator,

    pub const AccumulatedToolCall = struct {
        id: []const u8,
        name: []const u8,
        input: std.array_list.Managed(u8),

        pub fn deinit(self: *AccumulatedToolCall, allocator: std.mem.Allocator) void {
            allocator.free(self.id);
            allocator.free(self.name);
            self.input.deinit();
        }
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .text = std.array_list.Managed(u8).init(allocator),
            .tool_calls = std.array_list.Managed(AccumulatedToolCall).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.text.deinit();
        for (self.tool_calls.items) |*tc| {
            tc.deinit(self.allocator);
        }
        self.tool_calls.deinit();
    }

    /// Append text to the accumulator
    pub fn appendText(self: *Self, text: []const u8) !void {
        try self.text.appendSlice(text);
    }

    /// Get the accumulated text
    pub fn getText(self: Self) []const u8 {
        return self.text.items;
    }

    /// Start a new tool call
    pub fn startToolCall(self: *Self, id: []const u8, name: []const u8) !void {
        try self.tool_calls.append(.{
            .id = try self.allocator.dupe(u8, id),
            .name = try self.allocator.dupe(u8, name),
            .input = std.array_list.Managed(u8).init(self.allocator),
        });
    }

    /// Append to the current tool call input
    pub fn appendToolInput(self: *Self, id: []const u8, delta: []const u8) !void {
        for (self.tool_calls.items) |*tc| {
            if (std.mem.eql(u8, tc.id, id)) {
                try tc.input.appendSlice(delta);
                return;
            }
        }
    }

    /// Get tool calls
    pub fn getToolCalls(self: Self) []AccumulatedToolCall {
        return self.tool_calls.items;
    }
};

test "StreamCallbacks basic" {
    var received_items: usize = 0;
    var completed = false;

    const TestCallbacks = StreamCallbacks(i32);

    const callbacks = TestCallbacks{
        .on_item = struct {
            fn handler(ctx: ?*anyopaque, _: i32) void {
                const count: *usize = @ptrCast(@alignCast(ctx));
                count.* += 1;
            }
        }.handler,
        .on_error = struct {
            fn handler(_: ?*anyopaque, _: anyerror) void {}
        }.handler,
        .on_complete = struct {
            fn handler(ctx: ?*anyopaque) void {
                const flag: *bool = @ptrCast(@alignCast(ctx));
                flag.* = true;
            }
        }.handler,
        .ctx = &received_items,
    };

    callbacks.emit(1);
    callbacks.emit(2);
    callbacks.emit(3);

    // Change context for completion
    var callbacks_for_complete = callbacks;
    callbacks_for_complete.ctx = &completed;
    callbacks_for_complete.complete();

    try std.testing.expectEqual(@as(usize, 3), received_items);
    try std.testing.expect(completed);
}

test "StreamAccumulator" {
    const allocator = std.testing.allocator;

    var acc = StreamAccumulator.init(allocator);
    defer acc.deinit();

    try acc.appendText("Hello ");
    try acc.appendText("world!");

    try std.testing.expectEqualStrings("Hello world!", acc.getText());

    try acc.startToolCall("call-1", "search");
    try acc.appendToolInput("call-1", "{\"query\":");
    try acc.appendToolInput("call-1", "\"test\"}");

    try std.testing.expectEqual(@as(usize, 1), acc.getToolCalls().len);
    try std.testing.expectEqualStrings("search", acc.getToolCalls()[0].name);
    try std.testing.expectEqualStrings("{\"query\":\"test\"}", acc.getToolCalls()[0].input.items);
}

test "CallbackBuilder basic" {
    var item_count: usize = 0;
    var error_received = false;
    var complete_called = false;

    var builder = CallbackBuilder(i32).init();

    _ = builder.onItem(struct {
        fn handler(ctx: ?*anyopaque, _: i32) void {
            const count: *usize = @ptrCast(@alignCast(ctx));
            count.* += 1;
        }
    }.handler);

    _ = builder.onError(struct {
        fn handler(ctx: ?*anyopaque, _: anyerror) void {
            const flag: *bool = @ptrCast(@alignCast(ctx));
            flag.* = true;
        }
    }.handler);

    _ = builder.onComplete(struct {
        fn handler(ctx: ?*anyopaque) void {
            const flag: *bool = @ptrCast(@alignCast(ctx));
            flag.* = true;
        }
    }.handler);

    _ = builder.withContext(&item_count);

    const callbacks = builder.build();

    callbacks.emit(1);
    callbacks.emit(2);
    callbacks.emit(3);

    try std.testing.expectEqual(@as(usize, 3), item_count);

    // Change context for error
    var error_callbacks = callbacks;
    error_callbacks.ctx = &error_received;
    error_callbacks.fail(error.TestError);

    try std.testing.expect(error_received);

    // Change context for complete
    var complete_callbacks = callbacks;
    complete_callbacks.ctx = &complete_called;
    complete_callbacks.complete();

    try std.testing.expect(complete_called);
}

test "StreamCallbacks emit fail complete" {
    var items = std.array_list.Managed(i32).init(std.testing.allocator);
    defer items.deinit();

    var error_seen: ?anyerror = null;
    var complete_seen = false;

    const TestContext = struct {
        items: *std.array_list.Managed(i32),
        error_seen: *?anyerror,
        complete_seen: *bool,
    };

    var ctx = TestContext{
        .items = &items,
        .error_seen = &error_seen,
        .complete_seen = &complete_seen,
    };

    const callbacks = StreamCallbacks(i32){
        .on_item = struct {
            fn handler(context: ?*anyopaque, item: i32) void {
                const c: *TestContext = @ptrCast(@alignCast(context));
                c.items.append(item) catch @panic("OOM in test");
            }
        }.handler,
        .on_error = struct {
            fn handler(context: ?*anyopaque, err: anyerror) void {
                const c: *TestContext = @ptrCast(@alignCast(context));
                c.error_seen.* = err;
            }
        }.handler,
        .on_complete = struct {
            fn handler(context: ?*anyopaque) void {
                const c: *TestContext = @ptrCast(@alignCast(context));
                c.complete_seen.* = true;
            }
        }.handler,
        .ctx = &ctx,
    };

    callbacks.emit(10);
    callbacks.emit(20);
    callbacks.emit(30);

    try std.testing.expectEqual(@as(usize, 3), items.items.len);
    try std.testing.expectEqual(@as(i32, 10), items.items[0]);
    try std.testing.expectEqual(@as(i32, 20), items.items[1]);
    try std.testing.expectEqual(@as(i32, 30), items.items[2]);

    callbacks.fail(error.TestFailure);
    try std.testing.expect(error_seen != null);
    try std.testing.expectEqual(error.TestFailure, error_seen.?);

    callbacks.complete();
    try std.testing.expect(complete_seen);
}

test "StreamAccumulator multiple tool calls" {
    const allocator = std.testing.allocator;

    var acc = StreamAccumulator.init(allocator);
    defer acc.deinit();

    try acc.startToolCall("call-1", "search");
    try acc.startToolCall("call-2", "calculate");
    try acc.startToolCall("call-3", "translate");

    try acc.appendToolInput("call-1", "query1");
    try acc.appendToolInput("call-2", "expr1");
    try acc.appendToolInput("call-3", "text1");

    try acc.appendToolInput("call-1", " query2");
    try acc.appendToolInput("call-2", " expr2");

    try std.testing.expectEqual(@as(usize, 3), acc.getToolCalls().len);
    try std.testing.expectEqualStrings("search", acc.getToolCalls()[0].name);
    try std.testing.expectEqualStrings("calculate", acc.getToolCalls()[1].name);
    try std.testing.expectEqualStrings("translate", acc.getToolCalls()[2].name);

    try std.testing.expectEqualStrings("query1 query2", acc.getToolCalls()[0].input.items);
    try std.testing.expectEqualStrings("expr1 expr2", acc.getToolCalls()[1].input.items);
    try std.testing.expectEqualStrings("text1", acc.getToolCalls()[2].input.items);
}

test "StreamAccumulator empty" {
    const allocator = std.testing.allocator;

    var acc = StreamAccumulator.init(allocator);
    defer acc.deinit();

    try std.testing.expectEqualStrings("", acc.getText());
    try std.testing.expectEqual(@as(usize, 0), acc.getToolCalls().len);
}

test "StreamAccumulator append to nonexistent tool call" {
    const allocator = std.testing.allocator;

    var acc = StreamAccumulator.init(allocator);
    defer acc.deinit();

    try acc.startToolCall("call-1", "search");

    // Try to append to non-existent tool call (should not crash)
    try acc.appendToolInput("call-2", "data");

    try std.testing.expectEqual(@as(usize, 1), acc.getToolCalls().len);
    try std.testing.expectEqualStrings("", acc.getToolCalls()[0].input.items);
}

test "LanguageModelStreamCallbacks init" {
    var complete_called = false;

    const callbacks = LanguageModelStreamCallbacks.init(
        struct {
            fn onError(_: ?*anyopaque, _: anyerror) void {}
        }.onError,
        struct {
            fn onComplete(ctx: ?*anyopaque) void {
                const flag: *bool = @ptrCast(@alignCast(ctx));
                flag.* = true;
            }
        }.onComplete,
    );

    try std.testing.expect(callbacks.on_text_delta == null);
    try std.testing.expect(callbacks.on_tool_call_start == null);
    try std.testing.expect(callbacks.on_usage == null);

    var callbacks_with_ctx = callbacks;
    callbacks_with_ctx.ctx = &complete_called;
    callbacks_with_ctx.on_complete(callbacks_with_ctx.ctx);

    try std.testing.expect(complete_called);
}
