const std = @import("std");
const lm = @import("../../provider/src/language-model/v3/index.zig");
const shared = @import("../../provider/src/shared/v3/index.zig");

const config_mod = @import("groq-config.zig");
const options_mod = @import("groq-options.zig");
const map_finish = @import("map-groq-finish-reason.zig");

/// Groq Chat Language Model
/// Uses OpenAI-compatible API
pub const GroqChatLanguageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.GroqConfig,

    /// Create a new Groq chat language model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.GroqConfig,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .config = config,
        };
    }

    /// Get the model ID
    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    /// Get the provider name
    pub fn getProvider(self: *const Self) []const u8 {
        return self.config.provider;
    }

    /// Generate content (non-streaming)
    pub fn doGenerate(
        self: *Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?lm.LanguageModelV3.GenerateResult, ?anyerror, ?*anyopaque) void,
        callback_context: ?*anyopaque,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Build the request body (OpenAI format)
        const request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        // Build URL
        const url = config_mod.buildChatCompletionsUrl(
            request_allocator,
            self.config.base_url,
        ) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        // Get headers
        var headers = std.StringHashMap([]const u8).init(request_allocator);
        if (self.config.headers_fn) |headers_fn| {
            headers = headers_fn(&self.config);
        }

        // Serialize request body
        var body_buffer = std.ArrayList(u8).init(request_allocator);
        std.json.stringify(request_body, .{}, body_buffer.writer()) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        _ = url;
        _ = headers;

        // For now, return placeholder result
        const result = lm.LanguageModelV3.GenerateResult{
            .content = &[_]lm.LanguageModelV3Content{},
            .finish_reason = .stop,
            .usage = .{
                .prompt_tokens = 0,
                .completion_tokens = 0,
            },
            .warnings = &[_]shared.SharedV3Warning{},
        };

        _ = result_allocator;
        callback(result, null, callback_context);
    }

    /// Stream content
    pub fn doStream(
        self: *Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Build the request body with streaming enabled
        var request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callbacks.on_error(err, callbacks.context);
            return;
        };

        // Add stream flag
        if (request_body == .object) {
            request_body.object.put("stream", .{ .bool = true }) catch |err| {
                callbacks.on_error(err, callbacks.context);
                return;
            };
        }

        // Build URL
        const url = config_mod.buildChatCompletionsUrl(
            request_allocator,
            self.config.base_url,
        ) catch |err| {
            callbacks.on_error(err, callbacks.context);
            return;
        };

        _ = url;
        _ = result_allocator;

        // Emit stream start
        callbacks.on_part(.{ .stream_start = .{} }, callbacks.context);

        // For now, emit completion
        callbacks.on_part(.{
            .finish = .{
                .finish_reason = .stop,
                .usage = .{
                    .prompt_tokens = 0,
                    .completion_tokens = 0,
                },
            },
        }, callbacks.context);

        callbacks.on_complete(callbacks.context);
    }

    /// Build the request body (OpenAI format)
    fn buildRequestBody(
        self: *Self,
        allocator: std.mem.Allocator,
        call_options: lm.LanguageModelV3CallOptions,
    ) !std.json.Value {
        var body = std.json.ObjectMap.init(allocator);

        // Add model ID
        try body.put("model", .{ .string = self.model_id });

        // Build messages (OpenAI format)
        var messages = std.json.Array.init(allocator);

        for (call_options.prompt) |msg| {
            switch (msg.role) {
                .system => {
                    var message = std.json.ObjectMap.init(allocator);
                    try message.put("role", .{ .string = "system" });
                    try message.put("content", .{ .string = msg.content.system });
                    try messages.append(.{ .object = message });
                },
                .user => {
                    var message = std.json.ObjectMap.init(allocator);
                    try message.put("role", .{ .string = "user" });

                    var text_parts = std.ArrayList([]const u8).init(allocator);
                    for (msg.content.user) |part| {
                        switch (part) {
                            .text => |t| try text_parts.append(t.text),
                            else => {},
                        }
                    }
                    const joined = try std.mem.join(allocator, "", text_parts.items);
                    try message.put("content", .{ .string = joined });

                    try messages.append(.{ .object = message });
                },
                .assistant => {
                    var message = std.json.ObjectMap.init(allocator);
                    try message.put("role", .{ .string = "assistant" });

                    var text_content = std.ArrayList([]const u8).init(allocator);
                    var tool_calls = std.json.Array.init(allocator);

                    for (msg.content.assistant) |part| {
                        switch (part) {
                            .text => |t| try text_content.append(t.text),
                            .tool_call => |tc| {
                                var tool_call = std.json.ObjectMap.init(allocator);
                                try tool_call.put("id", .{ .string = tc.tool_call_id });
                                try tool_call.put("type", .{ .string = "function" });

                                var func = std.json.ObjectMap.init(allocator);
                                try func.put("name", .{ .string = tc.tool_name });
                                try func.put("arguments", .{ .string = tc.input });
                                try tool_call.put("function", .{ .object = func });

                                try tool_calls.append(.{ .object = tool_call });
                            },
                            else => {},
                        }
                    }

                    if (text_content.items.len > 0) {
                        const joined = try std.mem.join(allocator, "", text_content.items);
                        try message.put("content", .{ .string = joined });
                    }
                    if (tool_calls.items.len > 0) {
                        try message.put("tool_calls", .{ .array = tool_calls });
                    }

                    try messages.append(.{ .object = message });
                },
                .tool => {
                    for (msg.content.tool) |part| {
                        var message = std.json.ObjectMap.init(allocator);
                        try message.put("role", .{ .string = "tool" });
                        try message.put("tool_call_id", .{ .string = part.tool_call_id });

                        const output_text = switch (part.output) {
                            .text => |t| t.value,
                            .json => |j| try j.value.stringify(allocator),
                            .error_text => |e| e.value,
                            .error_json => |e| try e.value.stringify(allocator),
                            .execution_denied => |d| d.reason orelse "Execution denied",
                            .content => "Content output not yet supported",
                        };
                        try message.put("content", .{ .string = output_text });

                        try messages.append(.{ .object = message });
                    }
                },
            }
        }

        try body.put("messages", .{ .array = messages });

        // Add inference config
        if (call_options.max_output_tokens) |max_tokens| {
            try body.put("max_tokens", .{ .integer = @intCast(max_tokens) });
        }
        if (call_options.temperature) |temp| {
            try body.put("temperature", .{ .float = temp });
        }
        if (call_options.top_p) |top_p| {
            try body.put("top_p", .{ .float = top_p });
        }
        if (call_options.seed) |seed| {
            try body.put("seed", .{ .integer = @intCast(seed) });
        }

        // Add stop sequences
        if (call_options.stop_sequences) |stops| {
            var stops_array = std.json.Array.init(allocator);
            for (stops) |stop| {
                try stops_array.append(.{ .string = stop });
            }
            try body.put("stop", .{ .array = stops_array });
        }

        // Add tools if present (OpenAI format)
        if (call_options.tools) |tools| {
            var tools_array = std.json.Array.init(allocator);
            for (tools) |tool| {
                switch (tool) {
                    .function => |func| {
                        var tool_obj = std.json.ObjectMap.init(allocator);
                        try tool_obj.put("type", .{ .string = "function" });

                        var func_obj = std.json.ObjectMap.init(allocator);
                        try func_obj.put("name", .{ .string = func.name });
                        if (func.description) |desc| {
                            try func_obj.put("description", .{ .string = desc });
                        }
                        try func_obj.put("parameters", func.input_schema);

                        try tool_obj.put("function", .{ .object = func_obj });
                        try tools_array.append(.{ .object = tool_obj });
                    },
                    else => {},
                }
            }
            try body.put("tools", .{ .array = tools_array });
        }

        return .{ .object = body };
    }

    /// Convert to LanguageModelV3 interface
    pub fn asLanguageModel(self: *Self) lm.LanguageModelV3 {
        return .{
            .vtable = &vtable,
            .impl = self,
        };
    }

    const vtable = lm.LanguageModelV3.VTable{
        .doGenerate = doGenerateVtable,
        .doStream = doStreamVtable,
        .getModelId = getModelIdVtable,
        .getProvider = getProviderVtable,
    };

    fn doGenerateVtable(
        impl: *anyopaque,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?lm.LanguageModelV3.GenerateResult, ?anyerror, ?*anyopaque) void,
        callback_context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doGenerate(call_options, result_allocator, callback, callback_context);
    }

    fn doStreamVtable(
        impl: *anyopaque,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doStream(call_options, result_allocator, callbacks);
    }

    fn getModelIdVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getModelId();
    }

    fn getProviderVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getProvider();
    }
};

