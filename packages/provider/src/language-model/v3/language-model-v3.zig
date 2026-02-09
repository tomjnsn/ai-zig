const std = @import("std");
const shared = @import("../../shared/v3/index.zig");
const json_value = @import("../../json-value/index.zig");

const LanguageModelV3CallOptions = @import("language-model-v3-call-options.zig").LanguageModelV3CallOptions;
const LanguageModelV3Content = @import("language-model-v3-content.zig").LanguageModelV3Content;
const LanguageModelV3FinishReason = @import("language-model-v3-finish-reason.zig").LanguageModelV3FinishReason;
const LanguageModelV3Usage = @import("language-model-v3-usage.zig").LanguageModelV3Usage;
const LanguageModelV3StreamPart = @import("language-model-v3-stream-part.zig").LanguageModelV3StreamPart;
const LanguageModelV3ResponseMetadata = @import("language-model-v3-response-metadata.zig").LanguageModelV3ResponseMetadata;

/// Specification for a language model that implements the language model interface version 3.
///
/// ## Lifetime Requirements
/// This is a type-erased interface using vtable dispatch. The caller must ensure:
/// - `impl` must outlive every use of this `LanguageModelV3` value.
/// - `vtable` should point to a `const` with static lifetime (typically a file-level `const`).
/// - Do not store a `LanguageModelV3` beyond the lifetime of the concrete model it wraps.
///
/// ## Correct Usage
/// ```
/// var model = provider.languageModel("model-id");
/// const iface = model.asLanguageModel();  // borrows &model
/// // Use iface while model is alive
/// ```
pub const LanguageModelV3 = struct {
    /// VTable for dynamic dispatch (must have static lifetime)
    vtable: *const VTable,
    /// Type-erased implementation pointer (must outlive this struct)
    impl: *anyopaque,

    /// The language model must specify which language model interface version it implements.
    pub const specification_version = "v3";

    /// Virtual function table for language model operations
    pub const VTable = struct {
        /// Get the provider ID
        getProvider: *const fn (*anyopaque) []const u8,

        /// Get the model ID
        getModelId: *const fn (*anyopaque) []const u8,

        /// Get supported URL patterns by media type
        getSupportedUrls: *const fn (
            *anyopaque,
            std.mem.Allocator,
            *const fn (?*anyopaque, SupportedUrlsResult) void,
            ?*anyopaque,
        ) void,

        /// Generate a language model output (non-streaming)
        doGenerate: *const fn (
            *anyopaque,
            LanguageModelV3CallOptions,
            std.mem.Allocator,
            *const fn (?*anyopaque, GenerateResult) void,
            ?*anyopaque,
        ) void,

        /// Generate a language model output (streaming)
        doStream: *const fn (
            *anyopaque,
            LanguageModelV3CallOptions,
            std.mem.Allocator,
            StreamCallbacks,
        ) void,

        /// Optional: Cancel an ongoing operation
        cancel: ?*const fn (*anyopaque) void = null,
    };

    /// Result type for supported URLs
    pub const SupportedUrlsResult = union(enum) {
        success: std.StringHashMap([]const []const u8),
        failure: anyerror,
    };

    /// Result of doGenerate
    pub const GenerateResult = union(enum) {
        success: GenerateSuccess,
        failure: anyerror,
    };

    /// Successful generation result
    pub const GenerateSuccess = struct {
        /// Ordered content that the model has generated.
        content: []const LanguageModelV3Content,

        /// Finish reason.
        finish_reason: LanguageModelV3FinishReason,

        /// Usage information.
        usage: LanguageModelV3Usage,

        /// Additional provider-specific metadata.
        provider_metadata: ?shared.SharedV3ProviderMetadata = null,

        /// Optional request information for telemetry and debugging.
        request: ?RequestInfo = null,

        /// Optional response information for telemetry and debugging.
        response: ?ResponseInfo = null,

        /// Warnings for the call, e.g. unsupported settings.
        warnings: []const shared.SharedV3Warning = &[_]shared.SharedV3Warning{},
    };

    /// Request information
    pub const RequestInfo = struct {
        /// Request HTTP body that was sent to the provider API.
        body: ?json_value.JsonValue = null,
    };

    /// Response information
    pub const ResponseInfo = struct {
        /// Response metadata
        metadata: LanguageModelV3ResponseMetadata = .{},
        /// Response headers
        headers: ?shared.SharedV3Headers = null,
        /// Response HTTP body
        body: ?json_value.JsonValue = null,
    };

    /// Callbacks for streaming
    pub const StreamCallbacks = struct {
        /// Called for each stream part
        on_part: *const fn (?*anyopaque, LanguageModelV3StreamPart) void,
        /// Called when an error occurs
        on_error: *const fn (?*anyopaque, anyerror) void,
        /// Called when streaming completes
        on_complete: *const fn (?*anyopaque, ?StreamCompleteInfo) void,
        /// User context
        ctx: ?*anyopaque = null,
    };

    /// Information provided on stream completion
    pub const StreamCompleteInfo = struct {
        /// Request info
        request: ?RequestInfo = null,
        /// Response headers
        response_headers: ?shared.SharedV3Headers = null,
    };

    const Self = @This();

    // Public API methods that delegate to vtable

    /// Get the provider ID
    pub fn getProvider(self: Self) []const u8 {
        return self.vtable.getProvider(self.impl);
    }

    /// Get the model ID
    pub fn getModelId(self: Self) []const u8 {
        return self.vtable.getModelId(self.impl);
    }

    /// Get supported URL patterns
    pub fn getSupportedUrls(
        self: Self,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, SupportedUrlsResult) void,
        ctx: ?*anyopaque,
    ) void {
        self.vtable.getSupportedUrls(self.impl, allocator, callback, ctx);
    }

    /// Generate a response (non-streaming)
    pub fn doGenerate(
        self: Self,
        options: LanguageModelV3CallOptions,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, GenerateResult) void,
        ctx: ?*anyopaque,
    ) void {
        self.vtable.doGenerate(self.impl, options, allocator, callback, ctx);
    }

    /// Generate a response (streaming)
    pub fn doStream(
        self: Self,
        options: LanguageModelV3CallOptions,
        allocator: std.mem.Allocator,
        callbacks: StreamCallbacks,
    ) void {
        self.vtable.doStream(self.impl, options, allocator, callbacks);
    }

    /// Cancel an ongoing operation (if supported)
    pub fn cancel(self: Self) bool {
        if (self.vtable.cancel) |cancel_fn| {
            cancel_fn(self.impl);
            return true;
        }
        return false;
    }

    /// Get a string identifier for this model (provider:modelId)
    pub fn getId(self: Self, allocator: std.mem.Allocator) ![]u8 {
        const provider = self.getProvider();
        const model_id = self.getModelId();
        return std.fmt.allocPrint(allocator, "{s}:{s}", .{ provider, model_id });
    }
};

