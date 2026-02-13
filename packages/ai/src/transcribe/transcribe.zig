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

    /// Request context for timeout/cancellation
    request_context: ?*const @import("../context.zig").RequestContext = null,

    /// Retry policy for automatic retries
    retry_policy: ?@import("../retry.zig").RetryPolicy = null,

    /// Error diagnostic out-parameter for rich error context on failure.
    error_diagnostic: ?*provider_types.ErrorDiagnostic = null,
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

/// Read audio data from a local file path.
fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 100 * 1024 * 1024); // 100MB max
}

/// Fetch audio data from a URL using the standard HTTP client.
fn fetchUrl(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var response_body: std.Io.Writer.Allocating = .init(allocator);

    const result = client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &response_body.writer,
    }) catch return error.NetworkError;

    if (result.status != .ok) return error.NetworkError;

    return response_body.toOwnedSlice() catch return error.OutOfMemory;
}

/// Transcribe audio using a transcription model
pub fn transcribe(
    allocator: std.mem.Allocator,
    options: TranscribeOptions,
) TranscribeError!TranscribeResult {
    // Check request context for cancellation/timeout
    if (options.request_context) |ctx| {
        if (ctx.isDone()) return TranscribeError.Cancelled;
    }

    // Validate input and extract audio data
    // Track whether we allocated temporary audio data that needs freeing
    var temp_audio_buf: ?[]const u8 = null;
    defer if (temp_audio_buf) |buf| allocator.free(buf);

    const audio_data: provider_types.TranscriptionModelV3CallOptions.AudioData = switch (options.audio) {
        .data => |d| blk: {
            if (d.data.len == 0) return TranscribeError.InvalidAudio;
            break :blk .{ .binary = d.data };
        },
        .url => |u| blk: {
            if (u.len == 0) return TranscribeError.InvalidAudio;
            const fetched = fetchUrl(allocator, u) catch return TranscribeError.NetworkError;
            temp_audio_buf = fetched;
            break :blk .{ .binary = fetched };
        },
        .file => |f| blk: {
            if (f.len == 0) return TranscribeError.InvalidAudio;
            const contents = readFile(allocator, f) catch return TranscribeError.InvalidAudio;
            temp_audio_buf = contents;
            break :blk .{ .binary = contents };
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
        .error_diagnostic = options.error_diagnostic,
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

/// Parse an SRT timestamp "HH:MM:SS,mmm" to seconds
fn parseSrtTimestamp(s: []const u8) ?f64 {
    // Format: "HH:MM:SS,mmm"
    if (s.len < 12) return null;
    const hours = std.fmt.parseFloat(f64, s[0..2]) catch return null;
    const minutes = std.fmt.parseFloat(f64, s[3..5]) catch return null;
    const seconds = std.fmt.parseFloat(f64, s[6..8]) catch return null;
    const millis = std.fmt.parseFloat(f64, s[9..12]) catch return null;
    return hours * 3600.0 + minutes * 60.0 + seconds + millis / 1000.0;
}

/// Convert SRT format to segments
pub fn parseSrt(
    allocator: std.mem.Allocator,
    srt_content: []const u8,
) ![]TranscriptionSegment {
    var segments = std.ArrayList(TranscriptionSegment).empty;

    var lines = std.mem.splitScalar(u8, srt_content, '\n');
    var current_segment: ?TranscriptionSegment = null;
    var text_buffer = std.ArrayList(u8).empty;
    var state: enum { index, timing, text } = .index;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");

        if (trimmed.len == 0) {
            // Empty line - end of segment
            if (current_segment) |*seg| {
                seg.text = try text_buffer.toOwnedSlice(allocator);
                try segments.append(allocator, seg.*);
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
                if (std.mem.indexOf(u8, trimmed, " --> ")) |arrow_pos| {
                    const start_str = trimmed[0..arrow_pos];
                    const end_str = trimmed[arrow_pos + 5 ..];
                    if (current_segment) |*seg| {
                        seg.start = parseSrtTimestamp(start_str) orelse 0;
                        seg.end = parseSrtTimestamp(end_str) orelse 0;
                    }
                }
                state = .text;
            },
            .text => {
                // Accumulate text
                if (text_buffer.items.len > 0) {
                    try text_buffer.append(allocator, ' ');
                }
                try text_buffer.appendSlice(allocator, trimmed);
            },
        }
    }

    // Handle last segment
    if (current_segment) |*seg| {
        seg.text = try text_buffer.toOwnedSlice(allocator);
        try segments.append(allocator, seg.*);
    }

    return segments.toOwnedSlice(allocator);
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

test "transcribe reads audio from file source" {
    const MockTranscriptionModel = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-transcribe-file";
        }

        pub fn doGenerate(
            _: *const Self,
            call_opts: provider_types.TranscriptionModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, TranscriptionModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            // Verify audio data was read from the file (not just the path string)
            const audio_bytes = call_opts.audio.binary;
            // The file should contain actual content, not just the file path
            if (audio_bytes.len > 0 and !std.mem.eql(u8, audio_bytes, "/tmp/test_audio.wav")) {
                callback(ctx, .{ .success = .{
                    .text = "transcribed from file",
                    .segments = &[_]provider_types.TranscriptionSegment{},
                    .language = "en",
                    .duration_in_seconds = 1.0,
                    .response = .{
                        .timestamp = 1234567890,
                        .model_id = "mock-transcribe-file",
                    },
                } });
            } else {
                callback(ctx, .{ .failure = error.ModelError });
            }
        }
    };

    // Create a temporary audio file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const audio_content = "RIFF\x00\x00\x00\x00WAVEfmt fake_audio_content";
    try tmp_dir.dir.writeFile(.{ .sub_path = "test_audio.wav", .data = audio_content });

    // Get the full path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const full_path = try tmp_dir.dir.realpath("test_audio.wav", &path_buf);

    var mock = MockTranscriptionModel{};
    var model = provider_types.asTranscriptionModel(MockTranscriptionModel, &mock);

    const result = try transcribe(std.testing.allocator, .{
        .model = &model,
        .audio = .{ .file = full_path },
    });

    try std.testing.expectEqualStrings("transcribed from file", result.text);
    try std.testing.expectEqualStrings("mock-transcribe-file", result.response.model_id);
}

test "transcribe returns InvalidAudio on empty file path" {
    const MockModel = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.TranscriptionModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, TranscriptionModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.ModelError });
        }
    };

    var mock = MockModel{};
    var model = provider_types.asTranscriptionModel(MockModel, &mock);

    const result = transcribe(std.testing.allocator, .{
        .model = &model,
        .audio = .{ .file = "" },
    });
    try std.testing.expectError(TranscribeError.InvalidAudio, result);
}

test "transcribe returns InvalidAudio on nonexistent file" {
    const MockModel = struct {
        const Self = @This();

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.TranscriptionModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, TranscriptionModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .failure = error.ModelError });
        }
    };

    var mock = MockModel{};
    var model = provider_types.asTranscriptionModel(MockModel, &mock);

    const result = transcribe(std.testing.allocator, .{
        .model = &model,
        .audio = .{ .file = "/nonexistent/path/audio.wav" },
    });
    try std.testing.expectError(TranscribeError.InvalidAudio, result);
}
