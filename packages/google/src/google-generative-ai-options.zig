const std = @import("std");

/// Google Generative AI model identifiers
pub const Models = struct {
    // Gemini 1.5 models
    pub const gemini_1_5_flash = "gemini-1.5-flash";
    pub const gemini_1_5_flash_latest = "gemini-1.5-flash-latest";
    pub const gemini_1_5_flash_001 = "gemini-1.5-flash-001";
    pub const gemini_1_5_flash_002 = "gemini-1.5-flash-002";
    pub const gemini_1_5_flash_8b = "gemini-1.5-flash-8b";
    pub const gemini_1_5_flash_8b_latest = "gemini-1.5-flash-8b-latest";
    pub const gemini_1_5_flash_8b_001 = "gemini-1.5-flash-8b-001";
    pub const gemini_1_5_pro = "gemini-1.5-pro";
    pub const gemini_1_5_pro_latest = "gemini-1.5-pro-latest";
    pub const gemini_1_5_pro_001 = "gemini-1.5-pro-001";
    pub const gemini_1_5_pro_002 = "gemini-1.5-pro-002";

    // Gemini 2.0 models
    pub const gemini_2_0_flash = "gemini-2.0-flash";
    pub const gemini_2_0_flash_001 = "gemini-2.0-flash-001";
    pub const gemini_2_0_flash_lite = "gemini-2.0-flash-lite";
    pub const gemini_2_0_flash_exp = "gemini-2.0-flash-exp";
    pub const gemini_2_0_flash_thinking_exp = "gemini-2.0-flash-thinking-exp-01-21";

    // Gemini 2.5 models
    pub const gemini_2_5_pro = "gemini-2.5-pro";
    pub const gemini_2_5_flash = "gemini-2.5-flash";
    pub const gemini_2_5_flash_lite = "gemini-2.5-flash-lite";

    // Gemini 3 models
    pub const gemini_3_pro_preview = "gemini-3-pro-preview";
    pub const gemini_3_flash_preview = "gemini-3-flash-preview";

    // Latest aliases
    pub const gemini_pro_latest = "gemini-pro-latest";
    pub const gemini_flash_latest = "gemini-flash-latest";
    pub const gemini_flash_lite_latest = "gemini-flash-lite-latest";

    // Gemma models
    pub const gemma_3_12b_it = "gemma-3-12b-it";
    pub const gemma_3_27b_it = "gemma-3-27b-it";
};

/// Embedding model identifiers
pub const EmbeddingModels = struct {
    pub const gemini_embedding_001 = "gemini-embedding-001";
    pub const text_embedding_004 = "text-embedding-004";
};

/// Image model identifiers
pub const ImageModels = struct {
    pub const imagen_4_0_generate = "imagen-4.0-generate-001";
    pub const imagen_4_0_ultra = "imagen-4.0-ultra-generate-001";
    pub const imagen_4_0_fast = "imagen-4.0-fast-generate-001";
    // Gemini image models (use generateContent endpoint, not predict)
    pub const gemini_2_5_flash_image = "gemini-2.5-flash-image";
    pub const gemini_3_pro_image_preview = "gemini-3-pro-image-preview";
};

/// Harm category for safety settings
pub const HarmCategory = enum {
    unspecified,
    hate_speech,
    dangerous_content,
    harassment,
    sexually_explicit,
    civic_integrity,

    pub fn toString(self: HarmCategory) []const u8 {
        return switch (self) {
            .unspecified => "HARM_CATEGORY_UNSPECIFIED",
            .hate_speech => "HARM_CATEGORY_HATE_SPEECH",
            .dangerous_content => "HARM_CATEGORY_DANGEROUS_CONTENT",
            .harassment => "HARM_CATEGORY_HARASSMENT",
            .sexually_explicit => "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            .civic_integrity => "HARM_CATEGORY_CIVIC_INTEGRITY",
        };
    }
};

/// Harm block threshold for safety settings
pub const HarmBlockThreshold = enum {
    unspecified,
    block_low_and_above,
    block_medium_and_above,
    block_only_high,
    block_none,
    off,

    pub fn toString(self: HarmBlockThreshold) []const u8 {
        return switch (self) {
            .unspecified => "HARM_BLOCK_THRESHOLD_UNSPECIFIED",
            .block_low_and_above => "BLOCK_LOW_AND_ABOVE",
            .block_medium_and_above => "BLOCK_MEDIUM_AND_ABOVE",
            .block_only_high => "BLOCK_ONLY_HIGH",
            .block_none => "BLOCK_NONE",
            .off => "OFF",
        };
    }
};

