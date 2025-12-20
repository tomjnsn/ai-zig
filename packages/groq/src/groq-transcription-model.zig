const std = @import("std");

const config_mod = @import("groq-config.zig");
const options_mod = @import("groq-options.zig");

/// Groq Transcription Model
pub const GroqTranscriptionModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.GroqConfig,

    /// Create a new Groq transcription model
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

    /// Transcription result
    pub const TranscriptionResult = struct {
        text: []const u8,
        segments: ?[]const Segment = null,
        language: ?[]const u8 = null,
        duration: ?f64 = null,
    };

    /// Transcription segment
    pub const Segment = struct {
        id: usize,
        start: f64,
        end: f64,
        text: []const u8,
    };

    /// Transcription options
    pub const TranscriptionOptions = struct {
        /// The language of the audio (ISO 639-1)
        language: ?[]const u8 = null,

        /// The format of the transcript output
        response_format: ?ResponseFormat = null,

        /// Temperature for sampling
        temperature: ?f32 = null,

        /// A prompt to guide the transcription
        prompt: ?[]const u8 = null,
    };

    /// Response format options
    pub const ResponseFormat = enum {
        json,
        text,
        srt,
        verbose_json,
        vtt,

        pub fn toString(self: ResponseFormat) []const u8 {
            return switch (self) {
                .json => "json",
                .text => "text",
                .srt => "srt",
                .verbose_json => "verbose_json",
                .vtt => "vtt",
            };
        }
    };

    /// Transcribe audio
    pub fn doTranscribe(
        self: *Self,
        audio_data: []const u8,
        options: TranscriptionOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?TranscriptionResult, ?anyerror, ?*anyopaque) void,
        callback_context: ?*anyopaque,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        // Build URL
        const url = config_mod.buildTranscriptionsUrl(
            request_allocator,
            self.config.base_url,
        ) catch |err| {
            callback(null, err, callback_context);
            return;
        };

        _ = url;
        _ = audio_data;
        _ = options;

        // For now, return placeholder result
        const text = result_allocator.dupe(u8, "Transcription placeholder") catch |err| {
            callback(null, err, callback_context);
            return;
        };

        const result = TranscriptionResult{
            .text = text,
            .segments = null,
            .language = null,
            .duration = null,
        };

        callback(result, null, callback_context);
    }
};

test "GroqTranscriptionModel init" {
    const allocator = std.testing.allocator;

    var model = GroqTranscriptionModel.init(
        allocator,
        "whisper-large-v3-turbo",
        .{ .base_url = "https://api.groq.com/openai/v1" },
    );

    try std.testing.expectEqualStrings("whisper-large-v3-turbo", model.getModelId());
}

test "GroqTranscriptionModel init with custom config" {
    const allocator = std.testing.allocator;

    var model = GroqTranscriptionModel.init(
        allocator,
        "custom-model",
        .{
            .provider = "groq.transcription.custom",
            .base_url = "https://custom.groq.com",
        },
    );

    try std.testing.expectEqualStrings("custom-model", model.getModelId());
    try std.testing.expectEqualStrings("groq.transcription.custom", model.getProvider());
}

test "GroqTranscriptionModel getModelId and getProvider" {
    const allocator = std.testing.allocator;

    var model = GroqTranscriptionModel.init(
        allocator,
        "whisper-large-v3",
        .{},
    );

    try std.testing.expectEqualStrings("whisper-large-v3", model.getModelId());
    try std.testing.expectEqualStrings("groq", model.getProvider());
}

test "GroqTranscriptionModel multiple instances" {
    const allocator = std.testing.allocator;

    var model1 = GroqTranscriptionModel.init(allocator, "whisper-large-v3-turbo", .{});
    var model2 = GroqTranscriptionModel.init(allocator, "whisper-large-v3", .{});

    try std.testing.expectEqualStrings("whisper-large-v3-turbo", model1.getModelId());
    try std.testing.expectEqualStrings("whisper-large-v3", model2.getModelId());

    try std.testing.expectEqualStrings("groq", model1.getProvider());
    try std.testing.expectEqualStrings("groq", model2.getProvider());
}

test "GroqTranscriptionModel ResponseFormat toString" {
    try std.testing.expectEqualStrings("json", GroqTranscriptionModel.ResponseFormat.json.toString());
    try std.testing.expectEqualStrings("text", GroqTranscriptionModel.ResponseFormat.text.toString());
    try std.testing.expectEqualStrings("srt", GroqTranscriptionModel.ResponseFormat.srt.toString());
    try std.testing.expectEqualStrings("verbose_json", GroqTranscriptionModel.ResponseFormat.verbose_json.toString());
    try std.testing.expectEqualStrings("vtt", GroqTranscriptionModel.ResponseFormat.vtt.toString());
}