test "GroqChatLanguageModel init" {
    const allocator = std.testing.allocator;

    var model = GroqChatLanguageModel.init(
        allocator,
        "llama-3.3-70b-versatile",
        .{ .base_url = "https://api.groq.com/openai/v1" },
    );

    try std.testing.expectEqualStrings("llama-3.3-70b-versatile", model.getModelId());
    try std.testing.expectEqualStrings("groq", model.getProvider());
}

test "GroqChatLanguageModel init with custom config" {
    const allocator = std.testing.allocator;

    var model = GroqChatLanguageModel.init(
        allocator,
        "custom-model",
        .{
            .provider = "groq.custom",
            .base_url = "https://custom.groq.com",
        },
    );

    try std.testing.expectEqualStrings("custom-model", model.getModelId());
    try std.testing.expectEqualStrings("groq.custom", model.getProvider());
}

test "GroqChatLanguageModel getModelId and getProvider" {
    const allocator = std.testing.allocator;

    var model = GroqChatLanguageModel.init(
        allocator,
        "test-model-id",
        .{},
    );

    try std.testing.expectEqualStrings("test-model-id", model.getModelId());
    try std.testing.expectEqualStrings("groq", model.getProvider());
}

test "GroqChatLanguageModel asLanguageModel interface" {
    const allocator = std.testing.allocator;

    var model = GroqChatLanguageModel.init(
        allocator,
        "llama-3.3-70b-versatile",
        .{},
    );

    const lang_model = model.asLanguageModel();
    try std.testing.expect(lang_model.vtable.getModelId != null);
    try std.testing.expect(lang_model.vtable.getProvider != null);
    try std.testing.expect(lang_model.vtable.doGenerate != null);
    try std.testing.expect(lang_model.vtable.doStream != null);
}

