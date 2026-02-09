const std = @import("std");
const tm = @import("provider").transcription_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");

const api = @import("openai-transcription-api.zig");
const options_mod = @import("openai-transcription-options.zig");
const config_mod = @import("../openai-config.zig");
const error_mod = @import("../openai-error.zig");

/// OpenAI Transcription Model implementation
pub const OpenAITranscriptionModel = struct {
    const Self = @This();

    /// Model ID
    model_id: []const u8,

    /// Configuration
    config: config_mod.OpenAIConfig,

    /// Allocator for internal operations
    allocator: std.mem.Allocator,

    pub const specification_version = "v3";

    /// Initialize a new OpenAI transcription model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.OpenAIConfig,
    ) Self {
        return .{
            .model_id = model_id,
            .config = config,
            .allocator = allocator,
        };
    }

    /// Get the provider name
    pub fn getProvider(self: *const Self) []const u8 {
        return self.config.provider;
    }

    /// Get the model ID
    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    /// Generate transcription
    pub fn doGenerate(
        self: *const Self,
        call_options: tm.TranscriptionModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, tm.TranscriptionModelV3.GenerateResult) void,
        context: ?*anyopaque,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        const result = self.doGenerateInternal(request_allocator, result_allocator, call_options) catch |err| {
            callback(context, .{ .failure = err });
            return;
        };

        callback(context, .{ .success = result });
    }

    fn doGenerateInternal(
        self: *const Self,
        request_allocator: std.mem.Allocator,
        result_allocator: std.mem.Allocator,
        call_options: tm.TranscriptionModelV3CallOptions,
    ) !tm.TranscriptionModelV3.GenerateSuccess {
        const timestamp = std.time.milliTimestamp();
        const warnings: std.ArrayList(shared.SharedV3Warning) = .empty;
        _ = warnings;

        // Determine response format
        // GPT-4o transcribe models use json, others use verbose_json for segments
        const response_format: []const u8 = if (std.mem.eql(u8, self.model_id, "gpt-4o-transcribe") or
            std.mem.eql(u8, self.model_id, "gpt-4o-mini-transcribe"))
            "json"
        else
            "verbose_json";

        // Build URL
        const url = try self.config.buildUrl(request_allocator, "/audio/transcriptions", self.model_id);

        // Extract audio data from union
        const audio_binary = switch (call_options.audio) {
            .binary => |data| data,
            .base64 => |b64| blk: {
                // Decode base64 if needed
                const decoder = std.base64.standard.Decoder;
                const decoded = try request_allocator.alloc(u8, try decoder.calcSizeForSlice(b64));
                _ = try decoder.decode(decoded, b64);
                break :blk decoded;
            },
        };

        // Get headers
        var headers = self.config.getHeaders(request_allocator);
        if (call_options.headers) |user_headers| {
            var iter = user_headers.iterator();
            while (iter.next()) |entry| {
                try headers.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Make HTTP request
        const http_client = self.config.http_client orelse return error.NoHttpClient;

        // Build multipart form data
        var form_parts = std.array_list.Managed(FormPart).init(request_allocator);

        // Add model
        try form_parts.append(.{
            .name = "model",
            .value = .{ .text = self.model_id },
        });

        // Add file
        try form_parts.append(.{
            .name = "file",
            .value = .{ .binary = audio_binary },
            .filename = "audio.mp3",
            .content_type = call_options.media_type,
        });

        // Add response format
        try form_parts.append(.{
            .name = "response_format",
            .value = .{ .text = response_format },
        });

        // Add optional fields from provider_options
        if (call_options.provider_options) |opts| {
            if (opts.get("language")) |lang_value| {
                if (lang_value == .string) {
                    try form_parts.append(.{
                        .name = "language",
                        .value = .{ .text = lang_value.string },
                    });
                }
            }

            if (opts.get("prompt")) |prompt_value| {
                if (prompt_value == .string) {
                    try form_parts.append(.{
                        .name = "prompt",
                        .value = .{ .text = prompt_value.string },
                    });
                }
            }

            if (opts.get("temperature")) |temp_value| {
                if (temp_value == .float) {
                    var temp_buf: [32]u8 = undefined;
                    const temp_str = std.fmt.bufPrint(&temp_buf, "{d}", .{temp_value.float}) catch "0";
                    try form_parts.append(.{
                        .name = "temperature",
                        .value = .{ .text = temp_str },
                    });
                }
            }
        }

        // Build multipart body
        const boundary = "----ZigAISDKFormBoundary";
        const body = try buildMultipartBody(request_allocator, form_parts.items, boundary);

        // Update content-type header
        const content_type = try std.fmt.allocPrint(request_allocator, "multipart/form-data; boundary={s}", .{boundary});
        try headers.put("Content-Type", content_type);

        // Make the request
        var response_data: ?[]const u8 = null;
        var response_headers: ?std.StringHashMap([]const u8) = null;

        try http_client.post(url, headers, body, request_allocator, struct {
            fn onResponse(ctx: *anyopaque, resp_headers: std.StringHashMap([]const u8), resp_body: []const u8) void {
                const data = @as(*struct { body: *?[]const u8, headers: *?std.StringHashMap([]const u8) }, @ptrCast(@alignCast(ctx)));
                data.body.* = resp_body;
                data.headers.* = resp_headers;
            }
            fn onError(_: *anyopaque, _: anyerror) void {}
        }.onResponse, struct {
            fn onError(_: *anyopaque, _: anyerror) void {}
        }.onError, &.{ .body = &response_data, .headers = &response_headers });

        const response_body = response_data orelse return error.NoResponse;

        // Parse response
        const parsed = std.json.parseFromSlice(api.OpenAITranscriptionResponse, request_allocator, response_body, .{}) catch {
            return error.InvalidResponse;
        };
        const response = parsed.value;

        // Convert segments to tm.TranscriptionSegment
        var segments: []tm.TranscriptionSegment = &[_]tm.TranscriptionSegment{};
        if (response.segments) |resp_segments| {
            segments = try result_allocator.alloc(tm.TranscriptionSegment, resp_segments.len);
            for (resp_segments, 0..) |seg, i| {
                segments[i] = .{
                    .text = try result_allocator.dupe(u8, seg.text),
                    .start_second = seg.start,
                    .end_second = seg.end,
                };
            }
        } else if (response.words) |words| {
            segments = try result_allocator.alloc(tm.TranscriptionSegment, words.len);
            for (words, 0..) |word, i| {
                segments[i] = .{
                    .text = try result_allocator.dupe(u8, word.word),
                    .start_second = word.start,
                    .end_second = word.end,
                };
            }
        }

        // Get language code
        const language: ?[]const u8 = if (response.language) |lang|
            options_mod.languageNameToCode(lang) orelse try result_allocator.dupe(u8, lang)
        else
            null;

        return .{
            .text = try result_allocator.dupe(u8, response.text),
            .segments = segments,
            .language = language,
            .duration_in_seconds = response.duration,
            .warnings = &[_]shared.SharedV3Warning{},
            .response = .{
                .timestamp = timestamp,
                .model_id = try result_allocator.dupe(u8, self.model_id),
                .headers = response_headers,
            },
        };
    }

    /// Convert to TranscriptionModelV3 interface
    pub fn asTranscriptionModel(self: *Self) tm.TranscriptionModelV3 {
        return .{
            .vtable = &vtable,
            .impl = self,
        };
    }

    const vtable = tm.TranscriptionModelV3.VTable{
        .getProvider = getProviderVtable,
        .getModelId = getModelIdVtable,
        .doGenerate = doGenerateVtable,
    };

    fn getProviderVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getProvider();
    }

    fn getModelIdVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getModelId();
    }

    fn doGenerateVtable(
        impl: *anyopaque,
        call_options: tm.TranscriptionModelV3CallOptions,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, tm.TranscriptionModelV3.GenerateResult) void,
        context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doGenerate(call_options, allocator, callback, context);
    }
};

