const std = @import("std");
const shared = @import("../../shared/v3/index.zig");
const json_value = @import("../../json-value/index.zig");
const ErrorDiagnostic = @import("../../errors/diagnostic.zig").ErrorDiagnostic;

/// Call options for transcription
pub const TranscriptionModelV3CallOptions = struct {
    /// Audio data to transcribe.
    /// Accepts binary data or base64 encoded string.
    audio: AudioData,

    /// The IANA media type of the audio data.
    media_type: []const u8,

    /// Additional provider-specific options.
    provider_options: ?json_value.JsonObject = null,

    /// Additional HTTP headers to be sent with the request.
    headers: ?std.StringHashMap([]const u8) = null,

    /// Error diagnostic out-parameter for rich error context on failure.
    error_diagnostic: ?*ErrorDiagnostic = null,

    pub const AudioData = union(enum) {
        binary: []const u8,
        base64: []const u8,
    };
};

/// Transcription segment with timing information
pub const TranscriptionSegment = struct {
    /// The text content of this segment.
    text: []const u8,

    /// The start time of this segment in seconds.
    start_second: f64,

    /// The end time of this segment in seconds.
    end_second: f64,
};

/// Transcription model specification version 3.
pub const TranscriptionModelV3 = struct {
    /// VTable for dynamic dispatch
    vtable: *const VTable,
    /// Implementation pointer
    impl: *anyopaque,

    pub const specification_version = "v3";

    /// Virtual function table for transcription model operations
    pub const VTable = struct {
        /// Get the provider name
        getProvider: *const fn (*anyopaque) []const u8,

        /// Get the model ID
        getModelId: *const fn (*anyopaque) []const u8,

        /// Generate transcription
        doGenerate: *const fn (
            *anyopaque,
            TranscriptionModelV3CallOptions,
            std.mem.Allocator,
            *const fn (?*anyopaque, GenerateResult) void,
            ?*anyopaque,
        ) void,
    };

    /// Result of transcription
    pub const GenerateResult = union(enum) {
        success: GenerateSuccess,
        failure: anyerror,
    };

    /// Successful transcription result
    pub const GenerateSuccess = struct {
        /// The complete transcribed text from the audio.
        text: []const u8,

        /// Array of transcript segments with timing information.
        segments: []const TranscriptionSegment,

        /// The detected language of the audio content (ISO-639-1 code).
        language: ?[]const u8 = null,

        /// The total duration of the audio file in seconds.
        duration_in_seconds: ?f64 = null,

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
        body: ?[]const u8 = null,
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

    /// Generate transcription
    pub fn doGenerate(
        self: Self,
        options: TranscriptionModelV3CallOptions,
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

/// Helper to implement a transcription model from a concrete type
pub fn implementTranscriptionModel(comptime T: type) TranscriptionModelV3.VTable {
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
                options: TranscriptionModelV3CallOptions,
                allocator: std.mem.Allocator,
                callback: *const fn (?*anyopaque, TranscriptionModelV3.GenerateResult) void,
                ctx: ?*anyopaque,
            ) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.doGenerate(options, allocator, callback, ctx);
            }
        }.doGenerate,
    };
}

/// Create a TranscriptionModelV3 from a concrete implementation
pub fn asTranscriptionModel(comptime T: type, impl: *T) TranscriptionModelV3 {
    const vtable = comptime implementTranscriptionModel(T);
    return .{
        .vtable = &vtable,
        .impl = impl,
    };
}

test "TranscriptionModelV3 specification_version" {
    try std.testing.expectEqualStrings("v3", TranscriptionModelV3.specification_version);
}
