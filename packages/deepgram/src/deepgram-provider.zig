const std = @import("std");
const provider_utils = @import("provider-utils");
const provider_v3 = @import("provider").provider;

pub const DeepgramProviderSettings = struct {
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
    http_client: ?provider_utils.HttpClient = null,
};

/// Deepgram Transcription Model IDs
pub const TranscriptionModels = struct {
    pub const nova_2 = "nova-2";
    pub const nova_2_general = "nova-2-general";
    pub const nova_2_meeting = "nova-2-meeting";
    pub const nova_2_phonecall = "nova-2-phonecall";
    pub const nova_2_voicemail = "nova-2-voicemail";
    pub const nova_2_finance = "nova-2-finance";
    pub const nova_2_conversational = "nova-2-conversational";
    pub const nova_2_video = "nova-2-video";
    pub const nova_2_medical = "nova-2-medical";
    pub const nova_2_drivethru = "nova-2-drivethru";
    pub const nova_2_automotive = "nova-2-automotive";
    pub const nova = "nova";
    pub const enhanced = "enhanced";
    pub const base = "base";
    pub const whisper = "whisper";
};

/// Deepgram Speech Model IDs (Aura TTS)
pub const SpeechModels = struct {
    pub const aura_asteria_en = "aura-asteria-en";
    pub const aura_luna_en = "aura-luna-en";
    pub const aura_stella_en = "aura-stella-en";
    pub const aura_athena_en = "aura-athena-en";
    pub const aura_hera_en = "aura-hera-en";
    pub const aura_orion_en = "aura-orion-en";
    pub const aura_arcas_en = "aura-arcas-en";
    pub const aura_perseus_en = "aura-perseus-en";
    pub const aura_angus_en = "aura-angus-en";
    pub const aura_orpheus_en = "aura-orpheus-en";
    pub const aura_helios_en = "aura-helios-en";
    pub const aura_zeus_en = "aura-zeus-en";
};

/// Deepgram Transcription Model
pub const DeepgramTranscriptionModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    base_url: []const u8,
    settings: DeepgramProviderSettings,

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        base_url: []const u8,
        settings: DeepgramProviderSettings,
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
        return "deepgram.transcription";
    }

    /// Build query parameters for transcription
    pub fn buildQueryParams(
        self: *const Self,
        options: TranscriptionOptions,
    ) ![]const u8 {
        var params = std.array_list.Managed(u8).init(self.allocator);
        var writer = params.writer();

        try writer.print("model={s}", .{self.model_id});

        if (options.language) |l| {
            try writer.print("&language={s}", .{l});
        }
        if (options.detect_language) |dl| {
            try writer.print("&detect_language={}", .{dl});
        }
        if (options.punctuate) |p| {
            try writer.print("&punctuate={}", .{p});
        }
        if (options.profanity_filter) |pf| {
            try writer.print("&profanity_filter={}", .{pf});
        }
        if (options.redact) |r| {
            for (r) |item| {
                try writer.print("&redact={s}", .{item});
            }
        }
        if (options.diarize) |d| {
            try writer.print("&diarize={}", .{d});
        }
        if (options.diarize_version) |dv| {
            try writer.print("&diarize_version={s}", .{dv});
        }
        if (options.smart_format) |sf| {
            try writer.print("&smart_format={}", .{sf});
        }
        if (options.filler_words) |fw| {
            try writer.print("&filler_words={}", .{fw});
        }
        if (options.multichannel) |mc| {
            try writer.print("&multichannel={}", .{mc});
        }
        if (options.alternatives) |a| {
            try writer.print("&alternatives={}", .{a});
        }
        if (options.numerals) |n| {
            try writer.print("&numerals={}", .{n});
        }
        if (options.search) |s| {
            for (s) |term| {
                try writer.print("&search={s}", .{term});
            }
        }
        if (options.replace) |r| {
            for (r) |item| {
                try writer.print("&replace={s}", .{item});
            }
        }
        if (options.keywords) |k| {
            for (k) |kw| {
                try writer.print("&keywords={s}", .{kw});
            }
        }
        if (options.utterances) |u| {
            try writer.print("&utterances={}", .{u});
        }
        if (options.utt_split) |us| {
            try writer.print("&utt_split={d}", .{us});
        }
        if (options.paragraphs) |p| {
            try writer.print("&paragraphs={}", .{p});
        }
        if (options.summarize) |s| {
            try writer.print("&summarize={}", .{s});
        }
        if (options.detect_topics) |dt| {
            try writer.print("&detect_topics={}", .{dt});
        }
        if (options.detect_entities) |de| {
            try writer.print("&detect_entities={}", .{de});
        }
        if (options.sentiment) |s| {
            try writer.print("&sentiment={}", .{s});
        }
        if (options.intents) |i| {
            try writer.print("&intents={}", .{i});
        }

        return params.toOwnedSlice();
    }
};

