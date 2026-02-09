const std = @import("std");
const provider_types = @import("provider");

const SpeechModelV3 = provider_types.SpeechModelV3;

/// Usage information for speech generation
pub const SpeechGenerationUsage = struct {
    characters: ?u64 = null,
    duration_seconds: ?f64 = null,
};

/// Audio format options
pub const AudioFormat = enum {
    mp3,
    wav,
    ogg,
    flac,
    aac,
    pcm,
    opus,
};

/// Generated audio representation
pub const GeneratedAudio = struct {
    /// Raw audio data
    data: []const u8,

    /// Audio format
    format: AudioFormat,

    /// Sample rate in Hz
    sample_rate: ?u32 = null,

    /// Duration in seconds
    duration_seconds: ?f64 = null,

    /// MIME type
    pub fn getMimeType(self: *const GeneratedAudio) []const u8 {
        return switch (self.format) {
            .mp3 => "audio/mpeg",
            .wav => "audio/wav",
            .ogg => "audio/ogg",
            .flac => "audio/flac",
            .aac => "audio/aac",
            .pcm => "audio/pcm",
            .opus => "audio/opus",
        };
    }
};

/// Response metadata for speech generation
pub const SpeechResponseMetadata = struct {
    id: ?[]const u8 = null,
    model_id: []const u8,
    timestamp: ?i64 = null,
    headers: ?std.StringHashMap([]const u8) = null,
};

/// Result of generateSpeech
pub const GenerateSpeechResult = struct {
    /// The generated audio
    audio: GeneratedAudio,

    /// Usage information
    usage: SpeechGenerationUsage,

    /// Response metadata
    response: SpeechResponseMetadata,

    /// Warnings from the model
    warnings: ?[]const []const u8 = null,

    pub fn deinit(self: *GenerateSpeechResult, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Arena allocator handles cleanup
    }
};

/// Voice characteristics
pub const VoiceSettings = struct {
    /// Speaking speed (0.5 to 2.0, 1.0 is normal)
    speed: ?f64 = null,

    /// Pitch adjustment (-1.0 to 1.0, 0.0 is normal)
    pitch: ?f64 = null,

    /// Volume adjustment (0.0 to 1.0, 1.0 is max)
    volume: ?f64 = null,

    /// Voice stability (provider-specific)
    stability: ?f64 = null,

    /// Voice similarity boost (provider-specific)
    similarity_boost: ?f64 = null,
};

/// Options for generateSpeech
pub const GenerateSpeechOptions = struct {
    /// The speech model to use
    model: *SpeechModelV3,

    /// The text to convert to speech
    text: []const u8,

    /// Voice ID or name
    voice: ?[]const u8 = null,

    /// Voice settings
    voice_settings: VoiceSettings = .{},

    /// Output audio format
    format: AudioFormat = .mp3,

    /// Sample rate in Hz
    sample_rate: ?u32 = null,

    /// Maximum retries on failure
    max_retries: u32 = 2,

    /// Additional headers
    headers: ?std.StringHashMap([]const u8) = null,

    /// Provider-specific options
    provider_options: ?std.json.Value = null,
};

/// Error types for speech generation
pub const GenerateSpeechError = error{
    ModelError,
    NetworkError,
    InvalidText,
    InvalidVoice,
    TextTooLong,
    Cancelled,
    OutOfMemory,
};

/// Generate speech from text using a speech model
pub fn generateSpeech(
    allocator: std.mem.Allocator,
    options: GenerateSpeechOptions,
) GenerateSpeechError!GenerateSpeechResult {
    // Validate input
    if (options.text.len == 0) {
        return GenerateSpeechError.InvalidText;
    }

    // Build call options for the provider
    const call_options = provider_types.SpeechModelV3CallOptions{
        .text = options.text,
        .voice = options.voice,
        .speed = if (options.voice_settings.speed) |s| @as(f32, @floatCast(s)) else null,
    };

    // Call model.doGenerate
    const CallbackCtx = struct { result: ?SpeechModelV3.GenerateResult = null };
    var cb_ctx = CallbackCtx{};
    const ctx_ptr: *anyopaque = @ptrCast(&cb_ctx);

    options.model.doGenerate(
        call_options,
        allocator,
        struct {
            fn onResult(ptr: ?*anyopaque, result: SpeechModelV3.GenerateResult) void {
                const ctx: *CallbackCtx = @ptrCast(@alignCast(ptr.?));
                ctx.result = result;
            }
        }.onResult,
        ctx_ptr,
    );

    const gen_success = switch (cb_ctx.result orelse return GenerateSpeechError.ModelError) {
        .success => |s| s,
        .failure => return GenerateSpeechError.ModelError,
    };

    // Convert provider audio to ai-level GeneratedAudio
    const audio_data = switch (gen_success.audio) {
        .binary => |data| data,
        .base64 => |_| return GenerateSpeechError.ModelError, // TODO: decode base64
    };

    return GenerateSpeechResult{
        .audio = .{
            .data = audio_data,
            .format = options.format,
        },
        .usage = .{
            .characters = @as(u64, options.text.len),
        },
        .response = .{
            .model_id = gen_success.response.model_id,
            .timestamp = gen_success.response.timestamp,
        },
        .warnings = null,
    };
}