test "GroqChatLanguageModel multiple instances with different models" {
    const allocator = std.testing.allocator;

    var model1 = GroqChatLanguageModel.init(allocator, "llama-3.3-70b-versatile", .{});
    var model2 = GroqChatLanguageModel.init(allocator, "llama-3.1-8b-instant", .{});
    var model3 = GroqChatLanguageModel.init(allocator, "gemma2-9b-it", .{});

    try std.testing.expectEqualStrings("llama-3.3-70b-versatile", model1.getModelId());
    try std.testing.expectEqualStrings("llama-3.1-8b-instant", model2.getModelId());
    try std.testing.expectEqualStrings("gemma2-9b-it", model3.getModelId());

    try std.testing.expectEqualStrings("groq", model1.getProvider());
    try std.testing.expectEqualStrings("groq", model2.getProvider());
    try std.testing.expectEqualStrings("groq", model3.getProvider());
}

test "GroqChatLanguageModel buildRequestBody with simple prompt" {
    const allocator = std.testing.allocator;

    var model = GroqChatLanguageModel.init(allocator, "test-model", .{});

    const prompt = [_]lm.LanguageModelV3Prompt{
        .{
            .role = .user,
            .content = .{
                .user = &[_]lm.LanguageModelV3Content{
                    .{ .text = .{ .text = "Hello" } },
                },
            },
        },
    };

    const call_options = lm.LanguageModelV3CallOptions{
        .prompt = &prompt,
        .max_output_tokens = null,
        .temperature = null,
        .top_p = null,
        .top_k = null,
        .seed = null,
        .max_retries = null,
        .abort_signal = null,
        .headers = null,
        .stop_sequences = null,
        .tools = null,
    };

    const request_body = try model.buildRequestBody(allocator, call_options);
    defer {
        if (request_body == .object) {
            request_body.object.deinit();
        }
    }

    try std.testing.expect(request_body == .object);
    const model_val = request_body.object.get("model");
    try std.testing.expect(model_val != null);
    try std.testing.expectEqualStrings("test-model", model_val.?.string);
}

test "GroqChatLanguageModel buildRequestBody with max_tokens" {
    const allocator = std.testing.allocator;

    var model = GroqChatLanguageModel.init(allocator, "test-model", .{});

    const prompt = [_]lm.LanguageModelV3Prompt{
        .{
            .role = .user,
            .content = .{
                .user = &[_]lm.LanguageModelV3Content{
                    .{ .text = .{ .text = "Hello" } },
                },
            },
        },
    };

    const call_options = lm.LanguageModelV3CallOptions{
        .prompt = &prompt,
        .max_output_tokens = 100,
        .temperature = null,
        .top_p = null,
        .top_k = null,
        .seed = null,
        .max_retries = null,
        .abort_signal = null,
        .headers = null,
        .stop_sequences = null,
        .tools = null,
    };

    const request_body = try model.buildRequestBody(allocator, call_options);
    defer {
        if (request_body == .object) {
            request_body.object.deinit();
        }
    }

    try std.testing.expect(request_body == .object);
    const max_tokens = request_body.object.get("max_tokens");
    try std.testing.expect(max_tokens != null);
    try std.testing.expectEqual(@as(i64, 100), max_tokens.?.integer);
}

