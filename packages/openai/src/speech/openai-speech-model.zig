const std = @import("std");
const sm = @import("provider").speech_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");

const api = @import("openai-speech-api.zig");
const options_mod = @import("openai-speech-options.zig");
const config_mod = @import("../openai-config.zig");
const error_mod = @import("../openai-error.zig");

/// OpenAI Speech Model implementation
pub const OpenAISpeechModel = struct {
    const Self = @This();

    /// Model ID
    model_id: []const u8,

    /// Configuration
    config: config_mod.OpenAIConfig,

    /// Allocator for internal operations
    allocator: std.mem.Allocator,

    pub const specification_version = "v3";

    /// Initialize a new OpenAI speech model
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

    /// Generate speech
    pub fn doGenerate(
        self: *const Self,
        call_options: sm.SpeechModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, sm.SpeechModelV3.GenerateResult) void,
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
        call_options: sm.SpeechModelV3CallOptions,
    ) !sm.SpeechModelV3.GenerateSuccess {
        const timestamp = std.time.milliTimestamp();
        var warnings: std.ArrayList(shared.SharedV3Warning) = .empty;

        // Determine voice
        const voice = call_options.voice orelse "alloy";

        // Determine output format
        var output_format: []const u8 = "mp3";
        if (call_options.output_format) |fmt| {
            if (options_mod.isSupportedOutputFormat(fmt)) {
                output_format = fmt;
            } else {
                try warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature("outputFormat", "Unsupported output format. Using mp3 instead."));
            }
        }

        // Check for unsupported language
        if (call_options.language != null) {
            try warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature("language", "OpenAI speech models do not support language selection."));
        }

        // Build request
        const request = api.OpenAISpeechRequest{
            .model = self.model_id,
            .input = call_options.text,
            .voice = voice,
            .response_format = output_format,
            .speed = call_options.speed,
            .instructions = call_options.instructions,
        };

        // Build URL
        const url = try self.config.buildUrl(request_allocator, "/audio/speech", self.model_id);

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

        // Serialize request body
        const body = try serializeRequest(request_allocator, request);

        // Make the request (expecting binary response)
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

        const audio_data = response_data orelse return error.NoResponse;

        // Clone warnings
        var result_warnings = try result_allocator.alloc(shared.SharedV3Warning, warnings.items.len);
        for (warnings.items, 0..) |w, i| {
            result_warnings[i] = w;
        }

        return .{
            .audio = .{ .binary = try result_allocator.dupe(u8, audio_data) },
            .warnings = result_warnings,
            .response = .{
                .timestamp = timestamp,
                .model_id = try result_allocator.dupe(u8, self.model_id),
                .headers = response_headers,
            },
        };
    }

    /// Convert to SpeechModelV3 interface
    pub fn asSpeechModel(self: *Self) sm.SpeechModelV3 {
        return .{
            .vtable = &vtable,
            .impl = self,
        };
    }

    const vtable = sm.SpeechModelV3.VTable{
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
        call_options: sm.SpeechModelV3CallOptions,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, sm.SpeechModelV3.GenerateResult) void,
        context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doGenerate(call_options, allocator, callback, context);
    }
};

/// Options for speech generation
pub const GenerateOptions = struct {
    text: []const u8,
    voice: ?options_mod.Voice = null,
    output_format: ?[]const u8 = null,
    speed: ?f32 = null,
    language: ?[]const u8 = null,
    instructions: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
};

/// Result of generate call (legacy compatibility)
pub const GenerateResult = sm.SpeechModelV3.GenerateResult;

/// Serialize request to JSON
fn serializeRequest(allocator: std.mem.Allocator, request: api.OpenAISpeechRequest) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, request, .{});
}

test "OpenAISpeechModel basic" {
    const allocator = std.testing.allocator;

    const config = config_mod.OpenAIConfig{
        .provider = "openai.speech",
        .base_url = "https://api.openai.com/v1",
        .headers_fn = struct {
            fn getHeaders(_: *const config_mod.OpenAIConfig, alloc: std.mem.Allocator) std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(alloc);
            }
        }.getHeaders,
    };

    const model = OpenAISpeechModel.init(allocator, "tts-1", config);
    try std.testing.expectEqualStrings("openai.speech", model.getProvider());
    try std.testing.expectEqualStrings("tts-1", model.getModelId());
}
