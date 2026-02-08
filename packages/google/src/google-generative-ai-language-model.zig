const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");

const config_mod = @import("google-config.zig");
const options_mod = @import("google-generative-ai-options.zig");
const convert = @import("convert-to-google-generative-ai-messages.zig");
const prepare_tools = @import("google-prepare-tools.zig");
const map_finish = @import("map-google-generative-ai-finish-reason.zig");
const response_types = @import("google-generative-ai-response.zig");

/// Google Generative AI Language Model
pub const GoogleGenerativeAILanguageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.GoogleGenerativeAIConfig,

    /// Create a new Google Generative AI language model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.GoogleGenerativeAIConfig,
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

    /// Get the model path for API calls
    pub fn getModelPath(self: *const Self) []const u8 {
        // For tuned models, use the full path
        if (std.mem.startsWith(u8, self.model_id, "tunedModels/")) {
            return self.model_id;
        }
        return self.model_id;
    }

    /// Generate content (non-streaming)
    pub fn doGenerate(
        self: *const Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, lm.LanguageModelV3.GenerateResult) void,
        callback_context: ?*anyopaque,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Build the request
        const request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Make the API call
        const url = std.fmt.allocPrint(
            request_allocator,
            "{s}/models/{s}:generateContent",
            .{ self.config.base_url, self.getModelPath() },
        ) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Get headers
        var headers = if (self.config.headers_fn) |headers_fn|
            headers_fn(&self.config, request_allocator)
        else
            std.StringHashMap([]const u8).init(request_allocator);

        // Ensure content-type is set
        headers.put("Content-Type", "application/json") catch {};

        // Serialize request body
        var body_buffer = std.ArrayList(u8).init(request_allocator);
        std.json.stringify(request_body, .{}, body_buffer.writer()) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Get HTTP client
        const http_client = self.config.http_client orelse {
            callback(callback_context, .{ .failure = error.NoHttpClient });
            return;
        };

        // Convert headers to slice
        var header_list = std.ArrayList(provider_utils.HttpHeader).init(request_allocator);
        var header_iter = headers.iterator();
        while (header_iter.next()) |entry| {
            header_list.append(.{
                .name = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            }) catch {};
        }

        // Create context for callback
        const ResponseContext = struct {
            response_body: ?[]const u8 = null,
            response_error: ?provider_utils.HttpError = null,
        };
        var response_ctx = ResponseContext{};

        // Make HTTP request
        http_client.request(
            .{
                .method = .POST,
                .url = url,
                .headers = header_list.items,
                .body = body_buffer.items,
            },
            request_allocator,
            struct {
                fn onResponse(ctx: ?*anyopaque, response: provider_utils.HttpResponse) void {
                    const rctx: *ResponseContext = @ptrCast(@alignCast(ctx.?));
                    rctx.response_body = response.body;
                }
            }.onResponse,
            struct {
                fn onError(ctx: ?*anyopaque, err: provider_utils.HttpError) void {
                    const rctx: *ResponseContext = @ptrCast(@alignCast(ctx.?));
                    rctx.response_error = err;
                }
            }.onError,
            &response_ctx,
        );

        // Check for errors
        if (response_ctx.response_error != null) {
            callback(callback_context, .{ .failure = error.HttpRequestFailed });
            return;
        }

        const response_body = response_ctx.response_body orelse {
            callback(callback_context, .{ .failure = error.NoResponse });
            return;
        };

        // Parse response
        const parsed = response_types.GoogleGenerateContentResponse.fromJson(request_allocator, response_body) catch {
            callback(callback_context, .{ .failure = error.InvalidResponse });
            return;
        };
        const response = parsed.value;

        // Extract content from response
        var content = std.ArrayList(lm.LanguageModelV3Content).init(result_allocator);

        if (response.candidates) |candidates| {
            if (candidates.len > 0) {
                const candidate = candidates[0];

                if (candidate.content) |resp_content| {
                    if (resp_content.parts) |parts| {
                        for (parts) |part| {
                            // Handle text
                            if (part.text) |text| {
                                if (text.len > 0) {
                                    const text_copy = result_allocator.dupe(u8, text) catch continue;
                                    content.append(.{
                                        .text = .{ .text = text_copy },
                                    }) catch {};
                                }
                            }

                            // Handle function calls
                            if (part.functionCall) |fc| {
                                var args_str: []const u8 = "{}";
                                if (fc.args) |args| {
                                    var args_buffer = std.ArrayList(u8).init(request_allocator);
                                    std.json.stringify(args, .{}, args_buffer.writer()) catch {};
                                    args_str = result_allocator.dupe(u8, args_buffer.items) catch "{}";
                                }
                                content.append(.{
                                    .tool_call = .{
                                        .tool_call_id = result_allocator.dupe(u8, fc.name) catch "",
                                        .tool_name = result_allocator.dupe(u8, fc.name) catch "",
                                        .input = args_str,
                                    },
                                }) catch {};
                            }
                        }
                    }
                }
            }
        }

        // Extract usage
        var usage = lm.LanguageModelV3Usage{
            .prompt_tokens = 0,
            .completion_tokens = 0,
        };
        if (response.usageMetadata) |meta| {
            if (meta.promptTokenCount) |ptc| usage.prompt_tokens = ptc;
            if (meta.candidatesTokenCount) |ctc| usage.completion_tokens = ctc;
        }

        // Get finish reason
        var finish_reason: lm.LanguageModelV3FinishReason = .unknown;
        if (response.candidates) |candidates| {
            if (candidates.len > 0) {
                if (candidates[0].finishReason) |fr| {
                    finish_reason = map_finish.mapGoogleGenerativeAIFinishReason(fr);
                }
            }
        }

        const result = lm.LanguageModelV3.GenerateSuccess{
            .content = content.toOwnedSlice() catch &[_]lm.LanguageModelV3Content{},
            .finish_reason = finish_reason,
            .usage = usage,
            .warnings = &[_]shared.SharedV3Warning{},
        };

        callback(callback_context, .{ .success = result });
    }

    /// Stream state for SSE parsing
    const StreamState = struct {
        callbacks: lm.LanguageModelV3.StreamCallbacks,
        result_allocator: std.mem.Allocator,
        request_allocator: std.mem.Allocator,
        is_text_active: bool = false,
        finish_reason: lm.LanguageModelV3FinishReason = .unknown,
        usage: lm.LanguageModelV3Usage = .{ .prompt_tokens = 0, .completion_tokens = 0 },
        partial_line: std.ArrayList(u8),

        fn init(
            callbacks: lm.LanguageModelV3.StreamCallbacks,
            result_allocator: std.mem.Allocator,
            request_allocator: std.mem.Allocator,
        ) StreamState {
            return .{
                .callbacks = callbacks,
                .result_allocator = result_allocator,
                .request_allocator = request_allocator,
                .partial_line = std.ArrayList(u8).init(request_allocator),
            };
        }

        fn processChunk(self: *StreamState, chunk: []const u8) void {
            // Append chunk to partial line buffer
            self.partial_line.appendSlice(chunk) catch return;

            // Process complete lines
            while (std.mem.indexOf(u8, self.partial_line.items, "\n")) |newline_pos| {
                const line = self.partial_line.items[0..newline_pos];
                self.processLine(line);

                // Remove processed line from buffer
                const remaining = self.partial_line.items[newline_pos + 1 ..];
                std.mem.copyForwards(u8, self.partial_line.items[0..remaining.len], remaining);
                self.partial_line.shrinkRetainingCapacity(remaining.len);
            }
        }

        fn processLine(self: *StreamState, line: []const u8) void {
            // Skip empty lines
            const trimmed = std.mem.trim(u8, line, " \r\n");
            if (trimmed.len == 0) return;

            // Parse SSE data line
            if (std.mem.startsWith(u8, trimmed, "data: ")) {
                const json_data = trimmed[6..];

                // Skip [DONE] marker
                if (std.mem.eql(u8, json_data, "[DONE]")) return;

                // Parse JSON
                const parsed = std.json.parseFromSlice(
                    response_types.GoogleGenerateContentResponse,
                    self.request_allocator,
                    json_data,
                    .{ .ignore_unknown_fields = true },
                ) catch return;
                const response = parsed.value;

                // Process response
                if (response.candidates) |candidates| {
                    if (candidates.len > 0) {
                        const candidate = candidates[0];

                        if (candidate.content) |content| {
                            if (content.parts) |parts| {
                                for (parts) |part| {
                                    if (part.text) |text| {
                                        // Emit text_start if not active
                                        if (!self.is_text_active) {
                                            self.callbacks.on_part(self.callbacks.ctx, .{ .text_start = {} });
                                            self.is_text_active = true;
                                        }
                                        // Emit text delta
                                        const text_copy = self.result_allocator.dupe(u8, text) catch continue;
                                        self.callbacks.on_part(self.callbacks.ctx, .{
                                            .text_delta = .{ .text_delta = text_copy },
                                        });
                                    }

                                    if (part.functionCall) |fc| {
                                        var args_str: []const u8 = "{}";
                                        if (fc.args) |args| {
                                            var args_buffer = std.ArrayList(u8).init(self.request_allocator);
                                            std.json.stringify(args, .{}, args_buffer.writer()) catch {};
                                            args_str = self.result_allocator.dupe(u8, args_buffer.items) catch "{}";
                                        }
                                        self.callbacks.on_part(self.callbacks.ctx, .{
                                            .tool_call = .{
                                                .tool_call_id = self.result_allocator.dupe(u8, fc.name) catch "",
                                                .tool_name = self.result_allocator.dupe(u8, fc.name) catch "",
                                                .input = args_str,
                                            },
                                        });
                                    }
                                }
                            }
                        }

                        if (candidate.finishReason) |fr| {
                            self.finish_reason = map_finish.mapGoogleGenerativeAIFinishReason(fr);
                        }
                    }
                }

                // Extract usage
                if (response.usageMetadata) |meta| {
                    if (meta.promptTokenCount) |ptc| self.usage.prompt_tokens = ptc;
                    if (meta.candidatesTokenCount) |ctc| self.usage.completion_tokens = ctc;
                }
            }
        }

        fn finish(self: *StreamState) void {
            // Emit text_end if text was active
            if (self.is_text_active) {
                self.callbacks.on_part(self.callbacks.ctx, .{ .text_end = {} });
            }

            // Emit finish part
            self.callbacks.on_part(self.callbacks.ctx, .{
                .finish = .{
                    .finish_reason = self.finish_reason,
                    .usage = self.usage,
                },
            });

            // Complete the stream
            self.callbacks.on_complete(self.callbacks.ctx, null);
        }
    };

    /// Stream content
    pub fn doStream(
        self: *const Self,
        call_options: lm.LanguageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callbacks: lm.LanguageModelV3.StreamCallbacks,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        // Note: arena cleanup is deferred until stream completes
        const request_allocator = arena.allocator();

        // Build the request
        const request_body = self.buildRequestBody(request_allocator, call_options) catch |err| {
            callbacks.on_error(callbacks.ctx, err);
            arena.deinit();
            return;
        };

        // Make the streaming API call
        const url = std.fmt.allocPrint(
            request_allocator,
            "{s}/models/{s}:streamGenerateContent?alt=sse",
            .{ self.config.base_url, self.getModelPath() },
        ) catch |err| {
            callbacks.on_error(callbacks.ctx, err);
            arena.deinit();
            return;
        };

        // Get headers
        var headers = if (self.config.headers_fn) |headers_fn|
            headers_fn(&self.config, request_allocator)
        else
            std.StringHashMap([]const u8).init(request_allocator);

        headers.put("Content-Type", "application/json") catch {};

        // Serialize request body
        var body_buffer = std.ArrayList(u8).init(request_allocator);
        std.json.stringify(request_body, .{}, body_buffer.writer()) catch |err| {
            callbacks.on_error(callbacks.ctx, err);
            arena.deinit();
            return;
        };

        // Get HTTP client
        const http_client = self.config.http_client orelse {
            callbacks.on_error(callbacks.ctx, error.NoHttpClient);
            arena.deinit();
            return;
        };

        // Convert headers to slice
        var header_list = std.ArrayList(provider_utils.HttpHeader).init(request_allocator);
        var header_iter = headers.iterator();
        while (header_iter.next()) |entry| {
            header_list.append(.{
                .name = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            }) catch {};
        }

        // Create stream state
        var stream_state = StreamState.init(callbacks, result_allocator, request_allocator);

        // Make streaming HTTP request
        http_client.requestStreaming(
            .{
                .method = .POST,
                .url = url,
                .headers = header_list.items,
                .body = body_buffer.items,
            },
            request_allocator,
            .{
                .on_chunk = struct {
                    fn onChunk(ctx: ?*anyopaque, chunk: []const u8) void {
                        const state: *StreamState = @ptrCast(@alignCast(ctx.?));
                        state.processChunk(chunk);
                    }
                }.onChunk,
                .on_complete = struct {
                    fn onComplete(ctx: ?*anyopaque) void {
                        const state: *StreamState = @ptrCast(@alignCast(ctx.?));
                        state.finish();
                    }
                }.onComplete,
                .on_error = struct {
                    fn onError(ctx: ?*anyopaque, err: provider_utils.HttpError) void {
                        const state: *StreamState = @ptrCast(@alignCast(ctx.?));
                        _ = err;
                        state.callbacks.on_error(state.callbacks.ctx, error.HttpRequestFailed);
                    }
                }.onError,
                .ctx = &stream_state,
            },
        );
    }

    /// Build the request body for the API call
    fn buildRequestBody(
        self: *const Self,
        allocator: std.mem.Allocator,
        call_options: lm.LanguageModelV3CallOptions,
    ) !std.json.Value {
        var body = std.json.ObjectMap.init(allocator);

        // Convert messages
        const is_gemma = options_mod.isGemmaModel(self.model_id);
        const converted = try convert.convertToGoogleGenerativeAIMessages(
            allocator,
            call_options.prompt,
            .{ .is_gemma_model = is_gemma },
        );

        // Add contents
        var contents_array = std.json.Array.init(allocator);
        for (converted.contents) |content| {
            var content_obj = std.json.ObjectMap.init(allocator);
            try content_obj.put("role", .{ .string = content.role });

            var parts_array = std.json.Array.init(allocator);
            for (content.parts) |part| {
                const part_json = try @import("google-generative-ai-prompt.zig").serializeContentPart(allocator, part);
                try parts_array.append(part_json);
            }
            try content_obj.put("parts", .{ .array = parts_array });

            try contents_array.append(.{ .object = content_obj });
        }
        try body.put("contents", .{ .array = contents_array });

        // Add system instruction if present
        if (converted.system_instruction) |sys| {
            var sys_obj = std.json.ObjectMap.init(allocator);
            var sys_parts = std.json.Array.init(allocator);
            for (sys.parts) |part| {
                var part_obj = std.json.ObjectMap.init(allocator);
                try part_obj.put("text", .{ .string = part.text });
                try sys_parts.append(.{ .object = part_obj });
            }
            try sys_obj.put("parts", .{ .array = sys_parts });
            try body.put("systemInstruction", .{ .object = sys_obj });
        }

        // Add generation config
        var gen_config = std.json.ObjectMap.init(allocator);

        if (call_options.max_output_tokens) |max_tokens| {
            try gen_config.put("maxOutputTokens", .{ .integer = @intCast(max_tokens) });
        }
        if (call_options.temperature) |temp| {
            try gen_config.put("temperature", .{ .float = temp });
        }
        if (call_options.top_p) |top_p| {
            try gen_config.put("topP", .{ .float = top_p });
        }
        if (call_options.top_k) |top_k| {
            try gen_config.put("topK", .{ .integer = @intCast(top_k) });
        }
        if (call_options.frequency_penalty) |freq| {
            try gen_config.put("frequencyPenalty", .{ .float = freq });
        }
        if (call_options.presence_penalty) |pres| {
            try gen_config.put("presencePenalty", .{ .float = pres });
        }
        if (call_options.seed) |seed| {
            try gen_config.put("seed", .{ .integer = @intCast(seed) });
        }
        if (call_options.stop_sequences) |stops| {
            var stops_array = std.json.Array.init(allocator);
            for (stops) |stop| {
                try stops_array.append(.{ .string = stop });
            }
            try gen_config.put("stopSequences", .{ .array = stops_array });
        }

        // Add response format
        if (call_options.response_format) |format| {
            switch (format) {
                .json => {
                    try gen_config.put("responseMimeType", .{ .string = "application/json" });
                    if (format.json.schema) |schema| {
                        try gen_config.put("responseSchema", schema);
                    }
                },
                .text => {},
            }
        }

        if (gen_config.count() > 0) {
            try body.put("generationConfig", .{ .object = gen_config });
        }

        // Add tools
        const tools_result = try prepare_tools.prepareTools(
            allocator,
            call_options.tools,
            call_options.tool_choice,
            self.model_id,
        );

        if (tools_result.function_declarations) |decls| {
            var tools_array = std.json.Array.init(allocator);
            var func_decls_obj = std.json.ObjectMap.init(allocator);
            var func_decls_array = std.json.Array.init(allocator);

            for (decls) |decl| {
                var decl_obj = std.json.ObjectMap.init(allocator);
                try decl_obj.put("name", .{ .string = decl.name });
                try decl_obj.put("description", .{ .string = decl.description });
                try decl_obj.put("parameters", decl.parameters);
                try func_decls_array.append(.{ .object = decl_obj });
            }

            try func_decls_obj.put("functionDeclarations", .{ .array = func_decls_array });
            try tools_array.append(.{ .object = func_decls_obj });
            try body.put("tools", .{ .array = tools_array });
        }

        if (tools_result.provider_tools) |prov_tools| {
            var tools_array = std.json.Array.init(allocator);
            for (prov_tools) |prov_tool| {
                var tool_obj = std.json.ObjectMap.init(allocator);
                switch (prov_tool) {
                    .google_search => {
                        try tool_obj.put("googleSearch", .{ .object = std.json.ObjectMap.init(allocator) });
                    },
                    .code_execution => {
                        try tool_obj.put("codeExecution", .{ .object = std.json.ObjectMap.init(allocator) });
                    },
                    .url_context => {
                        try tool_obj.put("urlContext", .{ .object = std.json.ObjectMap.init(allocator) });
                    },
                    .google_maps => {
                        try tool_obj.put("googleMaps", .{ .object = std.json.ObjectMap.init(allocator) });
                    },
                    else => {},
                }
                try tools_array.append(.{ .object = tool_obj });
            }
            try body.put("tools", .{ .array = tools_array });
        }

        if (tools_result.tool_config) |tc| {
            var tc_obj = std.json.ObjectMap.init(allocator);
            if (tc.function_calling_config) |fcc| {
                var fcc_obj = std.json.ObjectMap.init(allocator);
                try fcc_obj.put("mode", .{ .string = fcc.mode.toString() });
                if (fcc.allowed_function_names) |names| {
                    var names_array = std.json.Array.init(allocator);
                    for (names) |name| {
                        try names_array.append(.{ .string = name });
                    }
                    try fcc_obj.put("allowedFunctionNames", .{ .array = names_array });
                }
                try tc_obj.put("functionCallingConfig", .{ .object = fcc_obj });
            }
            try body.put("toolConfig", .{ .object = tc_obj });
        }

        // Add safety settings from provider options
        if (call_options.provider_options) |provider_options| {
            if (provider_options.get("google")) |google_opts| {
                if (google_opts.get("safety_settings")) |safety_value| {
                    if (safety_value == .array) {
                        var safety_arr = std.json.Array.init(allocator);
                        for (safety_value.array) |setting| {
                            if (setting == .object) {
                                var setting_obj = std.json.ObjectMap.init(allocator);
                                if (setting.object.get("category")) |cat| {
                                    if (cat == .string) {
                                        try setting_obj.put("category", .{ .string = cat.string });
                                    }
                                }
                                if (setting.object.get("threshold")) |thresh| {
                                    if (thresh == .string) {
                                        try setting_obj.put("threshold", .{ .string = thresh.string });
                                    }
                                }
                                try safety_arr.append(.{ .object = setting_obj });
                            }
                        }
                        if (safety_arr.items.len > 0) {
                            try body.put("safetySettings", .{ .array = safety_arr });
                        }
                    }
                }
            }
        }

        return .{ .object = body };
    }

    /// Get supported URLs (stub implementation)
    pub fn getSupportedUrls(
        self: *const Self,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, lm.LanguageModelV3.SupportedUrlsResult) void,
        ctx: ?*anyopaque,
    ) void {
        _ = self;
        callback(ctx, .{ .success = std.StringHashMap([]const []const u8).init(allocator) });
    }

    /// Convert to LanguageModelV3 interface
    pub fn asLanguageModel(self: *Self) lm.LanguageModelV3 {
        return lm.asLanguageModel(Self, self);
    }
};