pub const TranscriptionOptions = struct {
    language: ?[]const u8 = null,
    detect_language: ?bool = null,
    punctuate: ?bool = null,
    profanity_filter: ?bool = null,
    redact: ?[]const []const u8 = null, // "pci", "numbers", "ssn", etc.
    diarize: ?bool = null,
    diarize_version: ?[]const u8 = null,
    smart_format: ?bool = null,
    filler_words: ?bool = null,
    multichannel: ?bool = null,
    alternatives: ?u32 = null,
    numerals: ?bool = null,
    search: ?[]const []const u8 = null,
    replace: ?[]const []const u8 = null,
    keywords: ?[]const []const u8 = null,
    utterances: ?bool = null,
    utt_split: ?f64 = null,
    paragraphs: ?bool = null,
    summarize: ?bool = null,
    detect_topics: ?bool = null,
    detect_entities: ?bool = null,
    sentiment: ?bool = null,
    intents: ?bool = null,
};

/// Deepgram Speech Model (Aura TTS)
pub const DeepgramSpeechModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    base_url: []const u8,
    settings: DeepgramProviderSettings,

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        base_url: []const u8,
        settings: DeepgramProviderSettings,
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
        return "deepgram.speech";
    }

    /// Build request body for speech synthesis
    pub fn buildRequestBody(
        self: *const Self,
        text: []const u8,
        options: SpeechOptions,
    ) !std.json.Value {
        var obj = std.json.ObjectMap.init(self.allocator);

        try obj.put("text", std.json.Value{ .string = text });

        if (options.encoding) |e| {
            try obj.put("encoding", std.json.Value{ .string = e });
        }
        if (options.container) |c| {
            try obj.put("container", std.json.Value{ .string = c });
        }
        if (options.sample_rate) |sr| {
            try obj.put("sample_rate", std.json.Value{ .integer = try provider_utils.safeCast(i64, sr) });
        }
        if (options.bit_rate) |br| {
            try obj.put("bit_rate", std.json.Value{ .integer = try provider_utils.safeCast(i64, br) });
        }

        return std.json.Value{ .object = obj };
    }
};

pub const SpeechOptions = struct {
    encoding: ?[]const u8 = null, // "linear16", "mulaw", "alaw", "mp3", "opus", "flac", "aac"
    container: ?[]const u8 = null, // "wav", "mp3", "ogg", etc.
    sample_rate: ?u32 = null,
    bit_rate: ?u32 = null,
};

