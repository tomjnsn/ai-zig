const std = @import("std");
const provider_utils = @import("provider-utils");
const HttpClient = provider_utils.HttpClient;

/// Configuration for OpenAI API requests
pub const OpenAIConfig = struct {
    /// Provider name (e.g., "openai.chat", "openai.embedding")
    provider: []const u8,

    /// Base URL for the API
    base_url: []const u8,

    /// Function to build the full URL from path
    url_builder: ?*const fn (config: *const OpenAIConfig, path: []const u8, model_id: []const u8) []const u8 = null,

    /// Function to get headers
    headers_fn: *const fn (*const OpenAIConfig, std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8),

    /// HTTP client to use
    http_client: ?HttpClient = null,

    /// Optional ID generator
    generate_id: ?*const fn () []const u8 = null,

    /// File ID prefixes used to identify file IDs in Responses API.
    /// When null, all file data is treated as base64 content.
    /// Examples:
    /// - OpenAI: ["file-"] for IDs like "file-abc123"
    /// - Azure OpenAI: ["assistant-"] for IDs like "assistant-abc123"
    file_id_prefixes: ?[]const []const u8 = null,

    const Self = @This();

    /// Build URL from path and model ID
    pub fn buildUrl(self: *const Self, allocator: std.mem.Allocator, path: []const u8, model_id: []const u8) ![]u8 {
        if (self.url_builder) |builder| {
            return allocator.dupe(u8, builder(self, path, model_id));
        }
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ self.base_url, path });
    }

    /// Get headers for the request
    pub fn getHeaders(self: *const Self, allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
        return self.headers_fn(self, allocator);
    }

    /// Check if a string is a file ID based on configured prefixes
    pub fn isFileId(self: *const Self, value: []const u8) bool {
        if (self.file_id_prefixes) |prefixes| {
            for (prefixes) |prefix| {
                if (std.mem.startsWith(u8, value, prefix)) {
                    return true;
                }
            }
        }
        return false;
    }
};

/// Chat-specific configuration
pub const OpenAIChatConfig = struct {
    config: OpenAIConfig,

    const Self = @This();

    pub fn getCompletionsUrl(self: *const Self, allocator: std.mem.Allocator, model_id: []const u8) ![]u8 {
        return self.config.buildUrl(allocator, "/chat/completions", model_id);
    }
};

/// Embedding-specific configuration
pub const OpenAIEmbeddingConfig = struct {
    config: OpenAIConfig,

    const Self = @This();

    pub fn getEmbeddingsUrl(self: *const Self, allocator: std.mem.Allocator, model_id: []const u8) ![]u8 {
        return self.config.buildUrl(allocator, "/embeddings", model_id);
    }
};

/// Image-specific configuration
pub const OpenAIImageConfig = struct {
    config: OpenAIConfig,

    const Self = @This();

    pub fn getGenerationsUrl(self: *const Self, allocator: std.mem.Allocator, model_id: []const u8) ![]u8 {
        return self.config.buildUrl(allocator, "/images/generations", model_id);
    }

    pub fn getEditsUrl(self: *const Self, allocator: std.mem.Allocator, model_id: []const u8) ![]u8 {
        return self.config.buildUrl(allocator, "/images/edits", model_id);
    }

    pub fn getVariationsUrl(self: *const Self, allocator: std.mem.Allocator, model_id: []const u8) ![]u8 {
        return self.config.buildUrl(allocator, "/images/variations", model_id);
    }
};

/// Speech-specific configuration
pub const OpenAISpeechConfig = struct {
    config: OpenAIConfig,

    const Self = @This();

    pub fn getSpeechUrl(self: *const Self, allocator: std.mem.Allocator, model_id: []const u8) ![]u8 {
        return self.config.buildUrl(allocator, "/audio/speech", model_id);
    }
};

/// Transcription-specific configuration
pub const OpenAITranscriptionConfig = struct {
    config: OpenAIConfig,

    const Self = @This();

    pub fn getTranscriptionsUrl(self: *const Self, allocator: std.mem.Allocator, model_id: []const u8) ![]u8 {
        return self.config.buildUrl(allocator, "/audio/transcriptions", model_id);
    }
};

test "OpenAIConfig buildUrl" {
    const allocator = std.testing.allocator;

    const config = OpenAIConfig{
        .provider = "openai.chat",
        .base_url = "https://api.openai.com/v1",
        .headers_fn = struct {
            fn getHeaders(_: *const OpenAIConfig, alloc: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(alloc);
            }
        }.getHeaders,
    };

    const url = try config.buildUrl(allocator, "/chat/completions", "gpt-4");
    defer allocator.free(url);

    try std.testing.expectEqualStrings("https://api.openai.com/v1/chat/completions", url);
}

test "OpenAIConfig isFileId" {
    const prefixes = [_][]const u8{"file-"};
    const config = OpenAIConfig{
        .provider = "openai.responses",
        .base_url = "https://api.openai.com/v1",
        .headers_fn = struct {
            fn getHeaders(_: *const OpenAIConfig, alloc: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(alloc);
            }
        }.getHeaders,
        .file_id_prefixes = &prefixes,
    };

    try std.testing.expect(config.isFileId("file-abc123"));
    try std.testing.expect(!config.isFileId("not-a-file-id"));
}
