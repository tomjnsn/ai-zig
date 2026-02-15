const std = @import("std");

/// Server-Sent Events (SSE) parser for JSON event streams.
/// Parses text/event-stream format and extracts JSON data payloads.
pub const EventSourceParser = struct {
    buffer: std.ArrayList(u8),
    data_buffer: std.ArrayList(u8),
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
            .buffer = std.ArrayList(u8).empty,
            .data_buffer = std.ArrayList(u8).empty,
            .event_type = null,
            .has_data_field = false,
            .allocator = allocator,
            .max_buffer_size = max_buffer_size,
        };
    }

    /// Deinitialize the parser
    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
        self.data_buffer.deinit(self.allocator);
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
        // Check projected buffer size before appending to avoid unnecessary allocation.
        // Uses current + incoming to catch large chunks that would exceed the limit.
        if (self.max_buffer_size) |max_size| {
            if (self.buffer.items.len + data.len > max_size) {
                return error.BufferLimitExceeded;
            }
        }
        try self.buffer.appendSlice(self.allocator, data);

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
                    try self.data_buffer.append(self.allocator, '\n');
                }
                try self.data_buffer.appendSlice(self.allocator, value);
            }
            // Ignore 'id' and 'retry' fields for now
        }
    }
};

test "EventSourceParser basic" {
    const allocator = std.testing.allocator;

    var parser = EventSourceParser.init(allocator);
    defer parser.deinit();

    var events = std.ArrayList([]const u8).empty;
    defer {
        for (events.items) |e| allocator.free(e);
        events.deinit(allocator);
    }

    const TestContext = struct {
        events: *std.ArrayList([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const data = self.allocator.dupe(u8, event.data) catch return;
            self.events.append(self.allocator, data) catch {
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

    var events = std.ArrayList([]const u8).empty;
    defer {
        for (events.items) |e| allocator.free(e);
        events.deinit(allocator);
    }

    const TestContext = struct {
        events: *std.ArrayList([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const data = self.allocator.dupe(u8, event.data) catch return;
            self.events.append(self.allocator, data) catch {
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

    var events = std.ArrayList([]const u8).empty;
    defer {
        for (events.items) |e| allocator.free(e);
        events.deinit(allocator);
    }

    const TestContext = struct {
        events: *std.ArrayList([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const data = self.allocator.dupe(u8, event.data) catch return;
            self.events.append(self.allocator, data) catch {
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

    var event_types = std.ArrayList([]const u8).empty;
    defer {
        for (event_types.items) |e| allocator.free(e);
        event_types.deinit(allocator);
    }

    const TestContext = struct {
        event_types: *std.ArrayList([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (event.event_type) |et| {
                const event_type = self.allocator.dupe(u8, et) catch return;
                self.event_types.append(self.allocator, event_type) catch {
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

    var events = std.ArrayList([]const u8).empty;
    defer {
        for (events.items) |e| allocator.free(e);
        events.deinit(allocator);
    }

    const TestContext = struct {
        events: *std.ArrayList([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const data = self.allocator.dupe(u8, event.data) catch return;
            self.events.append(self.allocator, data) catch {
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

    var events = std.ArrayList([]const u8).empty;
    defer {
        for (events.items) |e| allocator.free(e);
        events.deinit(allocator);
    }

    const TestContext = struct {
        events: *std.ArrayList([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const data = self.allocator.dupe(u8, event.data) catch return;
            self.events.append(self.allocator, data) catch {
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

    var events = std.ArrayList([]const u8).empty;
    defer {
        for (events.items) |e| allocator.free(e);
        events.deinit(allocator);
    }

    const TestContext = struct {
        events: *std.ArrayList([]const u8),
        allocator: std.mem.Allocator,

        fn handler(ctx: ?*anyopaque, event: EventSourceParser.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const data = self.allocator.dupe(u8, event.data) catch return;
            self.events.append(self.allocator, data) catch {
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