pub const DeepgramProvider = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: DeepgramProviderSettings,
    base_url: []const u8,

    pub const specification_version = "v3";

    pub fn init(allocator: std.mem.Allocator, settings: DeepgramProviderSettings) Self {
        return .{
            .allocator = allocator,
            .settings = settings,
            .base_url = settings.base_url orelse "https://api.deepgram.com",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        _ = self;
        return "deepgram";
    }

    pub fn transcriptionModel(self: *Self, model_id: []const u8) DeepgramTranscriptionModel {
        return DeepgramTranscriptionModel.init(self.allocator, model_id, self.base_url, self.settings);
    }

    pub fn transcription(self: *Self, model_id: []const u8) DeepgramTranscriptionModel {
        return self.transcriptionModel(model_id);
    }

    pub fn speechModel(self: *Self, model_id: []const u8) DeepgramSpeechModel {
        return DeepgramSpeechModel.init(self.allocator, model_id, self.base_url, self.settings);
    }

    pub fn speech(self: *Self, model_id: []const u8) DeepgramSpeechModel {
        return self.speechModel(model_id);
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
    return std.posix.getenv("DEEPGRAM_API_KEY");
}

/// Get headers for API requests. Caller owns the returned HashMap.
pub fn getHeaders(allocator: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
    var headers = std.StringHashMap([]const u8).init(allocator);
    errdefer headers.deinit();

    try headers.put("Content-Type", "application/json");

    if (getApiKeyFromEnv()) |api_key| {
        const auth_header = try std.fmt.allocPrint(allocator, "Token {s}", .{api_key});
        try headers.put("Authorization", auth_header);
    }

    return headers;
}

pub fn createDeepgram(allocator: std.mem.Allocator) DeepgramProvider {
    return DeepgramProvider.init(allocator, .{});
}

pub fn createDeepgramWithSettings(
    allocator: std.mem.Allocator,
    settings: DeepgramProviderSettings,
) DeepgramProvider {
    return DeepgramProvider.init(allocator, settings);
}

// ============================================================================
// Tests
// ============================================================================

test "DeepgramProvider basic initialization" {
    const allocator = std.testing.allocator;
    var provider = createDeepgram(allocator);
    defer provider.deinit();

    try std.testing.expectEqualStrings("deepgram", provider.getProvider());
    try std.testing.expectEqualStrings("https://api.deepgram.com", provider.base_url);
    try std.testing.expectEqual(@as(?[]const u8, null), provider.settings.api_key);
}

test "DeepgramProvider with custom settings" {
    const allocator = std.testing.allocator;

    var provider = createDeepgramWithSettings(allocator, .{
        .base_url = "https://custom.deepgram.com",
        .api_key = "test-api-key",
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("deepgram", provider.getProvider());
    try std.testing.expectEqualStrings("https://custom.deepgram.com", provider.base_url);
    try std.testing.expectEqualStrings("test-api-key", provider.settings.api_key.?);
}

test "DeepgramProvider with default base_url when null" {
    const allocator = std.testing.allocator;

    var provider = createDeepgramWithSettings(allocator, .{
        .base_url = null,
    });
    defer provider.deinit();

    try std.testing.expectEqualStrings("https://api.deepgram.com", provider.base_url);
}

test "DeepgramProvider specification version" {
    try std.testing.expectEqualStrings("v3", DeepgramProvider.specification_version);
}

test "DeepgramProvider transcription model creation" {
    const allocator = std.testing.allocator;
    var provider = createDeepgram(allocator);
    defer provider.deinit();

    const model = provider.transcriptionModel(TranscriptionModels.nova_2);
    try std.testing.expectEqualStrings("nova-2", model.getModelId());
    try std.testing.expectEqualStrings("deepgram.transcription", model.getProvider());
}

test "DeepgramProvider transcription alias" {
    const allocator = std.testing.allocator;
    var provider = createDeepgram(allocator);
    defer provider.deinit();

    const model = provider.transcription(TranscriptionModels.nova_2_general);
    try std.testing.expectEqualStrings("nova-2-general", model.getModelId());
}

test "DeepgramProvider speech model creation" {
    const allocator = std.testing.allocator;
    var provider = createDeepgram(allocator);
    defer provider.deinit();

    const model = provider.speechModel(SpeechModels.aura_asteria_en);
    try std.testing.expectEqualStrings("aura-asteria-en", model.getModelId());
    try std.testing.expectEqualStrings("deepgram.speech", model.getProvider());
}

test "DeepgramProvider speech alias" {
    const allocator = std.testing.allocator;
    var provider = createDeepgram(allocator);
    defer provider.deinit();

    const model = provider.speech(SpeechModels.aura_luna_en);
    try std.testing.expectEqualStrings("aura-luna-en", model.getModelId());
}

test "DeepgramTranscriptionModel initialization" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};

    const model = DeepgramTranscriptionModel.init(
        allocator,
        "nova-2",
        "https://api.deepgram.com",
        settings,
    );

    try std.testing.expectEqualStrings("nova-2", model.getModelId());
    try std.testing.expectEqualStrings("deepgram.transcription", model.getProvider());
    try std.testing.expectEqualStrings("https://api.deepgram.com", model.base_url);
}

test "DeepgramTranscriptionModel buildQueryParams with no options" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramTranscriptionModel.init(
        allocator,
        "nova-2",
        "https://api.deepgram.com",
        settings,
    );

    const options = TranscriptionOptions{};
    const params = try model.buildQueryParams(options);
    defer allocator.free(params);

    try std.testing.expectEqualStrings("model=nova-2", params);
}

