const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("../../provider/src/provider/v3/index.zig");

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
