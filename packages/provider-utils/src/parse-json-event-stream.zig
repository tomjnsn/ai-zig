const std = @import("std");
const json_value = @import("provider").json_value;
const parse_json = @import("parse-json.zig");

/// Server-Sent Events (SSE) parser for JSON event streams.
/// Parses text/event-stream format and extracts JSON data payloads.
pub const EventSourceParser = struct {
    buffer: std.array_list.Managed(u8),
    data_buffer: std.array_list.Managed(u8),
    event_type: ?[]const u8,
    has_data_field: bool,
    allocator: std.mem.Allocator,
    /// Maximum buffer size in bytes. null = no limit.
    max_buffer_size: ?usize,

    const Self = @This();

    /// Initialize a new event source parser with no buffer limit
    pub fn init(allocator: std.mem.Allocator) Self {
        return initWithMaxBuffer(allocator, null);
    }

    /// Initialize a new event source parser with a maximum buffer size
    pub fn initWithMaxBuffer(allocator: std.mem.Allocator, max_buffer_size: ?usize) Self {
        return .{
            .buffer = std.array_list.Managed(u8).init(allocator),
            .data_buffer = std.array_list.Managed(u8).init(allocator),
            .event_type = null,
            .has_data_field = false,
            .allocator = allocator,
            .max_buffer_size = max_buffer_size,
        };
    }

    /// Deinitialize the parser
    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.data_buffer.deinit();
        if (self.event_type) |et| {
            self.allocator.free(et);
        }
    }

    /// Reset the parser state for reuse
    pub fn reset(self: *Self) void {
        self.buffer.clearRetainingCapacity();
        self.data_buffer.clearRetainingCapacity();
        self.has_data_field = false;
        if (self.event_type) |et| {
            self.allocator.free(et);
            self.event_type = null;
        }
    }

    /// Event parsed from the stream
    pub const Event = struct {
        event_type: ?[]const u8,
        data: []const u8,
    };

    /// Feed data to the parser and emit events via callback
    pub fn feed(
        self: *Self,
        data: []const u8,
        on_event: *const fn (ctx: ?*anyopaque, event: Event) void,
        ctx: ?*anyopaque,
    ) !void {
        // Check buffer size limit before appending
        if (self.max_buffer_size) |max_size| {
            if (self.buffer.items.len + data.len > max_size) {
                return error.BufferLimitExceeded;
            }
        }
        try self.buffer.appendSlice(data);

        // Process complete lines
        while (self.findLineEnd()) |line_info| {
            const line = self.buffer.items[0..line_info.end];
            try self.processLine(line, on_event, ctx);

            // Remove processed line from buffer
            const remove_len = line_info.end + line_info.newline_len;
            if (remove_len < self.buffer.items.len) {
                std.mem.copyForwards(
                    u8,
                    self.buffer.items[0 .. self.buffer.items.len - remove_len],
                    self.buffer.items[remove_len..],
                );
            }
            self.buffer.shrinkRetainingCapacity(self.buffer.items.len - remove_len);
        }
    }

    const LineEnd = struct {
        end: usize,
        newline_len: usize,
    };

    fn findLineEnd(self: *Self) ?LineEnd {
        for (self.buffer.items, 0..) |char, i| {
            if (char == '\n') {
                // Check for \r\n
                if (i > 0 and self.buffer.items[i - 1] == '\r') {
                    return .{ .end = i - 1, .newline_len = 2 };
                }
                return .{ .end = i, .newline_len = 1 };
            }
            if (char == '\r') {
                // Standalone \r (old Mac style)
                if (i + 1 >= self.buffer.items.len or self.buffer.items[i + 1] != '\n') {
                    return .{ .end = i, .newline_len = 1 };
                }
            }
        }
        return null;
    }

    fn processLine(
        self: *Self,
        line: []const u8,
        on_event: *const fn (ctx: ?*anyopaque, event: Event) void,
        ctx: ?*anyopaque,
    ) !void {
        // Empty line = dispatch event
        if (line.len == 0) {
            if (self.has_data_field) {
                // Skip [DONE] events (OpenAI convention)
                if (!std.mem.eql(u8, self.data_buffer.items, "[DONE]")) {
                    on_event(ctx, .{
                        .event_type = self.event_type,
                        .data = self.data_buffer.items,
                    });
                }
                self.data_buffer.clearRetainingCapacity();
                self.has_data_field = false;
                if (self.event_type) |et| {
                    self.allocator.free(et);
                    self.event_type = null;
                }
            }
            return;
        }

        // Skip comments
        if (line[0] == ':') {
            return;
        }

        // Parse field:value
        if (std.mem.indexOfScalar(u8, line, ':')) |colon_idx| {
            const field = line[0..colon_idx];
            var value = line[colon_idx + 1 ..];

            // Skip leading space after colon
            if (value.len > 0 and value[0] == ' ') {
                value = value[1..];
            }

            if (std.mem.eql(u8, field, "event")) {
                if (self.event_type) |et| {
                    self.allocator.free(et);
                }
                self.event_type = try self.allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, field, "data")) {
                self.has_data_field = true;
                if (self.data_buffer.items.len > 0) {
                    try self.data_buffer.append('\n');
                }
                try self.data_buffer.appendSlice(value);
            }
            // Ignore 'id' and 'retry' fields for now
        }
    }
};

