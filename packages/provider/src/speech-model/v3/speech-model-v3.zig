const std = @import("std");
const shared = @import("../../shared/v3/index.zig");
const json_value = @import("../../json-value/index.zig");
const ErrorDiagnostic = @import("../../errors/diagnostic.zig").ErrorDiagnostic;

/// Call options for speech generation
pub const SpeechModelV3CallOptions = struct {
    /// Text to convert to speech.
    text: []const u8,

    /// The voice to use for speech synthesis.
    /// This is provider-specific and may be a voice ID, name, or other identifier.
    voice: ?[]const u8 = null,

    /// The desired output format for the audio e.g. "mp3", "wav", etc.
    output_format: ?[]const u8 = null,

    /// Instructions for the speech generation e.g. "Speak in a slow and steady tone".
    instructions: ?[]const u8 = null,

    /// The speed of the speech generation.
    speed: ?f32 = null,

    /// The language for speech generation. ISO 639-1 language code (e.g. "en", "es", "fr")
    /// or "auto" for automatic language detection.
    language: ?[]const u8 = null,

    /// Additional provider-specific options.
    provider_options: ?json_value.JsonObject = null,

    /// Additional HTTP headers to be sent with the request.
    headers: ?std.StringHashMap([]const u8) = null,

    /// Error diagnostic out-parameter for rich error context on failure.
    error_diagnostic: ?*ErrorDiagnostic = null,
};

/// Speech model specification version 3.
pub const SpeechModelV3 = struct {
    /// VTable for dynamic dispatch
    vtable: *const VTable,
    /// Implementation pointer
    impl: *anyopaque,

    pub const specification_version = "v3";

    /// Virtual function table for speech model operations
    pub const VTable = struct {
        /// Get the provider name
        getProvider: *const fn (*anyopaque) []const u8,

        /// Get the model ID
        getModelId: *const fn (*anyopaque) []const u8,

        /// Generate speech
        doGenerate: *const fn (
            *anyopaque,
            SpeechModelV3CallOptions,
            std.mem.Allocator,
            *const fn (?*anyopaque, GenerateResult) void,
            ?*anyopaque,
        ) void,
    };

    /// Result of speech generation
    pub const GenerateResult = union(enum) {
        success: GenerateSuccess,
        failure: anyerror,
    };

    /// Audio data
    pub const AudioData = union(enum) {
        /// Base64 encoded audio
        base64: []const u8,
        /// Binary audio data
        binary: []const u8,
    };

    /// Successful generation result
    pub const GenerateSuccess = struct {
        /// Generated audio.
        audio: AudioData,

        /// Warnings for the call.
        warnings: []const shared.SharedV3Warning = &[_]shared.SharedV3Warning{},

        /// Optional request information.
        request: ?RequestInfo = null,

        /// Response information.
        response: ResponseInfo,

        /// Additional provider-specific metadata.
        provider_metadata: ?json_value.JsonObject = null,
    };

    /// Request information
    pub const RequestInfo = struct {
        body: ?json_value.JsonValue = null,
    };

    /// Response information
    pub const ResponseInfo = struct {
        /// Timestamp for the start of the generated response.
        timestamp: i64,

        /// The ID of the response model.
        model_id: []const u8,

        /// Response headers.
        headers: ?shared.SharedV3Headers = null,

        /// Response body.
        body: ?json_value.JsonValue = null,
    };

    const Self = @This();

    /// Get the provider name
    pub fn getProvider(self: Self) []const u8 {
        return self.vtable.getProvider(self.impl);
    }

    /// Get the model ID
    pub fn getModelId(self: Self) []const u8 {
        return self.vtable.getModelId(self.impl);
    }

    /// Generate speech
    pub fn doGenerate(
        self: Self,
        options: SpeechModelV3CallOptions,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, GenerateResult) void,
        ctx: ?*anyopaque,
    ) void {
        self.vtable.doGenerate(self.impl, options, allocator, callback, ctx);
    }

    /// Get a string identifier for this model
    pub fn getId(self: Self, allocator: std.mem.Allocator) ![]u8 {
        const provider = self.getProvider();
        const model_id = self.getModelId();
        return std.fmt.allocPrint(allocator, "{s}:{s}", .{ provider, model_id });
    }
};

/// Helper to implement a speech model from a concrete type
pub fn implementSpeechModel(comptime T: type) SpeechModelV3.VTable {
    return .{
        .getProvider = struct {
            fn getProvider(ptr: *anyopaque) []const u8 {
                const self: *T = @ptrCast(@alignCast(ptr));
                return self.getProvider();
            }
        }.getProvider,

        .getModelId = struct {
            fn getModelId(ptr: *anyopaque) []const u8 {
                const self: *T = @ptrCast(@alignCast(ptr));
                return self.getModelId();
            }
        }.getModelId,

        .doGenerate = struct {
            fn doGenerate(
                ptr: *anyopaque,
                options: SpeechModelV3CallOptions,
                allocator: std.mem.Allocator,
                callback: *const fn (?*anyopaque, SpeechModelV3.GenerateResult) void,
                ctx: ?*anyopaque,
            ) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.doGenerate(options, allocator, callback, ctx);
            }
        }.doGenerate,
    };
}

/// Create a SpeechModelV3 from a concrete implementation
pub fn asSpeechModel(comptime T: type, impl: *T) SpeechModelV3 {
    const vtable = comptime implementSpeechModel(T);
    return .{
        .vtable = &vtable,
        .impl = impl,
    };
}

test "SpeechModelV3 specification_version" {
    try std.testing.expectEqualStrings("v3", SpeechModelV3.specification_version);
}

test "SpeechModelV3CallOptions basic" {
    const options = SpeechModelV3CallOptions{
        .text = "Hello, world!",
        .voice = "en-US-Standard-A",
    };
    try std.testing.expectEqualStrings("Hello, world!", options.text);
    try std.testing.expectEqualStrings("en-US-Standard-A", options.voice.?);
}