test "DeepgramTranscriptionModel buildQueryParams with language" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramTranscriptionModel.init(
        allocator,
        "nova-2",
        "https://api.deepgram.com",
        settings,
    );

    const options = TranscriptionOptions{
        .language = "en-US",
    };
    const params = try model.buildQueryParams(options);
    defer allocator.free(params);

    try std.testing.expectEqualStrings("model=nova-2&language=en-US", params);
}

test "DeepgramTranscriptionModel buildQueryParams with boolean options" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramTranscriptionModel.init(
        allocator,
        "nova-2",
        "https://api.deepgram.com",
        settings,
    );

    const options = TranscriptionOptions{
        .detect_language = true,
        .punctuate = true,
        .profanity_filter = false,
        .diarize = true,
    };
    const params = try model.buildQueryParams(options);
    defer allocator.free(params);

    try std.testing.expect(std.mem.indexOf(u8, params, "detect_language=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "punctuate=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "profanity_filter=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "diarize=true") != null);
}

test "DeepgramTranscriptionModel buildQueryParams with smart_format" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramTranscriptionModel.init(
        allocator,
        "nova-2",
        "https://api.deepgram.com",
        settings,
    );

    const options = TranscriptionOptions{
        .smart_format = true,
        .filler_words = true,
    };
    const params = try model.buildQueryParams(options);
    defer allocator.free(params);

    try std.testing.expect(std.mem.indexOf(u8, params, "smart_format=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "filler_words=true") != null);
}

test "DeepgramTranscriptionModel buildQueryParams with array options" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramTranscriptionModel.init(
        allocator,
        "nova-2",
        "https://api.deepgram.com",
        settings,
    );

    const redact_items = [_][]const u8{ "pci", "ssn", "numbers" };
    const search_terms = [_][]const u8{ "hello", "world" };
    const options = TranscriptionOptions{
        .redact = &redact_items,
        .search = &search_terms,
    };
    const params = try model.buildQueryParams(options);
    defer allocator.free(params);

    try std.testing.expect(std.mem.indexOf(u8, params, "redact=pci") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "redact=ssn") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "redact=numbers") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "search=hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "search=world") != null);
}

