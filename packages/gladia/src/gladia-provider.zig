const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");

pub const GladiaProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

/// Gladia Transcription Model IDs
pub const TranscriptionModels = struct {
    pub const enhanced = "enhanced";
    pub const fast = "fast";
};

/// Gladia Transcription Model
pub const GladiaTranscriptionModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    base_url: []const u8,
    settings: GladiaProviderSettings,

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        base_url: []const u8,
        settings: GladiaProviderSettings,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .base_url = base_url,
            .settings = settings,
        };
    }

    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "gladia.transcription";
    }

    /// Build request body for transcription
    pub fn buildRequestBody(
        self: *const Self,
        audio_url: []const u8,
        options: TranscriptionOptions,
    ) !std.json.Value {
        var obj = std.json.ObjectMap.init(self.allocator);

        try obj.put("audio_url", std.json.Value{ .string = audio_url });

        if (options.language) |l| {
            try obj.put("language", std.json.Value{ .string = l });
        }
        if (options.language_behaviour) |lb| {
            try obj.put("language_behaviour", std.json.Value{ .string = lb });
        }
        if (options.toggle_diarization) |td| {
            try obj.put("toggle_diarization", std.json.Value{ .bool = td });
        }
        if (options.diarization_max_speakers) |dms| {
            try obj.put("diarization_max_speakers", std.json.Value{ .integer = try provider_utils.safeCast(i64, dms) });
        }
        if (options.toggle_direct_translate) |tdt| {
            try obj.put("toggle_direct_translate", std.json.Value{ .bool = tdt });
        }
        if (options.target_translation_language) |ttl| {
            try obj.put("target_translation_language", std.json.Value{ .string = ttl });
        }
        if (options.toggle_text_emotion_recognition) |tter| {
            try obj.put("toggle_text_emotion_recognition", std.json.Value{ .bool = tter });
        }
        if (options.toggle_summarization) |ts| {
            try obj.put("toggle_summarization", std.json.Value{ .bool = ts });
        }
        if (options.toggle_chapterization) |tc| {
            try obj.put("toggle_chapterization", std.json.Value{ .bool = tc });
        }
        if (options.toggle_noise_reduction) |tnr| {
            try obj.put("toggle_noise_reduction", std.json.Value{ .bool = tnr });
        }
        if (options.output_format) |of| {
            try obj.put("output_format", std.json.Value{ .string = of });
        }
        if (options.custom_vocabulary) |cv| {
            var arr = std.json.Array.init(self.allocator);
            for (cv) |word| {
                try arr.append(std.json.Value{ .string = word });
            }
            try obj.put("custom_vocabulary", std.json.Value{ .array = arr });
        }
        if (options.custom_spelling) |cs| {
            var spelling_obj = std.json.ObjectMap.init(self.allocator);
            var iter = cs.iterator();
            while (iter.next()) |entry| {
                try spelling_obj.put(entry.key_ptr.*, std.json.Value{ .string = entry.value_ptr.* });
            }
            try obj.put("custom_spelling", std.json.Value{ .object = spelling_obj });
        }
        if (options.webhook_url) |wu| {
            try obj.put("webhook_url", std.json.Value{ .string = wu });
        }

        return std.json.Value{ .object = obj };
    }
};

pub const TranscriptionOptions = struct {
    language: ?[]const u8 = null,
    language_behaviour: ?[]const u8 = null, // "manual", "automatic single language", "automatic multiple languages"
    toggle_diarization: ?bool = null,
    diarization_max_speakers: ?u32 = null,
    toggle_direct_translate: ?bool = null,
    target_translation_language: ?[]const u8 = null,
    toggle_text_emotion_recognition: ?bool = null,
    toggle_summarization: ?bool = null,
    toggle_chapterization: ?bool = null,
    toggle_noise_reduction: ?bool = null,
    output_format: ?[]const u8 = null, // "json", "srt", "vtt", "txt"
    custom_vocabulary: ?[]const []const u8 = null,
    custom_spelling: ?std.StringHashMap([]const u8) = null,
    webhook_url: ?[]const u8 = null,
};

pub const GladiaProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: GladiaProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: GladiaProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.gladia.io",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "gladia";
    }

    pub fn transcriptionModel(self: *Self, model_id: []const u8) GladiaTranscriptionModel {
        return GladiaTranscriptionModel.init(self.allocator, model_id, self.base_url, self.settings);
    }

    pub fn transcription(self: *Self, model_id: []const u8) GladiaTranscriptionModel {
        return self.transcriptionModel(model_id);
    }

    pub fn asProvider(self: *Self) provider_v3.ProviderV3 {
        return .{
            .vtable = &vtable,
            .impl = self,
        };
    }

    const vtable = provider_v3.ProviderV3.VTable{
        .languageModel = languageModelVtable,
        .embeddingModel = embeddingModelVtable,
        .imageModel = imageModelVtable,
        .speechModel = speechModelVtable,
        .transcriptionModel = transcriptionModelVtable,
    };

    fn languageModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.LanguageModelResult {
        _ = model_id;
        return .{ .failure = error.NoSuchModel };
    }

    fn embeddingModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.EmbeddingModelResult {
        _ = model_id;
        return .{ .failure = error.NoSuchModel };
    }

    fn imageModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.ImageModelResult {
        _ = model_id;
        return .{ .failure = error.NoSuchModel };
    }

    fn speechModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.SpeechModelResult {
        _ = model_id;
        return .{ .failure = error.NoSuchModel };
    }

    fn transcriptionModelVtable(_: *anyopaque, model_id: []const u8) provider_v3.TranscriptionModelResult {
        _ = model_id;
        return .{ .failure = error.NoSuchModel };
    }
};

fn getApiKeyFromEnv() ?[]const u8 {
    return std.posix.getenv("GLADIA_API_KEY");
}

/// Get headers for API requests. Caller owns the returned HashMap.
pub fn getHeaders(allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    try headers.put("Content-Type", "application/json");

    if (getApiKeyFromEnv()) |api_key| {
        try headers.put("x-gladia-key", api_key);
    }

    return headers;
}

pub fn createGladia(allocator: std.mem.Allocator) GladiaProvider {
    return GladiaProvider.init(allocator, .{});
}

pub fn createGladiaWithSettings(
    allocator: std.mem.Allocator,
    settings: GladiaProviderSettings,
) GladiaProvider {
    return GladiaProvider.init(allocator, settings);
}

test "GladiaProvider basic" {
    const allocator = std.testing.allocator;
    var prov = createGladiaWithSettings(allocator, .{});
    defer prov.deinit();
    try std.testing.expectEqualStrings("gladia", prov.getProvider());
}