/// Safety setting for content generation
pub const SafetySetting = struct {
    category: HarmCategory,
    threshold: HarmBlockThreshold,
};

/// Thinking configuration for models that support extended thinking
pub const ThinkingConfig = struct {
    /// Budget for thinking tokens
    thinking_budget: ?u32 = null,

    /// Whether to include thoughts in the response
    include_thoughts: ?bool = null,

    /// Thinking level (minimal, low, medium, high)
    thinking_level: ?ThinkingLevel = null,

    pub const ThinkingLevel = enum {
        minimal,
        low,
        medium,
        high,

        pub fn toString(self: ThinkingLevel) []const u8 {
            return switch (self) {
                .minimal => "minimal",
                .low => "low",
                .medium => "medium",
                .high => "high",
            };
        }
    };
};

/// Response modality options
pub const ResponseModality = enum {
    text,
    image,

    pub fn toString(self: ResponseModality) []const u8 {
        return switch (self) {
            .text => "TEXT",
            .image => "IMAGE",
        };
    }
};

/// Media resolution options
pub const MediaResolution = enum {
    unspecified,
    low,
    medium,
    high,

    pub fn toString(self: MediaResolution) []const u8 {
        return switch (self) {
            .unspecified => "MEDIA_RESOLUTION_UNSPECIFIED",
            .low => "MEDIA_RESOLUTION_LOW",
            .medium => "MEDIA_RESOLUTION_MEDIUM",
            .high => "MEDIA_RESOLUTION_HIGH",
        };
    }
};

/// Image configuration options
pub const ImageConfig = struct {
    /// Aspect ratio for image generation
    aspect_ratio: ?AspectRatio = null,

    /// Image size
    image_size: ?ImageSize = null,

    pub const AspectRatio = enum {
        @"1:1",
        @"2:3",
        @"3:2",
        @"3:4",
        @"4:3",
        @"4:5",
        @"5:4",
        @"9:16",
        @"16:9",
        @"21:9",

        pub fn toString(self: AspectRatio) []const u8 {
            return switch (self) {
                .@"1:1" => "1:1",
                .@"2:3" => "2:3",
                .@"3:2" => "3:2",
                .@"3:4" => "3:4",
                .@"4:3" => "4:3",
                .@"4:5" => "4:5",
                .@"5:4" => "5:4",
                .@"9:16" => "9:16",
                .@"16:9" => "16:9",
                .@"21:9" => "21:9",
            };
        }
    };

    pub const ImageSize = enum {
        @"1K",
        @"2K",
        @"4K",

        pub fn toString(self: ImageSize) []const u8 {
            return switch (self) {
                .@"1K" => "1K",
                .@"2K" => "2K",
                .@"4K" => "4K",
            };
        }
    };
};

/// Retrieval configuration for grounding
pub const RetrievalConfig = struct {
    lat_lng: ?LatLng = null,

    pub const LatLng = struct {
        latitude: f64,
        longitude: f64,
    };
};

/// Provider options for Google Generative AI
pub const GoogleGenerativeAIProviderOptions = struct {
    /// Response modalities (TEXT, IMAGE)
    response_modalities: ?[]const ResponseModality = null,

    /// Extended thinking configuration
    thinking_config: ?ThinkingConfig = null,

    /// Cached content ID
    cached_content: ?[]const u8 = null,

    /// Enable structured outputs
    structured_outputs: ?bool = null,

    /// Safety settings
    safety_settings: ?[]const SafetySetting = null,

    /// Default harm block threshold
    threshold: ?HarmBlockThreshold = null,

    /// Enable audio timestamp
    audio_timestamp: ?bool = null,

    /// Labels for billing
    labels: ?std.StringHashMap([]const u8) = null,

    /// Media resolution
    media_resolution: ?MediaResolution = null,

    /// Image configuration
    image_config: ?ImageConfig = null,

    /// Retrieval configuration for grounding
    retrieval_config: ?RetrievalConfig = null,
};

