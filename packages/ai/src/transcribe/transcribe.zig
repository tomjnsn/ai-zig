const std = @import("std");
const provider_types = @import("provider");

const TranscriptionModelV3 = provider_types.TranscriptionModelV3;

/// Usage information for transcription
pub const TranscriptionUsage = struct {
    duration_seconds: ?f64 = null,
    characters: ?u64 = null,
};

/// A single word with timing information
pub const TranscriptionWord = struct {
    word: []const u8,
    start: f64,
    end: f64,
    confidence: ?f64 = null,
    speaker: ?[]const u8 = null,
};

/// A segment of the transcription
pub const TranscriptionSegment = struct {
    id: ?u32 = null,
    text: []const u8,
    start: f64,
    end: f64,
    words: ?[]const TranscriptionWord = null,
    speaker: ?[]const u8 = null,
    confidence: ?f64 = null,
    language: ?[]const u8 = null,
};

/// Response metadata for transcription
pub const TranscriptionResponseMetadata = struct {
    id: ?[]const u8 = null,
    model_id: []const u8,
    timestamp: ?i64 = null,
    headers: ?std.StringHashMap([]const u8) = null,
};

/// Result of transcribe
pub const TranscribeResult = struct {
    /// The full transcription text
    text: []const u8,

    /// Segments with timing information
    segments: ?[]const TranscriptionSegment = null,

    /// Words with timing information
    words: ?[]const TranscriptionWord = null,

    /// Detected language
    language: ?[]const u8 = null,

    /// Language detection confidence
    language_confidence: ?f64 = null,

    /// Duration of the audio in seconds
    duration_seconds: ?f64 = null,

    /// Usage information
    usage: TranscriptionUsage,

    /// Response metadata
    response: TranscriptionResponseMetadata,

    /// Warnings from the model
    warnings: ?[]const []const u8 = null,

    pub fn deinit(self: *TranscribeResult, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Arena allocator handles cleanup
    }
};

/// Audio input source
pub const AudioSource = union(enum) {
    /// Raw audio data
    data: AudioData,
    /// URL to audio file
    url: []const u8,
    /// File path
    file: []const u8,
};

pub const AudioData = struct {
    data: []const u8,
    mime_type: []const u8,
};

/// Options for transcribe
pub const TranscribeOptions = struct {
    /// The transcription model to use
    model: *TranscriptionModelV3,

    /// The audio to transcribe
    audio: AudioSource,

    /// Language of the audio (ISO 639-1 code)
    language: ?[]const u8 = null,

    /// Enable automatic language detection
    detect_language: ?bool = null,

    /// Prompt to guide the transcription
    prompt: ?[]const u8 = null,

    /// Enable word-level timestamps
    timestamps: ?TimestampGranularity = null,

    /// Enable speaker diarization
    diarization: ?bool = null,

    /// Maximum number of speakers (for diarization)
    max_speakers: ?u32 = null,

    /// Output format
    format: TranscriptionFormat = .json,

    /// Temperature for sampling
    temperature: ?f64 = null,

    /// Maximum retries on failure
    max_retries: u32 = 2,

    /// Additional headers
    headers: ?std.StringHashMap([]const u8) = null,

    /// Provider-specific options
    provider_options: ?std.json.Value = null,
};

pub const TimestampGranularity = enum {
    word,
    segment,
};

pub const TranscriptionFormat = enum {
    json,
    text,
    srt,
    vtt,
    verbose_json,
};

/// Error types for transcription
pub const TranscribeError = error{
    ModelError,
    NetworkError,
    InvalidAudio,
    AudioTooLong,
    UnsupportedFormat,
    Cancelled,
    OutOfMemory,
};

/// Transcribe audio using a transcription model
pub fn transcribe(
    allocator: std.mem.Allocator,
    options: TranscribeOptions,
) TranscribeError!TranscribeResult {
    // Validate input and extract audio data
    const audio_data: provider_types.TranscriptionModelV3CallOptions.AudioData = switch (options.audio) {
        .data => |d| blk: {
            if (d.data.len == 0) return TranscribeError.InvalidAudio;
            break :blk .{ .binary = d.data };
        },
        .url => |u| blk: {
            if (u.len == 0) return TranscribeError.InvalidAudio;
            break :blk .{ .binary = u }; // TODO: fetch URL
        },
        .file => |f| blk: {
            if (f.len == 0) return TranscribeError.InvalidAudio;
            break :blk .{ .binary = f }; // TODO: read file
        },
    };

    const media_type = switch (options.audio) {
        .data => |d| d.mime_type,
        else => "audio/mpeg",
    };

    // Build call options for the provider
    const call_options = provider_types.TranscriptionModelV3CallOptions{
        .audio = audio_data,
        .media_type = media_type,
    };

    // Call model.doGenerate
    const CallbackCtx = struct { result: ?TranscriptionModelV3.GenerateResult = null };
    var cb_ctx = CallbackCtx{};
    const ctx_ptr: *anyopaque = @ptrCast(&cb_ctx);

    options.model.doGenerate(
        call_options,
        allocator,
        struct {
            fn onResult(ptr: ?*anyopaque, result: TranscriptionModelV3.GenerateResult) void {
                const ctx: *CallbackCtx = @ptrCast(@alignCast(ptr.?));
                ctx.result = result;
            }
        }.onResult,
        ctx_ptr,
    );

    const gen_success = switch (cb_ctx.result orelse return TranscribeError.ModelError) {
        .success => |s| s,
        .failure => return TranscribeError.ModelError,
    };

    return TranscribeResult{
        .text = gen_success.text,
        .language = gen_success.language,
        .duration_seconds = gen_success.duration_in_seconds,
        .usage = .{
            .duration_seconds = gen_success.duration_in_seconds,
        },
        .response = .{
            .model_id = gen_success.response.model_id,
            .timestamp = gen_success.response.timestamp,
        },
        .warnings = null,
    };
}

