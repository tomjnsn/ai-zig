const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");

pub const RevAIProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

/// Rev AI Transcription Model IDs
pub const TranscriptionModels = struct {
    pub const machine = "machine";
    pub const machine_v2 = "machine_v2";
    pub const human = "human";
};

/// Rev AI Transcription Model
pub const RevAITranscriptionModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    base_url: []const u8,
    settings: RevAIProviderSettings,

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        base_url: []const u8,
        settings: RevAIProviderSettings,
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
        return "revai.transcription";
    }

    /// Build request body for transcription
    pub fn buildRequestBody(
        self: *const Self,
        media_url: []const u8,
        options: TranscriptionOptions,
    ) !std.json.Value {
        var obj = std.json.ObjectMap.init(self.allocator);

        try obj.put("media_url", std.json.Value{ .string = media_url });

        if (options.language) |l| {
            try obj.put("language", std.json.Value{ .string = l });
        }
        if (options.skip_diarization) |sd| {
            try obj.put("skip_diarization", std.json.Value{ .bool = sd });
        }
        if (options.skip_punctuation) |sp| {
            try obj.put("skip_punctuation", std.json.Value{ .bool = sp });
        }
        if (options.remove_disfluencies) |rd| {
            try obj.put("remove_disfluencies", std.json.Value{ .bool = rd });
        }
        if (options.filter_profanity) |fp| {
            try obj.put("filter_profanity", std.json.Value{ .bool = fp });
        }
        if (options.speaker_channels_count) |scc| {
            try obj.put("speaker_channels_count", std.json.Value{ .integer = try provider_utils.safeCast(i64, scc) });
        }
        if (options.custom_vocabularies) |cv| {
            var vocab_arr = std.json.Array.init(self.allocator);
            for (cv) |vocab| {
                var vocab_obj = std.json.ObjectMap.init(self.allocator);
                var phrases_arr = std.json.Array.init(self.allocator);
                for (vocab.phrases) |phrase| {
                    try phrases_arr.append(std.json.Value{ .string = phrase });
                }
                try vocab_obj.put("phrases", std.json.Value{ .array = phrases_arr });
                try vocab_arr.append(std.json.Value{ .object = vocab_obj });
            }
            try obj.put("custom_vocabularies", std.json.Value{ .array = vocab_arr });
        }
        if (options.delete_after_seconds) |das| {
            try obj.put("delete_after_seconds", std.json.Value{ .integer = try provider_utils.safeCast(i64, das) });
        }
        if (options.metadata) |m| {
            try obj.put("metadata", std.json.Value{ .string = m });
        }
        if (options.callback_url) |cu| {
            try obj.put("callback_url", std.json.Value{ .string = cu });
        }
        if (options.verbatim) |v| {
            try obj.put("verbatim", std.json.Value{ .bool = v });
        }
        if (options.rush) |r| {
            try obj.put("rush", std.json.Value{ .bool = r });
        }
        if (options.segments) |s| {
            try obj.put("segments", std.json.Value{ .bool = s });
        }
        if (options.emotion) |e| {
            try obj.put("emotion", std.json.Value{ .bool = e });
        }
        if (options.summarization) |sum| {
            var sum_obj = std.json.ObjectMap.init(self.allocator);
            if (sum.@"type") |t| {
                try sum_obj.put("type", std.json.Value{ .string = t });
            }
            if (sum.model) |m| {
                try sum_obj.put("model", std.json.Value{ .string = m });
            }
            if (sum.prompt) |p| {
                try sum_obj.put("prompt", std.json.Value{ .string = p });
            }
            try obj.put("summarization", std.json.Value{ .object = sum_obj });
        }
        if (options.translation) |tr| {
            var tr_obj = std.json.ObjectMap.init(self.allocator);
            if (tr.target_languages) |tl| {
                var lang_arr = std.json.Array.init(self.allocator);
                for (tl) |lang| {
                    try lang_arr.append(std.json.Value{ .string = lang });
                }
                try tr_obj.put("target_languages", std.json.Value{ .array = lang_arr });
            }
            try obj.put("translation", std.json.Value{ .object = tr_obj });
        }

        return std.json.Value{ .object = obj };
    }
};

pub const CustomVocabulary = struct {
    phrases: []const []const u8,
};

pub const SummarizationConfig = struct {
    @"type": ?[]const u8 = null, // "bullets", "paragraph"
    model: ?[]const u8 = null,
    prompt: ?[]const u8 = null,
};

pub const TranslationConfig = struct {
    target_languages: ?[]const []const u8 = null,
};

pub const TranscriptionOptions = struct {
    language: ?[]const u8 = null,
    skip_diarization: ?bool = null,
    skip_punctuation: ?bool = null,
    remove_disfluencies: ?bool = null,
    filter_profanity: ?bool = null,
    speaker_channels_count: ?u32 = null,
    custom_vocabularies: ?[]const CustomVocabulary = null,
    delete_after_seconds: ?u64 = null,
    metadata: ?[]const u8 = null,
    callback_url: ?[]const u8 = null,
    verbatim: ?bool = null,
    rush: ?bool = null,
    segments: ?bool = null,
    emotion: ?bool = null,
    summarization: ?SummarizationConfig = null,
    translation: ?TranslationConfig = null,
};

pub const RevAIProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: RevAIProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: RevAIProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.rev.ai",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "revai";
    }

    pub fn transcriptionModel(self: *Self, model_id: []const u8) RevAITranscriptionModel {
        return RevAITranscriptionModel.init(self.allocator, model_id, self.base_url, self.settings);
    }

    pub fn transcription(self: *Self, model_id: []const u8) RevAITranscriptionModel {
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
    return std.posix.getenv("REVAI_API_KEY");
}

/// Get headers for API requests. Caller owns the returned HashMap.
pub fn getHeaders(allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    try headers.put("Content-Type", "application/json");

    if (getApiKeyFromEnv()) |api_key| {
        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
        try headers.put("Authorization", auth_header);
    }

    return headers;
}

pub fn createRevAI(allocator: std.mem.Allocator) RevAIProvider {
    return RevAIProvider.init(allocator, .{});
}

pub fn createRevAIWithSettings(
    allocator: std.mem.Allocator,
    settings: RevAIProviderSettings,
) RevAIProvider {
    return RevAIProvider.init(allocator, settings);
}

test "RevAIProvider basic" {
    const allocator = std.testing.allocator;
    var prov = createRevAIWithSettings(allocator, .{});
    defer prov.deinit();
    try std.testing.expectEqualStrings("revai", prov.getProvider());
}