test "DeepgramTranscriptionModel buildQueryParams with numeric options" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramTranscriptionModel.init(
        allocator,
        "nova-2",
        "https://api.deepgram.com",
        settings,
    );

    const options = TranscriptionOptions{
        .alternatives = 3,
        .utt_split = 0.8,
    };
    const params = try model.buildQueryParams(options);
    defer allocator.free(params);

    try std.testing.expect(std.mem.indexOf(u8, params, "alternatives=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "utt_split=") != null);
}

test "DeepgramTranscriptionModel buildQueryParams with intelligence features" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramTranscriptionModel.init(
        allocator,
        "nova-2",
        "https://api.deepgram.com",
        settings,
    );

    const options = TranscriptionOptions{
        .summarize = true,
        .detect_topics = true,
        .detect_entities = true,
        .sentiment = true,
        .intents = true,
    };
    const params = try model.buildQueryParams(options);
    defer allocator.free(params);

    try std.testing.expect(std.mem.indexOf(u8, params, "summarize=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "detect_topics=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "detect_entities=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "sentiment=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "intents=true") != null);
}

test "DeepgramTranscriptionModel buildQueryParams with all options" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramTranscriptionModel.init(
        allocator,
        "nova-2-medical",
        "https://api.deepgram.com",
        settings,
    );

    const keywords = [_][]const u8{ "keyword1", "keyword2" };
    const options = TranscriptionOptions{
        .language = "en",
        .detect_language = false,
        .punctuate = true,
        .profanity_filter = true,
        .diarize = true,
        .diarize_version = "2024-01",
        .smart_format = true,
        .filler_words = false,
        .multichannel = false,
        .alternatives = 2,
        .numerals = true,
        .keywords = &keywords,
        .utterances = true,
        .paragraphs = true,
        .summarize = false,
        .detect_topics = false,
        .detect_entities = false,
        .sentiment = false,
        .intents = false,
    };
    const params = try model.buildQueryParams(options);
    defer allocator.free(params);

    // Verify model ID is always first
    try std.testing.expect(std.mem.startsWith(u8, params, "model=nova-2-medical"));
    // Verify some key parameters are present
    try std.testing.expect(std.mem.indexOf(u8, params, "language=en") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "diarize=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "keyword1") != null);
}

test "DeepgramSpeechModel initialization" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};

    const model = DeepgramSpeechModel.init(
        allocator,
        "aura-asteria-en",
        "https://api.deepgram.com",
        settings,
    );

    try std.testing.expectEqualStrings("aura-asteria-en", model.getModelId());
    try std.testing.expectEqualStrings("deepgram.speech", model.getProvider());
    try std.testing.expectEqualStrings("https://api.deepgram.com", model.base_url);
}

test "DeepgramSpeechModel buildRequestBody with text only" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramSpeechModel.init(
        allocator,
        "aura-asteria-en",
        "https://api.deepgram.com",
        settings,
    );

    const options = SpeechOptions{};
    var body = try model.buildRequestBody("Hello, world!", options);
    defer body.object.deinit();

    try std.testing.expectEqual(std.json.Value{ .string = "Hello, world!" }, body.object.get("text").?);
    try std.testing.expect(body.object.get("encoding") == null);
    try std.testing.expect(body.object.get("container") == null);
}

test "DeepgramSpeechModel buildRequestBody with encoding options" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramSpeechModel.init(
        allocator,
        "aura-luna-en",
        "https://api.deepgram.com",
        settings,
    );

    const options = SpeechOptions{
        .encoding = "mp3",
        .container = "mp3",
    };
    var body = try model.buildRequestBody("Test text", options);
    defer body.object.deinit();

    try std.testing.expectEqual(std.json.Value{ .string = "Test text" }, body.object.get("text").?);
    try std.testing.expectEqualStrings("mp3", body.object.get("encoding").?.string);
    try std.testing.expectEqualStrings("mp3", body.object.get("container").?.string);
}

test "DeepgramSpeechModel buildRequestBody with sample and bit rate" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramSpeechModel.init(
        allocator,
        "aura-orion-en",
        "https://api.deepgram.com",
        settings,
    );

    const options = SpeechOptions{
        .encoding = "linear16",
        .container = "wav",
        .sample_rate = 48000,
        .bit_rate = 128000,
    };
    var body = try model.buildRequestBody("Quality test", options);
    defer body.object.deinit();

    try std.testing.expectEqual(@as(i64, 48000), body.object.get("sample_rate").?.integer);
    try std.testing.expectEqual(@as(i64, 128000), body.object.get("bit_rate").?.integer);
}