test "GroqTranscriptionModel ResponseFormat enum values" {
    const json = GroqTranscriptionModel.ResponseFormat.json;
    const text = GroqTranscriptionModel.ResponseFormat.text;
    const srt = GroqTranscriptionModel.ResponseFormat.srt;
    const verbose_json = GroqTranscriptionModel.ResponseFormat.verbose_json;
    const vtt = GroqTranscriptionModel.ResponseFormat.vtt;

    try std.testing.expect(json != text);
    try std.testing.expect(text != srt);
    try std.testing.expect(srt != verbose_json);
    try std.testing.expect(verbose_json != vtt);
}

test "GroqTranscriptionModel TranscriptionOptions default values" {
    const options = GroqTranscriptionModel.TranscriptionOptions{};

    try std.testing.expect(options.language == null);
    try std.testing.expect(options.response_format == null);
    try std.testing.expect(options.temperature == null);
    try std.testing.expect(options.prompt == null);
}

test "GroqTranscriptionModel TranscriptionOptions with custom values" {
    const options = GroqTranscriptionModel.TranscriptionOptions{
        .language = "en",
        .response_format = .verbose_json,
        .temperature = 0.5,
        .prompt = "Transcribe this audio",
    };

    try std.testing.expect(options.language != null);
    try std.testing.expectEqualStrings("en", options.language.?);
    try std.testing.expect(options.response_format != null);
    try std.testing.expectEqual(GroqTranscriptionModel.ResponseFormat.verbose_json, options.response_format.?);
    try std.testing.expect(options.temperature != null);
    try std.testing.expectEqual(@as(f32, 0.5), options.temperature.?);
    try std.testing.expect(options.prompt != null);
    try std.testing.expectEqualStrings("Transcribe this audio", options.prompt.?);
}

test "GroqTranscriptionModel Segment structure" {
    const segment = GroqTranscriptionModel.Segment{
        .id = 1,
        .start = 0.0,
        .end = 5.5,
        .text = "Hello world",
    };

    try std.testing.expectEqual(@as(usize, 1), segment.id);
    try std.testing.expectEqual(@as(f64, 0.0), segment.start);
    try std.testing.expectEqual(@as(f64, 5.5), segment.end);
    try std.testing.expectEqualStrings("Hello world", segment.text);
}

test "GroqTranscriptionModel TranscriptionResult structure" {
    const segments = [_]GroqTranscriptionModel.Segment{
        .{
            .id = 0,
            .start = 0.0,
            .end = 2.5,
            .text = "First segment",
        },
        .{
            .id = 1,
            .start = 2.5,
            .end = 5.0,
            .text = "Second segment",
        },
    };

    const result = GroqTranscriptionModel.TranscriptionResult{
        .text = "Full transcription text",
        .segments = &segments,
        .language = "en",
        .duration = 5.0,
    };

    try std.testing.expectEqualStrings("Full transcription text", result.text);
    try std.testing.expect(result.segments != null);
    try std.testing.expect(result.segments.?.len == 2);
    try std.testing.expect(result.language != null);
    try std.testing.expectEqualStrings("en", result.language.?);
    try std.testing.expect(result.duration != null);
    try std.testing.expectEqual(@as(f64, 5.0), result.duration.?);
}

test "GroqTranscriptionModel TranscriptionResult minimal" {
    const result = GroqTranscriptionModel.TranscriptionResult{
        .text = "Basic transcription",
        .segments = null,
        .language = null,
        .duration = null,
    };

    try std.testing.expectEqualStrings("Basic transcription", result.text);
    try std.testing.expect(result.segments == null);
    try std.testing.expect(result.language == null);
    try std.testing.expect(result.duration == null);
}

test "GroqTranscriptionModel different response formats" {
    const formats = [_]GroqTranscriptionModel.ResponseFormat{
        .json,
        .text,
        .srt,
        .verbose_json,
        .vtt,
    };

    for (formats) |format| {
        const str = format.toString();
        try std.testing.expect(str.len > 0);
    }
}

test "GroqTranscriptionModel TranscriptionOptions with various languages" {
    const languages = [_][]const u8{
        "en", // English
        "es", // Spanish
        "fr", // French
        "de", // German
        "zh", // Chinese
        "ja", // Japanese
    };

    for (languages) |lang| {
        const options = GroqTranscriptionModel.TranscriptionOptions{
            .language = lang,
        };
        try std.testing.expect(options.language != null);
        try std.testing.expectEqualStrings(lang, options.language.?);
    }
}