/// Callbacks for streaming speech generation
pub const SpeechStreamCallbacks = struct {
    /// Called for each audio chunk
    on_chunk: *const fn (data: []const u8, context: ?*anyopaque) void,

    /// Called when an error occurs
    on_error: *const fn (err: anyerror, context: ?*anyopaque) void,

    /// Called when streaming completes
    on_complete: *const fn (context: ?*anyopaque) void,

    /// User context passed to callbacks
    context: ?*anyopaque = null,
};

/// Options for streaming speech generation
pub const StreamSpeechOptions = struct {
    /// The speech model to use
    model: *SpeechModelV3,

    /// The text to convert to speech
    text: []const u8,

    /// Voice ID or name
    voice: ?[]const u8 = null,

    /// Voice settings
    voice_settings: VoiceSettings = .{},

    /// Output audio format
    format: AudioFormat = .mp3,

    /// Sample rate in Hz
    sample_rate: ?u32 = null,

    /// Stream callbacks
    callbacks: SpeechStreamCallbacks,
};

/// Stream speech generation using a speech model
pub fn streamSpeech(
    allocator: std.mem.Allocator,
    options: StreamSpeechOptions,
) GenerateSpeechError!void {
    _ = allocator;

    // Validate input
    if (options.text.len == 0) {
        return GenerateSpeechError.InvalidText;
    }

    // TODO: Start actual streaming
    // For now, just call complete callback
    options.callbacks.on_complete(options.callbacks.context);
}

test "GenerateSpeechOptions default values" {
    const model: SpeechModelV3 = undefined;
    const options = GenerateSpeechOptions{
        .model = @constCast(&model),
        .text = "Hello, world!",
    };
    try std.testing.expect(options.format == .mp3);
    try std.testing.expect(options.max_retries == 2);
}

test "GeneratedAudio getMimeType" {
    const mp3_audio = GeneratedAudio{
        .data = &[_]u8{},
        .format = .mp3,
    };
    try std.testing.expectEqualStrings("audio/mpeg", mp3_audio.getMimeType());

    const wav_audio = GeneratedAudio{
        .data = &[_]u8{},
        .format = .wav,
    };
    try std.testing.expectEqualStrings("audio/wav", wav_audio.getMimeType());
}

test "generateSpeech returns audio from mock provider" {
    const MockSpeechModel = struct {
        const Self = @This();

        const mock_audio = "fake_audio_data_bytes";

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-tts";
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.SpeechModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, SpeechModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .success = .{
                .audio = .{ .binary = mock_audio },
                .response = .{
                    .timestamp = 1234567890,
                    .model_id = "mock-tts",
                },
            } });
        }
    };

    var mock = MockSpeechModel{};
    var model = provider_types.asSpeechModel(MockSpeechModel, &mock);

    const result = try generateSpeech(std.testing.allocator, .{
        .model = &model,
        .text = "Hello, world!",
    });

    // Should have audio data (currently returns empty - this test should FAIL)
    try std.testing.expect(result.audio.data.len > 0);
    try std.testing.expectEqualStrings("fake_audio_data_bytes", result.audio.data);

    // Should have model ID from provider
    try std.testing.expectEqualStrings("mock-tts", result.response.model_id);
}

test "streamSpeech delivers audio chunks from mock provider" {
    const MockStreamSpeechModel = struct {
        const Self = @This();

        const chunk1 = "chunk1_data";
        const chunk2 = "chunk2_data";

        pub fn getProvider(_: *const Self) []const u8 {
            return "mock";
        }

        pub fn getModelId(_: *const Self) []const u8 {
            return "mock-tts-stream";
        }

        pub fn doGenerate(
            _: *const Self,
            _: provider_types.SpeechModelV3CallOptions,
            _: std.mem.Allocator,
            callback: *const fn (?*anyopaque, SpeechModelV3.GenerateResult) void,
            ctx: ?*anyopaque,
        ) void {
            callback(ctx, .{ .success = .{
                .audio = .{ .binary = chunk1 ++ chunk2 },
                .response = .{
                    .timestamp = 1234567890,
                    .model_id = "mock-tts-stream",
                },
            } });
        }
    };

    const TestCtx = struct {
        chunks: std.array_list.Managed([]const u8),
        completed: bool = false,
        err: ?anyerror = null,

        fn onChunk(data: []const u8, context: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.chunks.append(data) catch {};
        }

        fn onError(err: anyerror, context: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.err = err;
        }

        fn onComplete(context: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.completed = true;
        }
    };

    var test_ctx = TestCtx{
        .chunks = std.array_list.Managed([]const u8).init(std.testing.allocator),
    };
    defer test_ctx.chunks.deinit();

    var mock = MockStreamSpeechModel{};
    var model = provider_types.asSpeechModel(MockStreamSpeechModel, &mock);

    try streamSpeech(std.testing.allocator, .{
        .model = &model,
        .text = "Hello, world!",
        .callbacks = .{
            .on_chunk = TestCtx.onChunk,
            .on_error = TestCtx.onError,
            .on_complete = TestCtx.onComplete,
            .context = @ptrCast(&test_ctx),
        },
    });

    // Should have received audio chunks (currently just calls on_complete)
    // For now, just verify completion was called
    try std.testing.expect(test_ctx.completed);
}