test "DeepgramSpeechModel buildRequestBody with all options" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramSpeechModel.init(
        allocator,
        "aura-zeus-en",
        "https://api.deepgram.com",
        settings,
    );

    const options = SpeechOptions{
        .encoding = "opus",
        .container = "ogg",
        .sample_rate = 24000,
        .bit_rate = 64000,
    };
    var body = try model.buildRequestBody("Complete test", options);
    defer body.object.deinit();

    try std.testing.expectEqual(std.json.Value{ .string = "Complete test" }, body.object.get("text").?);
    try std.testing.expectEqualStrings("opus", body.object.get("encoding").?.string);
    try std.testing.expectEqualStrings("ogg", body.object.get("container").?.string);
    try std.testing.expectEqual(@as(i64, 24000), body.object.get("sample_rate").?.integer);
    try std.testing.expectEqual(@as(i64, 64000), body.object.get("bit_rate").?.integer);
}

test "TranscriptionModels constants" {
    try std.testing.expectEqualStrings("nova-2", TranscriptionModels.nova_2);
    try std.testing.expectEqualStrings("nova-2-general", TranscriptionModels.nova_2_general);
    try std.testing.expectEqualStrings("nova-2-meeting", TranscriptionModels.nova_2_meeting);
    try std.testing.expectEqualStrings("nova-2-phonecall", TranscriptionModels.nova_2_phonecall);
    try std.testing.expectEqualStrings("nova-2-voicemail", TranscriptionModels.nova_2_voicemail);
    try std.testing.expectEqualStrings("nova-2-finance", TranscriptionModels.nova_2_finance);
    try std.testing.expectEqualStrings("nova-2-conversational", TranscriptionModels.nova_2_conversational);
    try std.testing.expectEqualStrings("nova-2-video", TranscriptionModels.nova_2_video);
    try std.testing.expectEqualStrings("nova-2-medical", TranscriptionModels.nova_2_medical);
    try std.testing.expectEqualStrings("nova-2-drivethru", TranscriptionModels.nova_2_drivethru);
    try std.testing.expectEqualStrings("nova-2-automotive", TranscriptionModels.nova_2_automotive);
    try std.testing.expectEqualStrings("nova", TranscriptionModels.nova);
    try std.testing.expectEqualStrings("enhanced", TranscriptionModels.enhanced);
    try std.testing.expectEqualStrings("base", TranscriptionModels.base);
    try std.testing.expectEqualStrings("whisper", TranscriptionModels.whisper);
}

test "SpeechModels constants" {
    try std.testing.expectEqualStrings("aura-asteria-en", SpeechModels.aura_asteria_en);
    try std.testing.expectEqualStrings("aura-luna-en", SpeechModels.aura_luna_en);
    try std.testing.expectEqualStrings("aura-stella-en", SpeechModels.aura_stella_en);
    try std.testing.expectEqualStrings("aura-athena-en", SpeechModels.aura_athena_en);
    try std.testing.expectEqualStrings("aura-hera-en", SpeechModels.aura_hera_en);
    try std.testing.expectEqualStrings("aura-orion-en", SpeechModels.aura_orion_en);
    try std.testing.expectEqualStrings("aura-arcas-en", SpeechModels.aura_arcas_en);
    try std.testing.expectEqualStrings("aura-perseus-en", SpeechModels.aura_perseus_en);
    try std.testing.expectEqualStrings("aura-angus-en", SpeechModels.aura_angus_en);
    try std.testing.expectEqualStrings("aura-orpheus-en", SpeechModels.aura_orpheus_en);
    try std.testing.expectEqualStrings("aura-helios-en", SpeechModels.aura_helios_en);
    try std.testing.expectEqualStrings("aura-zeus-en", SpeechModels.aura_zeus_en);
}

