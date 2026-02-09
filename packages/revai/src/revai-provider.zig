const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;

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

test "RevAIProvider default base_url" {
    const allocator = std.testing.allocator;
    var prov = createRevAI(allocator);
    defer prov.deinit();
    try std.testing.expectEqualStrings("https://api.rev.ai", prov.base_url);
}

test "RevAIProvider custom base_url" {
    const allocator = std.testing.allocator;
    var prov = createRevAIWithSettings(allocator, .{
        .base_url = "https://custom.rev.ai",
    });
    defer prov.deinit();
    try std.testing.expectEqualStrings("https://custom.rev.ai", prov.base_url);
}

test "RevAIProvider specification_version" {
    try std.testing.expectEqualStrings("v3", RevAIProvider.specification_version);
}

test "RevAIProvider transcriptionModel creates model with correct properties" {
    const allocator = std.testing.allocator;
    var prov = createRevAI(allocator);
    defer prov.deinit();

    const model = prov.transcriptionModel("machine");
    try std.testing.expectEqualStrings("machine", model.getModelId());
    try std.testing.expectEqualStrings("revai.transcription", model.getProvider());
    try std.testing.expectEqualStrings("https://api.rev.ai", model.base_url);
}

test "RevAIProvider transcription alias" {
    const allocator = std.testing.allocator;
    var prov = createRevAI(allocator);
    defer prov.deinit();

    const model = prov.transcription("human");
    try std.testing.expectEqualStrings("human", model.getModelId());
    try std.testing.expectEqualStrings("revai.transcription", model.getProvider());
}

test "TranscriptionModels constants" {
    try std.testing.expectEqualStrings("machine", TranscriptionModels.machine);
    try std.testing.expectEqualStrings("machine_v2", TranscriptionModels.machine_v2);
    try std.testing.expectEqualStrings("human", TranscriptionModels.human);
}

test "TranscriptionOptions default values" {
    const options = TranscriptionOptions{};
    try std.testing.expect(options.language == null);
    try std.testing.expect(options.skip_diarization == null);
    try std.testing.expect(options.skip_punctuation == null);
    try std.testing.expect(options.remove_disfluencies == null);
    try std.testing.expect(options.filter_profanity == null);
    try std.testing.expect(options.speaker_channels_count == null);
    try std.testing.expect(options.custom_vocabularies == null);
    try std.testing.expect(options.delete_after_seconds == null);
    try std.testing.expect(options.metadata == null);
    try std.testing.expect(options.callback_url == null);
    try std.testing.expect(options.verbatim == null);
    try std.testing.expect(options.rush == null);
    try std.testing.expect(options.segments == null);
    try std.testing.expect(options.emotion == null);
    try std.testing.expect(options.summarization == null);
    try std.testing.expect(options.translation == null);
}

test "SummarizationConfig default values" {
    const config = SummarizationConfig{};
    try std.testing.expect(config.@"type" == null);
    try std.testing.expect(config.model == null);
    try std.testing.expect(config.prompt == null);
}

test "TranslationConfig default values" {
    const config = TranslationConfig{};
    try std.testing.expect(config.target_languages == null);
}

test "RevAITranscriptionModel buildRequestBody with media_url only" {
    const allocator = std.testing.allocator;
    const settings = RevAIProviderSettings{};
    const model = RevAITranscriptionModel.init(
        allocator,
        "machine",
        "https://api.rev.ai",
        settings,
    );

    const options = TranscriptionOptions{};
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqualStrings("https://example.com/audio.mp3", body.object.get("media_url").?.string);
    try std.testing.expect(body.object.get("language") == null);
    try std.testing.expect(body.object.get("skip_diarization") == null);
    try std.testing.expect(body.object.get("summarization") == null);
}

