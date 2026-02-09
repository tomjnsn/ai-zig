const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;

pub const AssemblyAIProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

/// AssemblyAI Transcription Model IDs
pub const TranscriptionModels = struct {
    pub const best = "best";
    pub const nano = "nano";
    pub const conformer_2 = "conformer-2";
};

/// AssemblyAI Transcription Model
pub const AssemblyAITranscriptionModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    base_url: []const u8,
    settings: AssemblyAIProviderSettings,

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        base_url: []const u8,
        settings: AssemblyAIProviderSettings,
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
        return "assemblyai.transcription";
    }

    /// Build request body for transcription
    pub fn buildRequestBody(
        self: *const Self,
        audio_url: []const u8,
        options: TranscriptionOptions,
    ) !std.json.Value {
        var obj = std.json.ObjectMap.init(self.allocator);

        try obj.put("audio_url", std.json.Value{ .string = audio_url });

        if (options.language_code) |lc| {
            try obj.put("language_code", std.json.Value{ .string = lc });
        }
        if (options.language_detection) |ld| {
            try obj.put("language_detection", std.json.Value{ .bool = ld });
        }
        if (options.punctuate) |p| {
            try obj.put("punctuate", std.json.Value{ .bool = p });
        }
        if (options.format_text) |ft| {
            try obj.put("format_text", std.json.Value{ .bool = ft });
        }
        if (options.disfluencies) |d| {
            try obj.put("disfluencies", std.json.Value{ .bool = d });
        }
        if (options.speaker_labels) |sl| {
            try obj.put("speaker_labels", std.json.Value{ .bool = sl });
        }
        if (options.speakers_expected) |se| {
            try obj.put("speakers_expected", std.json.Value{ .integer = try provider_utils.safeCast(i64, se) });
        }
        if (options.word_boost) |wb| {
            var arr = std.json.Array.init(self.allocator);
            for (wb) |word| {
                try arr.append(std.json.Value{ .string = word });
            }
            try obj.put("word_boost", std.json.Value{ .array = arr });
        }
        if (options.boost_param) |bp| {
            try obj.put("boost_param", std.json.Value{ .string = bp });
        }
        if (options.filter_profanity) |fp| {
            try obj.put("filter_profanity", std.json.Value{ .bool = fp });
        }
        if (options.redact_pii) |rp| {
            try obj.put("redact_pii", std.json.Value{ .bool = rp });
        }
        if (options.auto_chapters) |ac| {
            try obj.put("auto_chapters", std.json.Value{ .bool = ac });
        }
        if (options.auto_highlights) |ah| {
            try obj.put("auto_highlights", std.json.Value{ .bool = ah });
        }
        if (options.content_safety) |cs| {
            try obj.put("content_safety", std.json.Value{ .bool = cs });
        }
        if (options.iab_categories) |ic| {
            try obj.put("iab_categories", std.json.Value{ .bool = ic });
        }
        if (options.sentiment_analysis) |sa| {
            try obj.put("sentiment_analysis", std.json.Value{ .bool = sa });
        }
        if (options.entity_detection) |ed| {
            try obj.put("entity_detection", std.json.Value{ .bool = ed });
        }
        if (options.summarization) |s| {
            try obj.put("summarization", std.json.Value{ .bool = s });
        }
        if (options.summary_model) |sm| {
            try obj.put("summary_model", std.json.Value{ .string = sm });
        }
        if (options.summary_type) |st| {
            try obj.put("summary_type", std.json.Value{ .string = st });
        }

        return std.json.Value{ .object = obj };
    }
};

pub const TranscriptionOptions = struct {
    language_code: ?[]const u8 = null,
    language_detection: ?bool = null,
    punctuate: ?bool = null,
    format_text: ?bool = null,
    disfluencies: ?bool = null,
    speaker_labels: ?bool = null,
    speakers_expected: ?u32 = null,
    word_boost: ?[]const []const u8 = null,
    boost_param: ?[]const u8 = null, // "low", "default", "high"
    filter_profanity: ?bool = null,
    redact_pii: ?bool = null,
    auto_chapters: ?bool = null,
    auto_highlights: ?bool = null,
    content_safety: ?bool = null,
    iab_categories: ?bool = null,
    sentiment_analysis: ?bool = null,
    entity_detection: ?bool = null,
    summarization: ?bool = null,
    summary_model: ?[]const u8 = null, // "informative", "conversational", "catchy"
    summary_type: ?[]const u8 = null, // "bullets", "bullets_verbose", "gist", "headline", "paragraph"
};