test "GroqChatLanguageModel buildRequestBody with temperature and top_p" {
    const allocator = std.testing.allocator;

    var model = GroqChatLanguageModel.init(allocator, "test-model", .{});

    const prompt = [_]lm.LanguageModelV3Prompt{
        .{
            .role = .user,
            .content = .{
                .user = &[_]lm.LanguageModelV3Content{
                    .{ .text = .{ .text = "Hello" } },
                },
            },
        },
    };

    const call_options = lm.LanguageModelV3CallOptions{
        .prompt = &prompt,
        .max_output_tokens = null,
        .temperature = 0.7,
        .top_p = 0.9,
        .top_k = null,
        .seed = null,
        .max_retries = null,
        .abort_signal = null,
        .headers = null,
        .stop_sequences = null,
        .tools = null,
    };

    const request_body = try model.buildRequestBody(allocator, call_options);
    defer {
        if (request_body == .object) {
            request_body.object.deinit();
        }
    }

    try std.testing.expect(request_body == .object);

    const temperature = request_body.object.get("temperature");
    try std.testing.expect(temperature != null);
    try std.testing.expectEqual(@as(f64, 0.7), temperature.?.float);

    const top_p = request_body.object.get("top_p");
    try std.testing.expect(top_p != null);
    try std.testing.expectEqual(@as(f64, 0.9), top_p.?.float);
}

test "GroqChatLanguageModel buildRequestBody with seed" {
    const allocator = std.testing.allocator;

    var model = GroqChatLanguageModel.init(allocator, "test-model", .{});

    const prompt = [_]lm.LanguageModelV3Prompt{
        .{
            .role = .user,
            .content = .{
                .user = &[_]lm.LanguageModelV3Content{
                    .{ .text = .{ .text = "Hello" } },
                },
            },
        },
    };

    const call_options = lm.LanguageModelV3CallOptions{
        .prompt = &prompt,
        .max_output_tokens = null,
        .temperature = null,
        .top_p = null,
        .top_k = null,
        .seed = 42,
        .max_retries = null,
        .abort_signal = null,
        .headers = null,
        .stop_sequences = null,
        .tools = null,
    };

    const request_body = try model.buildRequestBody(allocator, call_options);
    defer {
        if (request_body == .object) {
            request_body.object.deinit();
        }
    }

    try std.testing.expect(request_body == .object);
    const seed = request_body.object.get("seed");
    try std.testing.expect(seed != null);
    try std.testing.expectEqual(@as(i64, 42), seed.?.integer);
}

test "GroqChatLanguageModel buildRequestBody with stop sequences" {
    const allocator = std.testing.allocator;

    var model = GroqChatLanguageModel.init(allocator, "test-model", .{});

    const prompt = [_]lm.LanguageModelV3Prompt{
        .{
            .role = .user,
            .content = .{
                .user = &[_]lm.LanguageModelV3Content{
                    .{ .text = .{ .text = "Hello" } },
                },
            },
        },
    };

    const stops = [_][]const u8{ "END", "STOP" };

    const call_options = lm.LanguageModelV3CallOptions{
        .prompt = &prompt,
        .max_output_tokens = null,
        .temperature = null,
        .top_p = null,
        .top_k = null,
        .seed = null,
        .max_retries = null,
        .abort_signal = null,
        .headers = null,
        .stop_sequences = &stops,
        .tools = null,
    };

    const request_body = try model.buildRequestBody(allocator, call_options);
    defer {
        if (request_body == .object) {
            request_body.object.deinit();
        }
    }

    try std.testing.expect(request_body == .object);
    const stop = request_body.object.get("stop");
    try std.testing.expect(stop != null);
    try std.testing.expect(stop.?.array.items.len == 2);
}

test "GroqChatLanguageModel buildRequestBody with system message" {
    const allocator = std.testing.allocator;

    var model = GroqChatLanguageModel.init(allocator, "test-model", .{});

    const prompt = [_]lm.LanguageModelV3Prompt{
        .{
            .role = .system,
            .content = .{ .system = "You are a helpful assistant" },
        },
        .{
            .role = .user,
            .content = .{
                .user = &[_]lm.LanguageModelV3Content{
                    .{ .text = .{ .text = "Hello" } },
                },
            },
        },
    };

    const call_options = lm.LanguageModelV3CallOptions{
        .prompt = &prompt,
        .max_output_tokens = null,
        .temperature = null,
        .top_p = null,
        .top_k = null,
        .seed = null,
        .max_retries = null,
        .abort_signal = null,
        .headers = null,
        .stop_sequences = null,
        .tools = null,
    };

    const request_body = try model.buildRequestBody(allocator, call_options);
    defer {
        if (request_body == .object) {
            request_body.object.deinit();
        }
    }

    try std.testing.expect(request_body == .object);
    const messages = request_body.object.get("messages");
    try std.testing.expect(messages != null);
    try std.testing.expect(messages.?.array.items.len == 2);

    const system_msg = messages.?.array.items[0].object.get("role");
    try std.testing.expectEqualStrings("system", system_msg.?.string);
}