test "RevAITranscriptionModel buildRequestBody with language" {
    const allocator = std.testing.allocator;
    const settings = RevAIProviderSettings{};
    const model = RevAITranscriptionModel.init(
        allocator,
        "machine",
        "https://api.rev.ai",
        settings,
    );

    const options = TranscriptionOptions{
        .language = "en",
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqualStrings("en", body.object.get("language").?.string);
}

test "RevAITranscriptionModel buildRequestBody with processing options" {
    const allocator = std.testing.allocator;
    const settings = RevAIProviderSettings{};
    const model = RevAITranscriptionModel.init(
        allocator,
        "machine",
        "https://api.rev.ai",
        settings,
    );

    const options = TranscriptionOptions{
        .skip_diarization = false,
        .skip_punctuation = false,
        .remove_disfluencies = true,
        .filter_profanity = true,
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqual(false, body.object.get("skip_diarization").?.bool);
    try std.testing.expectEqual(false, body.object.get("skip_punctuation").?.bool);
    try std.testing.expectEqual(true, body.object.get("remove_disfluencies").?.bool);
    try std.testing.expectEqual(true, body.object.get("filter_profanity").?.bool);
}

test "RevAITranscriptionModel buildRequestBody with speaker_channels_count" {
    const allocator = std.testing.allocator;
    const settings = RevAIProviderSettings{};
    const model = RevAITranscriptionModel.init(
        allocator,
        "machine",
        "https://api.rev.ai",
        settings,
    );

    const options = TranscriptionOptions{
        .speaker_channels_count = 2,
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqual(@as(i64, 2), body.object.get("speaker_channels_count").?.integer);
}

test "RevAITranscriptionModel buildRequestBody with custom_vocabularies" {
    const allocator = std.testing.allocator;
    const settings = RevAIProviderSettings{};
    const model = RevAITranscriptionModel.init(
        allocator,
        "machine",
        "https://api.rev.ai",
        settings,
    );

    const vocabs = &[_]CustomVocabulary{
        .{ .phrases = &[_][]const u8{ "Zig", "comptime" } },
        .{ .phrases = &[_][]const u8{"allocator"} },
    };
    const options = TranscriptionOptions{
        .custom_vocabularies = vocabs,
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer {
        // Clean up nested arrays and objects
        var cv_arr = body.object.get("custom_vocabularies").?.array;
        for (cv_arr.items) |*item| {
            item.object.get("phrases").?.array.deinit();
            item.object.deinit();
        }
        cv_arr.deinit();
        body.object.deinit();
    }

    const cv_arr = body.object.get("custom_vocabularies").?.array;
    try std.testing.expectEqual(@as(usize, 2), cv_arr.items.len);

    // First vocabulary entry
    const first_phrases = cv_arr.items[0].object.get("phrases").?.array;
    try std.testing.expectEqual(@as(usize, 2), first_phrases.items.len);
    try std.testing.expectEqualStrings("Zig", first_phrases.items[0].string);
    try std.testing.expectEqualStrings("comptime", first_phrases.items[1].string);

    // Second vocabulary entry
    const second_phrases = cv_arr.items[1].object.get("phrases").?.array;
    try std.testing.expectEqual(@as(usize, 1), second_phrases.items.len);
    try std.testing.expectEqualStrings("allocator", second_phrases.items[0].string);
}

test "RevAITranscriptionModel buildRequestBody with metadata and callback" {
    const allocator = std.testing.allocator;
    const settings = RevAIProviderSettings{};
    const model = RevAITranscriptionModel.init(
        allocator,
        "machine",
        "https://api.rev.ai",
        settings,
    );

    const options = TranscriptionOptions{
        .metadata = "job-123",
        .callback_url = "https://example.com/callback",
        .delete_after_seconds = 3600,
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqualStrings("job-123", body.object.get("metadata").?.string);
    try std.testing.expectEqualStrings("https://example.com/callback", body.object.get("callback_url").?.string);
    try std.testing.expectEqual(@as(i64, 3600), body.object.get("delete_after_seconds").?.integer);
}

test "RevAITranscriptionModel buildRequestBody with human transcription options" {
    const allocator = std.testing.allocator;
    const settings = RevAIProviderSettings{};
    const model = RevAITranscriptionModel.init(
        allocator,
        "human",
        "https://api.rev.ai",
        settings,
    );

    const options = TranscriptionOptions{
        .verbatim = true,
        .rush = true,
        .segments = true,
        .emotion = true,
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqual(true, body.object.get("verbatim").?.bool);
    try std.testing.expectEqual(true, body.object.get("rush").?.bool);
    try std.testing.expectEqual(true, body.object.get("segments").?.bool);
    try std.testing.expectEqual(true, body.object.get("emotion").?.bool);
}

test "RevAITranscriptionModel buildRequestBody with summarization" {
    const allocator = std.testing.allocator;
    const settings = RevAIProviderSettings{};
    const model = RevAITranscriptionModel.init(
        allocator,
        "machine",
        "https://api.rev.ai",
        settings,
    );

    const options = TranscriptionOptions{
        .summarization = .{
            .@"type" = "bullets",
            .model = "standard",
            .prompt = "Summarize the key points",
        },
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer {
        body.object.getPtr("summarization").?.object.deinit();
        body.object.deinit();
    }

    const sum_obj = body.object.get("summarization").?.object;
    try std.testing.expectEqualStrings("bullets", sum_obj.get("type").?.string);
    try std.testing.expectEqualStrings("standard", sum_obj.get("model").?.string);
    try std.testing.expectEqualStrings("Summarize the key points", sum_obj.get("prompt").?.string);
}

test "RevAITranscriptionModel buildRequestBody with translation" {
    const allocator = std.testing.allocator;
    const settings = RevAIProviderSettings{};
    const model = RevAITranscriptionModel.init(
        allocator,
        "machine",
        "https://api.rev.ai",
        settings,
    );

    const target_langs = &[_][]const u8{ "es", "fr", "de" };
    const options = TranscriptionOptions{
        .translation = .{
            .target_languages = target_langs,
        },
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer {
        body.object.getPtr("translation").?.object.getPtr("target_languages").?.array.deinit();
        body.object.getPtr("translation").?.object.deinit();
        body.object.deinit();
    }

    const tr_obj = body.object.get("translation").?.object;
    const lang_arr = tr_obj.get("target_languages").?.array;
    try std.testing.expectEqual(@as(usize, 3), lang_arr.items.len);
    try std.testing.expectEqualStrings("es", lang_arr.items[0].string);
    try std.testing.expectEqualStrings("fr", lang_arr.items[1].string);
    try std.testing.expectEqualStrings("de", lang_arr.items[2].string);
}

test "RevAITranscriptionModel buildRequestBody with partial summarization config" {
    const allocator = std.testing.allocator;
    const settings = RevAIProviderSettings{};
    const model = RevAITranscriptionModel.init(
        allocator,
        "machine",
        "https://api.rev.ai",
        settings,
    );

    const options = TranscriptionOptions{
        .summarization = .{
            .@"type" = "paragraph",
        },
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer {
        body.object.getPtr("summarization").?.object.deinit();
        body.object.deinit();
    }

    const sum_obj = body.object.get("summarization").?.object;
    try std.testing.expectEqualStrings("paragraph", sum_obj.get("type").?.string);
    try std.testing.expect(sum_obj.get("model") == null);
    try std.testing.expect(sum_obj.get("prompt") == null);
}

test "RevAITranscriptionModel model with custom base_url" {
    const allocator = std.testing.allocator;
    var prov = createRevAIWithSettings(allocator, .{
        .base_url = "https://custom.rev.ai",
    });
    defer prov.deinit();

    const model = prov.transcriptionModel("machine_v2");
    try std.testing.expectEqualStrings("https://custom.rev.ai", model.base_url);
    try std.testing.expectEqualStrings("machine_v2", model.getModelId());
}
