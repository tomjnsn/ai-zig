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
        options: GenerateOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, GenerateResult) void,
        context: ?*anyopaque,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        const result = self.doGenerateInternal(request_allocator, result_allocator, options) catch |err| {
            callback(context, .{ .failure = err });
            return;
        };

        callback(context, .{ .success = result });
    }

    fn doGenerateInternal(
        self: *const Self,
        request_allocator: std.mem.Allocator,
        result_allocator: std.mem.Allocator,
        options: GenerateOptions,
    ) !GenerateResultOk {
        const warnings = std.array_list.Managed(shared.SharedV3Warning).init(request_allocator);
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

        // Get headers
        var headers = self.config.getHeaders(request_allocator);
        if (options.headers) |user_headers| {
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
            .value = .{ .binary = options.audio },
            .filename = "audio.mp3",
            .content_type = options.media_type,
        });

        // Add response format
        try form_parts.append(.{
            .name = "response_format",
            .value = .{ .text = response_format },
        });

        // Add optional fields
        if (options.language) |lang| {
            try form_parts.append(.{
                .name = "language",
                .value = .{ .text = lang },
            });
        }

        if (options.prompt) |prompt| {
            try form_parts.append(.{
                .name = "prompt",
                .value = .{ .text = prompt },
            });
        }

        if (options.temperature) |temp| {
            var temp_buf: [32]u8 = undefined;
            const temp_str = std.fmt.bufPrint(&temp_buf, "{d}", .{temp}) catch "0";
            try form_parts.append(.{
                .name = "temperature",
                .value = .{ .text = temp_str },
            });
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

        http_client.post(url, headers, body, request_allocator, struct {
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

        // Convert segments
        const segments = try api.convertSegments(result_allocator, response);

        // Get language code
        const language: ?[]const u8 = if (response.language) |lang|
            options_mod.languageNameToCode(lang) orelse try result_allocator.dupe(u8, lang)
        else
            null;

        return .{
            .text = try result_allocator.dupe(u8, response.text),
            .segments = segments,
            .language = language,
            .duration_seconds = response.duration,
            .warnings = &[_]shared.SharedV3Warning{},
            .model_id = try result_allocator.dupe(u8, self.model_id),
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
        callback: *const fn (?*anyopaque, GenerateResult) void,
        context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doGenerate(.{
            .audio = call_options.audio,
            .media_type = call_options.media_type,
        }, allocator, callback, context);
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

/// Result of generate call
pub const GenerateResult = union(enum) {
    ok: GenerateResultOk,
    err: anyerror,
};

pub const GenerateResultOk = struct {
    text: []const u8,
    segments: []api.TranscriptionSegment,
    language: ?[]const u8,
    duration_seconds: ?f64,
    warnings: []shared.SharedV3Warning,
    model_id: []const u8,
};

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
            fn getHeaders(_: *const config_mod.OpenAIConfig) std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(std.testing.allocator);
            }
        }.getHeaders,
    };

    const model = OpenAITranscriptionModel.init(allocator, "whisper-1", config);
    try std.testing.expectEqualStrings("openai.transcription", model.getProvider());
    try std.testing.expectEqualStrings("whisper-1", model.getModelId());
}