test "GoogleGenerativeAILanguageModel init" {
    const allocator = std.testing.allocator;

    var model = GoogleGenerativeAILanguageModel.init(
        allocator,
        "gemini-2.0-flash",
        .{},
    );

    try std.testing.expectEqualStrings("gemini-2.0-flash", model.getModelId());
    try std.testing.expectEqualStrings("google.generative-ai", model.getProvider());
}

test "GoogleGenerativeAILanguageModel getModelPath" {
    const allocator = std.testing.allocator;

    var model = GoogleGenerativeAILanguageModel.init(
        allocator,
        "gemini-2.0-flash",
        .{},
    );

    try std.testing.expectEqualStrings("gemini-2.0-flash", model.getModelPath());

    // Test tuned model
    var tuned_model = GoogleGenerativeAILanguageModel.init(
        allocator,
        "tunedModels/my-model",
        .{},
    );

    try std.testing.expectEqualStrings("tunedModels/my-model", tuned_model.getModelPath());
}

test "Google finish reason mapping via language model" {
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.stop, map_finish.mapGoogleGenerativeAIFinishReason("STOP", false));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.tool_calls, map_finish.mapGoogleGenerativeAIFinishReason("STOP", true));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.length, map_finish.mapGoogleGenerativeAIFinishReason("MAX_TOKENS", false));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.content_filter, map_finish.mapGoogleGenerativeAIFinishReason("SAFETY", false));
    try std.testing.expectEqual(lm.LanguageModelV3FinishReason.unknown, map_finish.mapGoogleGenerativeAIFinishReason(null, false));
}

test "Google response parsing integration" {
    const allocator = std.testing.allocator;
    const response_json =
        \\{"candidates":[{"content":{"parts":[{"text":"Hello!"}],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"totalTokenCount":15}}
    ;

    const parsed = try response_types.GoogleGenerateContentResponse.fromJson(allocator, response_json);
    defer parsed.deinit();
    const response = parsed.value;

    try std.testing.expect(response.candidates != null);
    try std.testing.expectEqual(@as(usize, 1), response.candidates.?.len);
    try std.testing.expectEqualStrings("STOP", response.candidates.?[0].finishReason.?);
    try std.testing.expect(response.usageMetadata != null);
    try std.testing.expectEqual(@as(u64, 10), response.usageMetadata.?.promptTokenCount.?);
    try std.testing.expectEqual(@as(u64, 5), response.usageMetadata.?.candidatesTokenCount.?);
}