test "TranscriptionOptions default values" {
    const options = TranscriptionOptions{};

    try std.testing.expect(options.language == null);
    try std.testing.expect(options.detect_language == null);
    try std.testing.expect(options.punctuate == null);
    try std.testing.expect(options.profanity_filter == null);
    try std.testing.expect(options.redact == null);
    try std.testing.expect(options.diarize == null);
    try std.testing.expect(options.diarize_version == null);
    try std.testing.expect(options.smart_format == null);
    try std.testing.expect(options.filler_words == null);
    try std.testing.expect(options.multichannel == null);
    try std.testing.expect(options.alternatives == null);
    try std.testing.expect(options.numerals == null);
    try std.testing.expect(options.search == null);
    try std.testing.expect(options.replace == null);
    try std.testing.expect(options.keywords == null);
    try std.testing.expect(options.utterances == null);
    try std.testing.expect(options.utt_split == null);
    try std.testing.expect(options.paragraphs == null);
    try std.testing.expect(options.summarize == null);
    try std.testing.expect(options.detect_topics == null);
    try std.testing.expect(options.detect_entities == null);
    try std.testing.expect(options.sentiment == null);
    try std.testing.expect(options.intents == null);
}

test "SpeechOptions default values" {
    const options = SpeechOptions{};

    try std.testing.expect(options.encoding == null);
    try std.testing.expect(options.container == null);
    try std.testing.expect(options.sample_rate == null);
    try std.testing.expect(options.bit_rate == null);
}

test "DeepgramProviderSettings default values" {
    const settings = DeepgramProviderSettings{};

    try std.testing.expect(settings.base_url == null);
    try std.testing.expect(settings.api_key == null);
    try std.testing.expect(settings.headers == null);
    try std.testing.expect(settings.http_client == null);
}

test "DeepgramProvider asProvider vtable" {
    const allocator = std.testing.allocator;
    var provider = createDeepgram(allocator);
    defer provider.deinit();

    const prov = provider.asProvider();
    const result = prov.vtable.languageModel(prov.impl, "test-model");
    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }
}

test "DeepgramProvider languageModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createDeepgram(allocator);
    defer provider.deinit();

    const prov = provider.asProvider();
    const result = prov.vtable.languageModel(prov.impl, "any-model");
    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }
}

test "DeepgramProvider embeddingModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createDeepgram(allocator);
    defer provider.deinit();

    const prov = provider.asProvider();
    const result = prov.vtable.embeddingModel(prov.impl, "any-model");
    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }
}

test "DeepgramProvider imageModel returns error" {
    const allocator = std.testing.allocator;
    var provider = createDeepgram(allocator);
    defer provider.deinit();

    const prov = provider.asProvider();
    const result = prov.vtable.imageModel(prov.impl, "any-model");
    switch (result) {
        .success => try std.testing.expect(false),
        .failure, .no_such_model => {},
    }
}

test "DeepgramTranscriptionModel all model constants" {
    const allocator = std.testing.allocator;
    var provider = createDeepgram(allocator);
    defer provider.deinit();

    // Test each transcription model constant
    const models = [_][]const u8{
        TranscriptionModels.nova_2,
        TranscriptionModels.nova_2_general,
        TranscriptionModels.nova_2_meeting,
        TranscriptionModels.nova_2_phonecall,
        TranscriptionModels.nova_2_voicemail,
        TranscriptionModels.nova_2_finance,
        TranscriptionModels.nova_2_conversational,
        TranscriptionModels.nova_2_video,
        TranscriptionModels.nova_2_medical,
        TranscriptionModels.nova_2_drivethru,
        TranscriptionModels.nova_2_automotive,
        TranscriptionModels.nova,
        TranscriptionModels.enhanced,
        TranscriptionModels.base,
        TranscriptionModels.whisper,
    };

    for (models) |model_id| {
        const model = provider.transcriptionModel(model_id);
        try std.testing.expectEqualStrings(model_id, model.getModelId());
        try std.testing.expectEqualStrings("deepgram.transcription", model.getProvider());
    }
}