/// Convert SRT format to segments
pub fn parseSrt(
    allocator: std.mem.Allocator,
    srt_content: []const u8,
) ![]TranscriptionSegment {
    var segments = std.array_list.Managed(TranscriptionSegment).init(allocator);

    var lines = std.mem.splitScalar(u8, srt_content, '\n');
    var current_segment: ?TranscriptionSegment = null;
    var text_buffer = std.array_list.Managed(u8).init(allocator);
    var state: enum { index, timing, text } = .index;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");

        if (trimmed.len == 0) {
            // Empty line - end of segment
            if (current_segment) |*seg| {
                seg.text = try text_buffer.toOwnedSlice();
                try segments.append(seg.*);
                current_segment = null;
            }
            state = .index;
            continue;
        }

        switch (state) {
            .index => {
                // Parse segment index
                const idx = std.fmt.parseInt(u32, trimmed, 10) catch continue;
                current_segment = TranscriptionSegment{
                    .id = idx,
                    .text = "",
                    .start = 0,
                    .end = 0,
                };
                text_buffer.clearRetainingCapacity();
                state = .timing;
            },
            .timing => {
                // Parse timing line: "00:00:00,000 --> 00:00:02,500"
                // TODO: Implement proper SRT timing parsing
                state = .text;
            },
            .text => {
                // Accumulate text
                if (text_buffer.items.len > 0) {
                    try text_buffer.append(' ');
                }
                try text_buffer.appendSlice(trimmed);
            },
        }
    }

    // Handle last segment
    if (current_segment) |*seg| {
        seg.text = try text_buffer.toOwnedSlice();
        try segments.append(seg.*);
    }

    return segments.toOwnedSlice();
}

test "TranscribeOptions default values" {
    const model: TranscriptionModelV3 = undefined;
    const options = TranscribeOptions{
        .model = @constCast(&model),
        .audio = .{ .url = "https://example.com/audio.mp3" },
    };
    try std.testing.expect(options.format == .json);
    try std.testing.expect(options.max_retries == 2);
}

test "AudioSource union" {
    const url_source = AudioSource{ .url = "https://example.com/audio.mp3" };
    switch (url_source) {
        .url => |u| try std.testing.expectEqualStrings("https://example.com/audio.mp3", u),
        else => try std.testing.expect(false),
    }

    const data_source = AudioSource{
        .data = .{
            .data = "audio data",
            .mime_type = "audio/mp3",
        },
    };
    switch (data_source) {
        .data => |d| {
            try std.testing.expectEqualStrings("audio data", d.data);
            try std.testing.expectEqualStrings("audio/mp3", d.mime_type);
        },
        else => try std.testing.expect(false),
    }
}

test "transcribe returns text from mock provider" {
    const MockTranscriptionModel = struct {
        const Self = @This();

        const mock_segments = [_]provider_types.TranscriptionSegment{
            .{ .text = "Hello world", .start_second = 0.0, .end_second = 1.5 },
            .{ .text = "How are you", .start_second = 1.5, .end_second = 3.0 },
        };

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-transcribe";
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.TranscriptionModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, TranscriptionModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .success = .{
                .text = "Hello world How are you",
                .segments = &mock_segments,
                .language = "en",
                .duration_in_seconds = 3.0,
                .response = .{
                    .timestamp = 1234567890,
                    .model_id = "mock-transcribe",
                },
            } });
        }
    };

    var mock = MockTranscriptionModel{};
    var model = provider_types.asTranscriptionModel(MockTranscriptionModel, &mock);

    const result = try transcribe(std.testing.allocator, .{
        .model = &model,
        .audio = .{ .data = .{ .data = "fake_audio", .mime_type = "audio/mp3" } },
    });

    // Should have transcription text (currently returns empty - this test should FAIL)
    try std.testing.expectEqualStrings("Hello world How are you", result.text);

    // Should have language
    try std.testing.expectEqualStrings("en", result.language.?);

    // Should have duration
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), result.duration_seconds.?, 0.001);

    // Should have model ID from provider
    try std.testing.expectEqualStrings("mock-transcribe", result.response.model_id);
}

test "parseSrt parses SRT format correctly" {
    const srt_content =
        \\1
        \\00:00:00,000 --> 00:00:02,500
        \\Hello world
        \\
        \\2
        \\00:00:02,500 --> 00:00:05,000
        \\How are you
        \\
    ;

    const segments = try parseSrt(std.testing.allocator, srt_content);
    defer {
        for (segments) |seg| {
            std.testing.allocator.free(seg.text);
        }
        std.testing.allocator.free(segments);
    }

    try std.testing.expectEqual(@as(usize, 2), segments.len);

    try std.testing.expectEqualStrings("Hello world", segments[0].text);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), segments[0].start, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), segments[0].end, 0.001);
    try std.testing.expectEqual(@as(?u32, 1), segments[0].id);

    try std.testing.expectEqualStrings("How are you", segments[1].text);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), segments[1].start, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), segments[1].end, 0.001);
    try std.testing.expectEqual(@as(?u32, 2), segments[1].id);
}
