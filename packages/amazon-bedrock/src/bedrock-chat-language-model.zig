const std = @import("std");
const lm = @import("../../provider/src/language-model/v3/index.zig");
const shared = @import("../../provider/src/shared/v3/index.zig");
const provider_utils = @import("provider-utils");

const config_mod = @import("bedrock-config.zig");
const options_mod = @import("bedrock-options.zig");
const map_finish = @import("map-bedrock-finish-reason.zig");

/// Amazon Bedrock Chat Language Model
pub const BedrockChatLanguageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.BedrockConfig,

    /// Create a new Bedrock chat language model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.BedrockConfig,
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

        // Build the request body
        const request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        // Build URL
        const url = config_mod.buildConverseUrl(
            request_allocator,
            self.config.base_url,
            self.model_id,
        ) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        // Get headers
        var headers = std.StringHashMap([]const u8).init(request_allocator);
        if (self.config.headers_fn) |headers_fn| {
            headers = headers_fn(&self.config, request_allocator) catch |err| {
                callback(null, err, callback_context);
                return;
            };
        }

        // Serialize request body
        var body_buffer = std.array_list.Managed(u8).init(request_allocator);
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

        // Build the request body
        const request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callbacks.on_error(err, callbacks.context);
            return;
        };

        // Build URL
        const url = config_mod.buildConverseStreamUrl(
            request_allocator,
            self.config.base_url,
            self.model_id,
        ) catch |err| {
            callbacks.on_error(err, callbacks.context);
            return;
        };

        _ = url;
        _ = request_body;
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

    /// Build the request body for the Converse API
    fn buildRequestBody(
        self: *Self,
        allocator: std.mem.Allocator,
        call_options: lm.LanguageModelV3CallOptions,
    ) !std.json.Value {
        var body = std.json.ObjectMap.init(allocator);

        // Add model ID
        try body.put("modelId", .{ .string = self.model_id });

        // Build messages
        var messages = std.json.Array.init(allocator);
        var system_content: ?[]const u8 = null;

        for (call_options.prompt) |msg| {
            switch (msg.role) {
                .system => {
                    system_content = msg.content.system;
                },
                .user => {
                    var message = std.json.ObjectMap.init(allocator);
                    try message.put("role", .{ .string = "user" });

                    var content = std.json.Array.init(allocator);
                    for (msg.content.user) |part| {
                        switch (part) {
                            .text => |t| {
                                var text_obj = std.json.ObjectMap.init(allocator);
                                try text_obj.put("text", .{ .string = t.text });
                                try content.append(.{ .object = text_obj });
                            },
                            .file => |f| {
                                if (f.media_type) |mt| {
                                    if (std.mem.startsWith(u8, mt, "image/")) {
                                        var image_obj = std.json.ObjectMap.init(allocator);
                                        var source = std.json.ObjectMap.init(allocator);

                                        switch (f.data) {
                                            .base64 => |data| {
                                                try source.put("bytes", .{ .string = data });
                                            },
                                            else => {},
                                        }

                                        try image_obj.put("format", .{ .string = std.mem.trimLeft(u8, mt, "image/") });
                                        try image_obj.put("source", .{ .object = source });

                                        var wrapper = std.json.ObjectMap.init(allocator);
                                        try wrapper.put("image", .{ .object = image_obj });
                                        try content.append(.{ .object = wrapper });
                                    }
                                }
                            },
                        }
                    }

                    try message.put("content", .{ .array = content });
                    try messages.append(.{ .object = message });
                },
                .assistant => {
                    var message = std.json.ObjectMap.init(allocator);
                    try message.put("role", .{ .string = "assistant" });

                    var content = std.json.Array.init(allocator);
                    for (msg.content.assistant) |part| {
                        switch (part) {
                            .text => |t| {
                                var text_obj = std.json.ObjectMap.init(allocator);
                                try text_obj.put("text", .{ .string = t.text });
                                try content.append(.{ .object = text_obj });
                            },
                            .tool_call => |tc| {
                                var tool_use = std.json.ObjectMap.init(allocator);
                                try tool_use.put("toolUseId", .{ .string = tc.tool_call_id });
                                try tool_use.put("name", .{ .string = tc.tool_name });

                                const parsed = try std.json.parseFromSlice(std.json.Value, allocator, tc.input, .{});
                                try tool_use.put("input", parsed.value);

                                var wrapper = std.json.ObjectMap.init(allocator);
                                try wrapper.put("toolUse", .{ .object = tool_use });
                                try content.append(.{ .object = wrapper });
                            },
                            else => {},
                        }
                    }

                    try message.put("content", .{ .array = content });
                    try messages.append(.{ .object = message });
                },
                .tool => {
                    var message = std.json.ObjectMap.init(allocator);
                    try message.put("role", .{ .string = "user" });

                    var content = std.json.Array.init(allocator);
                    for (msg.content.tool) |part| {
                        var tool_result = std.json.ObjectMap.init(allocator);
                        try tool_result.put("toolUseId", .{ .string = part.tool_call_id });

                        const output_text = switch (part.output) {
                            .text => |t| t.value,
                            .json => |j| try j.value.stringify(allocator),
                            .error_text => |e| e.value,
                            .error_json => |e| try e.value.stringify(allocator),
                            .execution_denied => |d| d.reason orelse "Execution denied",
                            .content => "Content output not yet supported",
                        };

                        var result_content = std.json.Array.init(allocator);
                        var text_obj = std.json.ObjectMap.init(allocator);
                        try text_obj.put("text", .{ .string = output_text });
                        try result_content.append(.{ .object = text_obj });
                        try tool_result.put("content", .{ .array = result_content });

                        // Check for error
                        switch (part.output) {
                            .error_text, .error_json, .execution_denied => {
                                try tool_result.put("status", .{ .string = "error" });
                            },
                            else => {},
                        }

                        var wrapper = std.json.ObjectMap.init(allocator);
                        try wrapper.put("toolResult", .{ .object = tool_result });
                        try content.append(.{ .object = wrapper });
                    }

                    try message.put("content", .{ .array = content });
                    try messages.append(.{ .object = message });
                },
            }
        }

        try body.put("messages", .{ .array = messages });

        // Add system prompt
        if (system_content) |sys| {
            var system_array = std.json.Array.init(allocator);
            var sys_obj = std.json.ObjectMap.init(allocator);
            try sys_obj.put("text", .{ .string = sys });
            try system_array.append(.{ .object = sys_obj });
            try body.put("system", .{ .array = system_array });
        }

        // Add inference config
        var inference_config = std.json.ObjectMap.init(allocator);

        if (call_options.max_output_tokens) |max_tokens| {
            try inference_config.put("maxTokens", .{ .integer = try provider_utils.safeCast(i64, max_tokens) });
        }
        if (call_options.temperature) |temp| {
            try inference_config.put("temperature", .{ .float = temp });
        }
        if (call_options.top_p) |top_p| {
            try inference_config.put("topP", .{ .float = top_p });
        }
        if (call_options.stop_sequences) |stops| {
            var stops_array = std.json.Array.init(allocator);
            for (stops) |stop| {
                try stops_array.append(.{ .string = stop });
            }
            try inference_config.put("stopSequences", .{ .array = stops_array });
        }

        if (inference_config.count() > 0) {
            try body.put("inferenceConfig", .{ .object = inference_config });
        }

        // Add tools if present
        if (call_options.tools) |tools| {
            var tool_config = std.json.ObjectMap.init(allocator);
            var tools_array = std.json.Array.init(allocator);

            for (tools) |tool| {
                switch (tool) {
                    .function => |func| {
                        var tool_spec = std.json.ObjectMap.init(allocator);
                        try tool_spec.put("name", .{ .string = func.name });
                        if (func.description) |desc| {
                            try tool_spec.put("description", .{ .string = desc });
                        }
                        try tool_spec.put("inputSchema", func.input_schema);

                        var tool_obj = std.json.ObjectMap.init(allocator);
                        try tool_obj.put("toolSpec", .{ .object = tool_spec });
                        try tools_array.append(.{ .object = tool_obj });
                    },
                    else => {},
                }
            }

            try tool_config.put("tools", .{ .array = tools_array });
            try body.put("toolConfig", .{ .object = tool_config });
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

test "BedrockChatLanguageModel init" {
    const allocator = std.testing.allocator;

    var model = BedrockChatLanguageModel.init(
        allocator,
        "anthropic.claude-3-5-sonnet-20241022-v2:0",
        .{ .base_url = "https://bedrock-runtime.us-east-1.amazonaws.com" },
    );

    try std.testing.expectEqualStrings("anthropic.claude-3-5-sonnet-20241022-v2:0", model.getModelId());
    try std.testing.expectEqualStrings("bedrock", model.getProvider());
}