/// AssemblyAI LeMUR Language Model
pub const AssemblyAILanguageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    base_url: []const u8,
    settings: AssemblyAIProviderSettings,

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        base_url: []const u8,
        settings: AssemblyAIProviderSettings,
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
        return "assemblyai.lemur";
    }
};

pub const AssemblyAIProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: AssemblyAIProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: AssemblyAIProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.assemblyai.com",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "assemblyai";
    }

    pub fn transcriptionModel(self: *Self, model_id: []const u8) AssemblyAITranscriptionModel {
        return AssemblyAITranscriptionModel.init(self.allocator, model_id, self.base_url, self.settings);
    }

    pub fn transcription(self: *Self, model_id: []const u8) AssemblyAITranscriptionModel {
        return self.transcriptionModel(model_id);
    }

    pub fn languageModel(self: *Self, model_id: []const u8) AssemblyAILanguageModel {
        return AssemblyAILanguageModel.init(self.allocator, model_id, self.base_url, self.settings);
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
    return std.posix.getenv("ASSEMBLYAI_API_KEY");
}

/// Get headers for API requests. Caller owns the returned HashMap.
pub fn getHeaders(allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    try headers.put("Content-Type", "application/json");

    if (getApiKeyFromEnv()) |api_key| {
        try headers.put("Authorization", api_key);
    }

    return headers;
}

pub fn createAssemblyAI(allocator: std.mem.Allocator) AssemblyAIProvider {
    return AssemblyAIProvider.init(allocator, .{});
}

pub fn createAssemblyAIWithSettings(
    allocator: std.mem.Allocator,
    settings: AssemblyAIProviderSettings,
) AssemblyAIProvider {
    return AssemblyAIProvider.init(allocator, settings);
}

test "AssemblyAIProvider basic" {
    const allocator = std.testing.allocator;
    var prov = createAssemblyAIWithSettings(allocator, .{});
    defer prov.deinit();
    try std.testing.expectEqualStrings("assemblyai", prov.getProvider());
}

test "AssemblyAIProvider default base_url" {
    const allocator = std.testing.allocator;
    var prov = createAssemblyAI(allocator);
    defer prov.deinit();
    try std.testing.expectEqualStrings("https://api.assemblyai.com", prov.base_url);
}

test "AssemblyAIProvider custom base_url" {
    const allocator = std.testing.allocator;
    var prov = createAssemblyAIWithSettings(allocator, .{
        .base_url = "https://custom.assemblyai.com",
    });
    defer prov.deinit();
    try std.testing.expectEqualStrings("https://custom.assemblyai.com", prov.base_url);
}

test "AssemblyAIProvider specification_version" {
    try std.testing.expectEqualStrings("v3", AssemblyAIProvider.specification_version);
}

test "AssemblyAIProvider transcriptionModel creates model with correct properties" {
    const allocator = std.testing.allocator;
    var prov = createAssemblyAI(allocator);
    defer prov.deinit();

    const model = prov.transcriptionModel("best");
    try std.testing.expectEqualStrings("best", model.getModelId());
    try std.testing.expectEqualStrings("assemblyai.transcription", model.getProvider());
    try std.testing.expectEqualStrings("https://api.assemblyai.com", model.base_url);
}

test "AssemblyAIProvider transcription alias" {
    const allocator = std.testing.allocator;
    var prov = createAssemblyAI(allocator);
    defer prov.deinit();

    const model = prov.transcription("nano");
    try std.testing.expectEqualStrings("nano", model.getModelId());
    try std.testing.expectEqualStrings("assemblyai.transcription", model.getProvider());
}