/// Parse a JSON event stream, calling the callback for each parsed JSON event.
pub fn parseJsonEventStream(
    comptime T: type,
    allocator: std.mem.Allocator,
    on_event: *const fn (ctx: ?*anyopaque, result: ParseEventResult(T)) void,
    ctx: ?*anyopaque,
) JsonEventStreamParser(T) {
    return JsonEventStreamParser(T).init(allocator, on_event, ctx);
}

/// Result of parsing a JSON event
pub fn ParseEventResult(comptime T: type) type {
    return union(enum) {
        success: struct {
            value: T,
            raw: []const u8,
        },
        failure: struct {
            message: []const u8,
            raw: []const u8,
        },
    };
}

/// JSON event stream parser that parses SSE events and extracts JSON data
pub fn JsonEventStreamParser(comptime T: type) type {
    return struct {
        sse_parser: EventSourceParser,
        on_event: *const fn (ctx: ?*anyopaque, result: ParseEventResult(T)) void,
        ctx: ?*anyopaque,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(
            allocator: std.mem.Allocator,
            on_event: *const fn (ctx: ?*anyopaque, result: ParseEventResult(T)) void,
            ctx: ?*anyopaque,
        ) Self {
            return .{
                .sse_parser = EventSourceParser.init(allocator),
                .on_event = on_event,
                .ctx = ctx,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.sse_parser.deinit();
        }

        /// Feed data to the parser
        pub fn feed(self: *Self, data: []const u8) !void {
            try self.sse_parser.feed(data, handleEvent, self);
        }

        fn handleEvent(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *Self = @ptrCast(@alignCast(ctx));

            // Parse the JSON data
            const parse_result = parse_json.safeParseJson(event.data, self.allocator);

            switch (parse_result) {
                .success => |parsed| {
                    // In a full implementation, you'd convert parsed to T
                    _ = parsed;
                    self.on_event(self.ctx, .{
                        .failure = .{
                            .message = "Type conversion not implemented",
                            .raw = event.data,
                        },
                    });
                },
                .failure => |err| {
                    self.on_event(self.ctx, .{
                        .failure = .{
                            .message = err.message,
                            .raw = event.data,
                        },
                    });
                },
            }
        }
    };
}

/// Streaming callbacks for JSON event streams
pub const JsonEventStreamCallbacks = struct {
    on_event: *const fn (ctx: ?*anyopaque, data: json_value.JsonValue) void,
    on_error: *const fn (ctx: ?*anyopaque, message: []const u8, raw: []const u8) void,
    on_complete: *const fn (ctx: ?*anyopaque) void,
    ctx: ?*anyopaque = null,
};

/// Simple JSON event stream processor that doesn't require type parameter
pub const SimpleJsonEventStreamParser = struct {
    sse_parser: EventSourceParser,
    callbacks: JsonEventStreamCallbacks,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        callbacks: JsonEventStreamCallbacks,
    ) Self {
        return .{
            .sse_parser = EventSourceParser.init(allocator),
            .callbacks = callbacks,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.sse_parser.deinit();
    }

    pub fn feed(self: *Self, data: []const u8) !void {
        try self.sse_parser.feed(data, handleEvent, self);
    }

    pub fn complete(self: *Self) void {
        self.callbacks.on_complete(self.callbacks.ctx);
    }

    fn handleEvent(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const parse_result = parse_json.safeParseJson(event.data, self.allocator);

        switch (parse_result) {
            .success => |parsed| {
                self.callbacks.on_event(self.callbacks.ctx, parsed);
            },
            .failure => |err| {
                self.callbacks.on_error(self.callbacks.ctx, err.message, event.data);
            },
        }
    }
};

test "EventSourceParser basic" {
    const allocator = std.testing.allocator;

    var parser = EventSourceParser.init(allocator);
    defer parser.deinit();

    var events = std.array_list.Managed([]const u8).init(allocator);
    defer {
        for (events.items) |e| allocator.free(e);
        events.deinit();
    }

    const TestContext = struct {
        events: *std.array_list.Managed([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const data = self.allocator.dupe(u8, event.data) catch return;
            self.events.append(data) catch {
                self.allocator.free(data);
            };
        }
    };

    var test_ctx = TestContext{
        .events = &events,
        .allocator = allocator,
    };

    try parser.feed("data: {\"text\": \"hello\"}\n\n", TestContext.handler, &test_ctx);

    try std.testing.expectEqual(@as(usize, 1), events.items.len);
    try std.testing.expectEqualStrings("{\"text\": \"hello\"}", events.items[0]);
}

test "EventSourceParser ignores DONE" {
    const allocator = std.testing.allocator;

    var parser = EventSourceParser.init(allocator);
    defer parser.deinit();

    var event_count: usize = 0;

    try parser.feed("data: [DONE]\n\n", struct {
        fn handler(_: ?*anyopaque, _: EventSourceParser.Event) void {
            // This should not be called for [DONE]
            unreachable;
        }
    }.handler, &event_count);

    try std.testing.expectEqual(@as(usize, 0), event_count);
}

test "EventSourceParser multiple events" {
    const allocator = std.testing.allocator;

    var parser = EventSourceParser.init(allocator);
    defer parser.deinit();

    var events = std.array_list.Managed([]const u8).init(allocator);
    defer {
        for (events.items) |e| allocator.free(e);
        events.deinit();
    }

    const TestContext = struct {
        events: *std.array_list.Managed([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const data = self.allocator.dupe(u8, event.data) catch return;
            self.events.append(data) catch {
                self.allocator.free(data);
            };
        }
    };

    var test_ctx = TestContext{
        .events = &events,
        .allocator = allocator,
    };

    const stream_data =
        \\data: {"id":1}
        \\
        \\data: {"id":2}
        \\
        \\data: {"id":3}
        \\
        \\
    ;

    try parser.feed(stream_data, TestContext.handler, &test_ctx);

    try std.testing.expectEqual(@as(usize, 3), events.items.len);
    try std.testing.expectEqualStrings("{\"id\":1}", events.items[0]);
    try std.testing.expectEqualStrings("{\"id\":2}", events.items[1]);
    try std.testing.expectEqualStrings("{\"id\":3}", events.items[2]);
}

test "EventSourceParser multiline data" {
    const allocator = std.testing.allocator;

    var parser = EventSourceParser.init(allocator);
    defer parser.deinit();

    var events = std.array_list.Managed([]const u8).init(allocator);
    defer {
        for (events.items) |e| allocator.free(e);
        events.deinit();
    }

    const TestContext = struct {
        events: *std.array_list.Managed([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const data = self.allocator.dupe(u8, event.data) catch return;
            self.events.append(data) catch {
                self.allocator.free(data);
            };
        }
    };

    var test_ctx = TestContext{
        .events = &events,
        .allocator = allocator,
    };

    const stream_data =
        \\data: line 1
        \\data: line 2
        \\data: line 3
        \\
        \\
    ;

    try parser.feed(stream_data, TestContext.handler, &test_ctx);

    try std.testing.expectEqual(@as(usize, 1), events.items.len);
    try std.testing.expectEqualStrings("line 1\nline 2\nline 3", events.items[0]);
}

test "EventSourceParser with event types" {
    const allocator = std.testing.allocator;

    var parser = EventSourceParser.init(allocator);
    defer parser.deinit();

    var event_types = std.array_list.Managed([]const u8).init(allocator);
    defer {
        for (event_types.items) |e| allocator.free(e);
        event_types.deinit();
    }

    const TestContext = struct {
        event_types: *std.array_list.Managed([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (event.event_type) |et| {
                const event_type = self.allocator.dupe(u8, et) catch return;
                self.event_types.append(event_type) catch {
                    self.allocator.free(event_type);
                };
            }
        }
    };

    var test_ctx = TestContext{
        .event_types = &event_types,
        .allocator = allocator,
    };

    const stream_data =
        \\event: message
        \\data: {"text":"hello"}
        \\
        \\event: error
        \\data: {"error":"failed"}
        \\
        \\
    ;

    try parser.feed(stream_data, TestContext.handler, &test_ctx);

    try std.testing.expectEqual(@as(usize, 2), event_types.items.len);
    try std.testing.expectEqualStrings("message", event_types.items[0]);
    try std.testing.expectEqualStrings("error", event_types.items[1]);
}

test "EventSourceParser ignores comments" {
    const allocator = std.testing.allocator;

    var parser = EventSourceParser.init(allocator);
    defer parser.deinit();

    var event_count: usize = 0;

    const stream_data =
        \\: this is a comment
        \\data: real data
        \\: another comment
        \\
        \\
    ;

    try parser.feed(stream_data, struct {
        fn handler(ctx: ?*anyopaque, _: EventSourceParser.Event) void {
            const count: *usize = @ptrCast(@alignCast(ctx));
            count.* += 1;
        }
    }.handler, &event_count);

    try std.testing.expectEqual(@as(usize, 1), event_count);
}

test "EventSourceParser different line endings" {
    const allocator = std.testing.allocator;

    var parser = EventSourceParser.init(allocator);
    defer parser.deinit();

    var events = std.array_list.Managed([]const u8).init(allocator);
    defer {
        for (events.items) |e| allocator.free(e);
        events.deinit();
    }

    const TestContext = struct {
        events: *std.array_list.Managed([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const data = self.allocator.dupe(u8, event.data) catch return;
            self.events.append(data) catch {
                self.allocator.free(data);
            };
        }
    };

    var test_ctx = TestContext{
        .events = &events,
        .allocator = allocator,
    };

    // Test \r\n (Windows)
    try parser.feed("data: test1\r\n\r\n", TestContext.handler, &test_ctx);

    // Test \n (Unix)
    try parser.feed("data: test2\n\n", TestContext.handler, &test_ctx);

    try std.testing.expectEqual(@as(usize, 2), events.items.len);
}

test "EventSourceParser chunked input" {
    const allocator = std.testing.allocator;

    var parser = EventSourceParser.init(allocator);
    defer parser.deinit();

    var events = std.array_list.Managed([]const u8).init(allocator);
    defer {
        for (events.items) |e| allocator.free(e);
        events.deinit();
    }

    const TestContext = struct {
        events: *std.array_list.Managed([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const data = self.allocator.dupe(u8, event.data) catch return;
            self.events.append(data) catch {
                self.allocator.free(data);
            };
        }
    };

    var test_ctx = TestContext{
        .events = &events,
        .allocator = allocator,
    };

    // Feed data in small chunks
    try parser.feed("data: ", TestContext.handler, &test_ctx);
    try parser.feed("hello", TestContext.handler, &test_ctx);
    try parser.feed(" world", TestContext.handler, &test_ctx);
    try parser.feed("\n", TestContext.handler, &test_ctx);
    try parser.feed("\n", TestContext.handler, &test_ctx);

    try std.testing.expectEqual(@as(usize, 1), events.items.len);
    try std.testing.expectEqualStrings("hello world", events.items[0]);
}

test "EventSourceParser reset" {
    const allocator = std.testing.allocator;

    var parser = EventSourceParser.init(allocator);
    defer parser.deinit();

    var event_count: usize = 0;

    try parser.feed("data: test\n\n", struct {
        fn handler(ctx: ?*anyopaque, _: EventSourceParser.Event) void {
            const count: *usize = @ptrCast(@alignCast(ctx));
            count.* += 1;
        }
    }.handler, &event_count);

    try std.testing.expectEqual(@as(usize, 1), event_count);

    parser.reset();
    event_count = 0;

    try parser.feed("data: test2\n\n", struct {
        fn handler(ctx: ?*anyopaque, _: EventSourceParser.Event) void {
            const count: *usize = @ptrCast(@alignCast(ctx));
            count.* += 1;
        }
    }.handler, &event_count);

    try std.testing.expectEqual(@as(usize, 1), event_count);
}

test "EventSourceParser empty data field" {
    const allocator = std.testing.allocator;

    var parser = EventSourceParser.init(allocator);
    defer parser.deinit();

    var events = std.array_list.Managed([]const u8).init(allocator);
    defer {
        for (events.items) |e| allocator.free(e);
        events.deinit();
    }

    const TestContext = struct {
        events: *std.array_list.Managed([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const data = self.allocator.dupe(u8, event.data) catch return;
            self.events.append(data) catch {
                self.allocator.free(data);
            };
        }
    };

    var test_ctx = TestContext{
        .events = &events,
        .allocator = allocator,
    };

    try parser.feed("data:\n\n", TestContext.handler, &test_ctx);

    try std.testing.expectEqual(@as(usize, 1), events.items.len);
    try std.testing.expectEqualStrings("", events.items[0]);
}

test "rejects event stream exceeding buffer limit" {
    const allocator = std.testing.allocator;

    var parser = EventSourceParser.initWithMaxBuffer(allocator, 64);
    defer parser.deinit();

    var event_count: usize = 0;

    // Feed data that exceeds the buffer limit (no newline so it accumulates)
    const chunk = "data: " ++ "x" ** 70;
    const result = parser.feed(chunk, struct {
        fn handler(ctx: ?*anyopaque, _: EventSourceParser.Event) void {
            const count: *usize = @ptrCast(@alignCast(ctx));
            count.* += 1;
        }
    }.handler, &event_count);

    try std.testing.expectError(error.BufferLimitExceeded, result);
    try std.testing.expectEqual(@as(usize, 0), event_count);
}

test "SimpleJsonEventStreamParser basic" {
    const allocator = std.testing.allocator;

    var received_events = std.array_list.Managed(json_value.JsonValue).init(allocator);
    defer {
        for (received_events.items) |*event| {
            event.deinit(allocator);
        }
        received_events.deinit();
    }

    var error_count: usize = 0;
    var complete_called = false;

    const TestContext = struct {
        events: *std.array_list.Managed(json_value.JsonValue),
        error_count: *usize,
        complete_called: *bool,
        allocator: std.mem.Allocator,
    };

    var test_ctx = TestContext{
        .events = &received_events,
        .error_count = &error_count,
        .complete_called = &complete_called,
        .allocator = allocator,
    };

    var parser = SimpleJsonEventStreamParser.init(allocator, .{
        .on_event = struct {
            fn handler(ctx: ?*anyopaque, data: json_value.JsonValue) void {
                const self: *TestContext = @ptrCast(@alignCast(ctx));
                self.events.append(data) catch {};
            }
        }.handler,
        .on_error = struct {
            fn handler(ctx: ?*anyopaque, _: []const u8, _: []const u8) void {
                const self: *TestContext = @ptrCast(@alignCast(ctx));
                self.error_count.* += 1;
            }
        }.handler,
        .on_complete = struct {
            fn handler(ctx: ?*anyopaque) void {
                const self: *TestContext = @ptrCast(@alignCast(ctx));
                self.complete_called.* = true;
            }
        }.handler,
        .ctx = &test_ctx,
    });
    defer parser.deinit();

    try parser.feed("data: {\"text\":\"hello\"}\n\n");
    try parser.feed("data: {\"text\":\"world\"}\n\n");
    parser.complete();

    try std.testing.expectEqual(@as(usize, 2), received_events.items.len);
    try std.testing.expectEqual(@as(usize, 0), error_count);
    try std.testing.expect(complete_called);
}