test "DeepgramSpeechModel all model constants" {
    const allocator = std.testing.allocator;
    var provider = createDeepgram(allocator);
    defer provider.deinit();

    // Test each speech model constant
    const models = [_][]const u8{
        SpeechModels.aura_asteria_en,
        SpeechModels.aura_luna_en,
        SpeechModels.aura_stella_en,
        SpeechModels.aura_athena_en,
        SpeechModels.aura_hera_en,
        SpeechModels.aura_orion_en,
        SpeechModels.aura_arcas_en,
        SpeechModels.aura_perseus_en,
        SpeechModels.aura_angus_en,
        SpeechModels.aura_orpheus_en,
        SpeechModels.aura_helios_en,
        SpeechModels.aura_zeus_en,
    };

    for (models) |model_id| {
        const model = provider.speechModel(model_id);
        try std.testing.expectEqualStrings(model_id, model.getModelId());
        try std.testing.expectEqualStrings("deepgram.speech", model.getProvider());
    }
}

test "DeepgramTranscriptionModel empty arrays in buildQueryParams" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramTranscriptionModel.init(
        allocator,
        "nova-2",
        "https://api.deepgram.com",
        settings,
    );

    const empty_redact = [_][]const u8{};
    const options = TranscriptionOptions{
        .redact = &empty_redact,
    };
    const params = try model.buildQueryParams(options);
    defer allocator.free(params);

    // Should only contain the model parameter
    try std.testing.expectEqualStrings("model=nova-2", params);
}

test "DeepgramTranscriptionModel single item array in buildQueryParams" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramTranscriptionModel.init(
        allocator,
        "enhanced",
        "https://api.deepgram.com",
        settings,
    );

    const keywords = [_][]const u8{"important"};
    const options = TranscriptionOptions{
        .keywords = &keywords,
    };
    const params = try model.buildQueryParams(options);
    defer allocator.free(params);

    try std.testing.expect(std.mem.indexOf(u8, params, "keywords=important") != null);
}

test "DeepgramSpeechModel empty text in buildRequestBody" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramSpeechModel.init(
        allocator,
        "aura-asteria-en",
        "https://api.deepgram.com",
        settings,
    );

    const options = SpeechOptions{};
    var body = try model.buildRequestBody("", options);
    defer body.object.deinit();

    try std.testing.expectEqual(std.json.Value{ .string = "" }, body.object.get("text").?);
}

test "DeepgramTranscriptionModel buildQueryParams edge case: zero values" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramTranscriptionModel.init(
        allocator,
        "base",
        "https://api.deepgram.com",
        settings,
    );

    const options = TranscriptionOptions{
        .alternatives = 0,
        .utt_split = 0.0,
    };
    const params = try model.buildQueryParams(options);
    defer allocator.free(params);

    try std.testing.expect(std.mem.indexOf(u8, params, "alternatives=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, params, "utt_split=") != null);
}

test "DeepgramSpeechModel buildRequestBody edge case: zero values" {
    const allocator = std.testing.allocator;
    const settings = DeepgramProviderSettings{};
    const model = DeepgramSpeechModel.init(
        allocator,
        "aura-helios-en",
        "https://api.deepgram.com",
        settings,
    );

    const options = SpeechOptions{
        .sample_rate = 0,
        .bit_rate = 0,
    };
    var body = try model.buildRequestBody("test", options);
    defer body.object.deinit();

    try std.testing.expectEqual(@as(i64, 0), body.object.get("sample_rate").?.integer);
    try std.testing.expectEqual(@as(i64, 0), body.object.get("bit_rate").?.integer);
}