test "AssemblyAIProvider languageModel creates LeMUR model" {
    const allocator = std.testing.allocator;
    var prov = createAssemblyAI(allocator);
    defer prov.deinit();

    const model = prov.languageModel("default");
    try std.testing.expectEqualStrings("default", model.getModelId());
    try std.testing.expectEqualStrings("assemblyai.lemur", model.getProvider());
    try std.testing.expectEqualStrings("https://api.assemblyai.com", model.base_url);
}

test "TranscriptionModels constants" {
    try std.testing.expectEqualStrings("best", TranscriptionModels.best);
    try std.testing.expectEqualStrings("nano", TranscriptionModels.nano);
    try std.testing.expectEqualStrings("conformer-2", TranscriptionModels.conformer_2);
}

test "TranscriptionOptions default values" {
    const options = TranscriptionOptions{};
    try std.testing.expect(options.language_code == null);
    try std.testing.expect(options.language_detection == null);
    try std.testing.expect(options.punctuate == null);
    try std.testing.expect(options.format_text == null);
    try std.testing.expect(options.disfluencies == null);
    try std.testing.expect(options.speaker_labels == null);
    try std.testing.expect(options.speakers_expected == null);
    try std.testing.expect(options.word_boost == null);
    try std.testing.expect(options.boost_param == null);
    try std.testing.expect(options.filter_profanity == null);
    try std.testing.expect(options.redact_pii == null);
    try std.testing.expect(options.auto_chapters == null);
    try std.testing.expect(options.auto_highlights == null);
    try std.testing.expect(options.content_safety == null);
    try std.testing.expect(options.iab_categories == null);
    try std.testing.expect(options.sentiment_analysis == null);
    try std.testing.expect(options.entity_detection == null);
    try std.testing.expect(options.summarization == null);
    try std.testing.expect(options.summary_model == null);
    try std.testing.expect(options.summary_type == null);
}

test "AssemblyAITranscriptionModel buildRequestBody with audio_url only" {
    const allocator = std.testing.allocator;
    const settings = AssemblyAIProviderSettings{};
    const model = AssemblyAITranscriptionModel.init(
        allocator,
        "best",
        "https://api.assemblyai.com",
        settings,
    );

    const options = TranscriptionOptions{};
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqualStrings("https://example.com/audio.mp3", body.object.get("audio_url").?.string);
    try std.testing.expect(body.object.get("language_code") == null);
    try std.testing.expect(body.object.get("speaker_labels") == null);
    try std.testing.expect(body.object.get("summarization") == null);
}