/// Embedding provider options
pub const GoogleGenerativeAIEmbeddingProviderOptions = struct {
    /// Output dimensionality for embeddings
    output_dimensionality: ?u32 = null,

    /// Task type for embeddings
    task_type: ?TaskType = null,

    pub const TaskType = enum {
        semantic_similarity,
        classification,
        clustering,
        retrieval_document,
        retrieval_query,
        question_answering,
        fact_verification,
        code_retrieval_query,

        pub fn toString(self: TaskType) []const u8 {
            return switch (self) {
                .semantic_similarity => "SEMANTIC_SIMILARITY",
                .classification => "CLASSIFICATION",
                .clustering => "CLUSTERING",
                .retrieval_document => "RETRIEVAL_DOCUMENT",
                .retrieval_query => "RETRIEVAL_QUERY",
                .question_answering => "QUESTION_ANSWERING",
                .fact_verification => "FACT_VERIFICATION",
                .code_retrieval_query => "CODE_RETRIEVAL_QUERY",
            };
        }
    };
};

/// Image generation settings
pub const GoogleGenerativeAIImageSettings = struct {
    /// Maximum images per call (default 4)
    max_images_per_call: ?u32 = null,
};

/// Image provider options
pub const GoogleGenerativeAIImageProviderOptions = struct {
    /// Person generation setting
    person_generation: ?PersonGeneration = null,

    /// Aspect ratio
    aspect_ratio: ?ImageAspectRatio = null,

    pub const PersonGeneration = enum {
        dont_allow,
        allow_adult,
        allow_all,

        pub fn toString(self: PersonGeneration) []const u8 {
            return switch (self) {
                .dont_allow => "dont_allow",
                .allow_adult => "allow_adult",
                .allow_all => "allow_all",
            };
        }
    };

    pub const ImageAspectRatio = enum {
        @"1:1",
        @"3:4",
        @"4:3",
        @"9:16",
        @"16:9",

        pub fn toString(self: ImageAspectRatio) []const u8 {
            return switch (self) {
                .@"1:1" => "1:1",
                .@"3:4" => "3:4",
                .@"4:3" => "4:3",
                .@"9:16" => "9:16",
                .@"16:9" => "16:9",
            };
        }
    };
};

/// Check if a model is a Gemma model
pub fn isGemmaModel(model_id: []const u8) bool {
    return std.ascii.startsWithIgnoreCase(model_id, "gemma-");
}

/// Check if a model is Gemini 2 or newer
pub fn isGemini2OrNewer(model_id: []const u8) bool {
    return std.mem.indexOf(u8, model_id, "gemini-2") != null or
        std.mem.indexOf(u8, model_id, "gemini-3") != null or
        std.mem.eql(u8, model_id, Models.gemini_flash_latest) or
        std.mem.eql(u8, model_id, Models.gemini_flash_lite_latest) or
        std.mem.eql(u8, model_id, Models.gemini_pro_latest);
}

/// Check if a model supports dynamic retrieval
pub fn supportsDynamicRetrieval(model_id: []const u8) bool {
    return std.mem.indexOf(u8, model_id, "gemini-1.5-flash") != null and
        std.mem.indexOf(u8, model_id, "-8b") == null;
}

/// Check if a model supports file search
pub fn supportsFileSearch(model_id: []const u8) bool {
    return std.mem.indexOf(u8, model_id, "gemini-2.5") != null;
}

test "Models constants" {
    try std.testing.expectEqualStrings("gemini-2.0-flash", Models.gemini_2_0_flash);
    try std.testing.expectEqualStrings("gemini-2.5-pro", Models.gemini_2_5_pro);
}

test "isGemmaModel" {
    try std.testing.expect(isGemmaModel("gemma-3-12b-it"));
    try std.testing.expect(isGemmaModel("GEMMA-3-27b-it"));
    try std.testing.expect(!isGemmaModel("gemini-2.0-flash"));
}

test "isGemini2OrNewer" {
    try std.testing.expect(isGemini2OrNewer("gemini-2.0-flash"));
    try std.testing.expect(isGemini2OrNewer("gemini-2.5-pro"));
    try std.testing.expect(isGemini2OrNewer("gemini-3-pro-preview"));
    try std.testing.expect(!isGemini2OrNewer("gemini-1.5-pro"));
}