/// Options for transcription
pub const GenerateOptions = struct {
    audio: []const u8,
    media_type: []const u8,
    language: ?[]const u8 = null,
    prompt: ?[]const u8 = null,
    temperature: ?f32 = null,
    headers: ?std.StringHashMap([]const u8) = null,
};

/// Result of generate call (legacy compatibility)
pub const GenerateResult = tm.TranscriptionModelV3.GenerateResult;

/// Form part for multipart encoding
const FormPart = struct {
    name: []const u8,
    value: union(enum) {
        text: []const u8,
        binary: []const u8,
    },
    filename: ?[]const u8 = null,
    content_type: ?[]const u8 = null,
};

/// Build multipart form body
fn buildMultipartBody(allocator: std.mem.Allocator, parts: []const FormPart, boundary: []const u8) ![]const u8 {
    var buffer = std.array_list.Managed(u8).init(allocator);
    const writer = buffer.writer();

    for (parts) |part| {
        try writer.print("--{s}\r\n", .{boundary});
        try writer.print("Content-Disposition: form-data; name=\"{s}\"", .{part.name});

        if (part.filename) |filename| {
            try writer.print("; filename=\"{s}\"", .{filename});
        }
        try writer.writeAll("\r\n");

        if (part.content_type) |ct| {
            try writer.print("Content-Type: {s}\r\n", .{ct});
        }

        try writer.writeAll("\r\n");

        switch (part.value) {
            .text => |text| try writer.writeAll(text),
            .binary => |data| try writer.writeAll(data),
        }

        try writer.writeAll("\r\n");
    }

    try writer.print("--{s}--\r\n", .{boundary});

    return buffer.toOwnedSlice();
}

test "OpenAITranscriptionModel basic" {
    const allocator = std.testing.allocator;

    const config = config_mod.OpenAIConfig{
        .provider = "openai.transcription",
        .base_url = "https://api.openai.com/v1",
        .headers_fn = struct {
            fn getHeaders(_: *const config_mod.OpenAIConfig, alloc: std.mem.Allocator) std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(alloc);
            }
        }.getHeaders,
    };

    const model = OpenAITranscriptionModel.init(allocator, "whisper-1", config);
    try std.testing.expectEqualStrings("openai.transcription", model.getProvider());
    try std.testing.expectEqualStrings("whisper-1", model.getModelId());
}