test "AssemblyAITranscriptionModel buildRequestBody with language options" {
    const allocator = std.testing.allocator;
    const settings = AssemblyAIProviderSettings{};
    const model = AssemblyAITranscriptionModel.init(
        allocator,
        "best",
        "https://api.assemblyai.com",
        settings,
    );

    const options = TranscriptionOptions{
        .language_code = "en_us",
        .language_detection = true,
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqualStrings("en_us", body.object.get("language_code").?.string);
    try std.testing.expectEqual(true, body.object.get("language_detection").?.bool);
}

test "AssemblyAITranscriptionModel buildRequestBody with formatting options" {
    const allocator = std.testing.allocator;
    const settings = AssemblyAIProviderSettings{};
    const model = AssemblyAITranscriptionModel.init(
        allocator,
        "best",
        "https://api.assemblyai.com",
        settings,
    );

    const options = TranscriptionOptions{
        .punctuate = true,
        .format_text = true,
        .disfluencies = false,
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqual(true, body.object.get("punctuate").?.bool);
    try std.testing.expectEqual(true, body.object.get("format_text").?.bool);
    try std.testing.expectEqual(false, body.object.get("disfluencies").?.bool);
}

test "AssemblyAITranscriptionModel buildRequestBody with speaker labels" {
    const allocator = std.testing.allocator;
    const settings = AssemblyAIProviderSettings{};
    const model = AssemblyAITranscriptionModel.init(
        allocator,
        "best",
        "https://api.assemblyai.com",
        settings,
    );

    const options = TranscriptionOptions{
        .speaker_labels = true,
        .speakers_expected = 3,
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqual(true, body.object.get("speaker_labels").?.bool);
    try std.testing.expectEqual(@as(i64, 3), body.object.get("speakers_expected").?.integer);
}

test "AssemblyAITranscriptionModel buildRequestBody with word_boost" {
    const allocator = std.testing.allocator;
    const settings = AssemblyAIProviderSettings{};
    const model = AssemblyAITranscriptionModel.init(
        allocator,
        "best",
        "https://api.assemblyai.com",
        settings,
    );

    const boost_words = &[_][]const u8{ "Kubernetes", "Docker", "Terraform" };
    const options = TranscriptionOptions{
        .word_boost = boost_words,
        .boost_param = "high",
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer {
        body.object.get("word_boost").?.array.deinit();
        body.object.deinit();
    }

    const arr = body.object.get("word_boost").?.array;
    try std.testing.expectEqual(@as(usize, 3), arr.items.len);
    try std.testing.expectEqualStrings("Kubernetes", arr.items[0].string);
    try std.testing.expectEqualStrings("Docker", arr.items[1].string);
    try std.testing.expectEqualStrings("Terraform", arr.items[2].string);
    try std.testing.expectEqualStrings("high", body.object.get("boost_param").?.string);
}

test "AssemblyAITranscriptionModel buildRequestBody with content moderation" {
    const allocator = std.testing.allocator;
    const settings = AssemblyAIProviderSettings{};
    const model = AssemblyAITranscriptionModel.init(
        allocator,
        "best",
        "https://api.assemblyai.com",
        settings,
    );

    const options = TranscriptionOptions{
        .filter_profanity = true,
        .redact_pii = true,
        .content_safety = true,
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqual(true, body.object.get("filter_profanity").?.bool);
    try std.testing.expectEqual(true, body.object.get("redact_pii").?.bool);
    try std.testing.expectEqual(true, body.object.get("content_safety").?.bool);
}

test "AssemblyAITranscriptionModel buildRequestBody with audio intelligence" {
    const allocator = std.testing.allocator;
    const settings = AssemblyAIProviderSettings{};
    const model = AssemblyAITranscriptionModel.init(
        allocator,
        "best",
        "https://api.assemblyai.com",
        settings,
    );

    const options = TranscriptionOptions{
        .auto_chapters = true,
        .auto_highlights = true,
        .iab_categories = true,
        .sentiment_analysis = true,
        .entity_detection = true,
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqual(true, body.object.get("auto_chapters").?.bool);
    try std.testing.expectEqual(true, body.object.get("auto_highlights").?.bool);
    try std.testing.expectEqual(true, body.object.get("iab_categories").?.bool);
    try std.testing.expectEqual(true, body.object.get("sentiment_analysis").?.bool);
    try std.testing.expectEqual(true, body.object.get("entity_detection").?.bool);
}

test "AssemblyAITranscriptionModel buildRequestBody with summarization" {
    const allocator = std.testing.allocator;
    const settings = AssemblyAIProviderSettings{};
    const model = AssemblyAITranscriptionModel.init(
        allocator,
        "best",
        "https://api.assemblyai.com",
        settings,
    );

    const options = TranscriptionOptions{
        .summarization = true,
        .summary_model = "informative",
        .summary_type = "bullets",
    };
    var body = try model.buildRequestBody("https://example.com/audio.mp3", options);
    defer body.object.deinit();

    try std.testing.expectEqual(true, body.object.get("summarization").?.bool);
    try std.testing.expectEqualStrings("informative", body.object.get("summary_model").?.string);
    try std.testing.expectEqualStrings("bullets", body.object.get("summary_type").?.string);
}

test "AssemblyAITranscriptionModel model with custom base_url" {
    const allocator = std.testing.allocator;
    var prov = createAssemblyAIWithSettings(allocator, .{
        .base_url = "https://custom.assemblyai.com",
    });
    defer prov.deinit();

    const model = prov.transcriptionModel("nano");
    try std.testing.expectEqualStrings("https://custom.assemblyai.com", model.base_url);
}