/// Helper to implement a language model from a concrete type
pub fn implementLanguageModel(comptime T: type) LanguageModelV3.VTable {
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

        .getSupportedUrls = struct {
            fn getSupportedUrls(
                ptr: *anyopaque,
                allocator: std.mem.Allocator,
                callback: *const fn (?*anyopaque, LanguageModelV3.SupportedUrlsResult) void,
                ctx: ?*anyopaque,
            ) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.getSupportedUrls(allocator, callback, ctx);
            }
        }.getSupportedUrls,

        .doGenerate = struct {
            fn doGenerate(
                ptr: *anyopaque,
                options: LanguageModelV3CallOptions,
                allocator: std.mem.Allocator,
                callback: *const fn (?*anyopaque, LanguageModelV3.GenerateResult) void,
                ctx: ?*anyopaque,
            ) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.doGenerate(options, allocator, callback, ctx);
            }
        }.doGenerate,

        .doStream = struct {
            fn doStream(
                ptr: *anyopaque,
                options: LanguageModelV3CallOptions,
                allocator: std.mem.Allocator,
                callbacks: LanguageModelV3.StreamCallbacks,
            ) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.doStream(options, allocator, callbacks);
            }
        }.doStream,

        .cancel = if (@hasDecl(T, "cancel")) struct {
            fn cancel(ptr: *anyopaque) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.cancel();
            }
        }.cancel else null,
    };
}

/// Create a LanguageModelV3 from a concrete implementation
pub fn asLanguageModel(comptime T: type, impl: *T) LanguageModelV3 {
    const vtable = comptime implementLanguageModel(T);
    return .{
        .vtable = &vtable,
        .impl = impl,
    };
}

test "LanguageModelV3 specification_version" {
    try std.testing.expectEqualStrings("v3", LanguageModelV3.specification_version);
}
