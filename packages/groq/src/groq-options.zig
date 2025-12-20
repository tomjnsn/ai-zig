const std = @import("std");

/// Groq chat model IDs
pub const ChatModels = struct {
    // Production models
    pub const gemma2_9b_it = "gemma2-9b-it";
    pub const llama_3_1_8b_instant = "llama-3.1-8b-instant";
    pub const llama_3_3_70b_versatile = "llama-3.3-70b-versatile";
    pub const llama_guard_4_12b = "meta-llama/llama-guard-4-12b";
    pub const gpt_oss_120b = "openai/gpt-oss-120b";
    pub const gpt_oss_20b = "openai/gpt-oss-20b";

    // Preview models
    pub const deepseek_r1_distill_llama_70b = "deepseek-r1-distill-llama-70b";
    pub const llama_4_maverick_17b = "meta-llama/llama-4-maverick-17b-128e-instruct";
    pub const llama_4_scout_17b = "meta-llama/llama-4-scout-17b-16e-instruct";
    pub const kimi_k2_instruct = "moonshotai/kimi-k2-instruct-0905";
    pub const qwen3_32b = "qwen/qwen3-32b";
    pub const llama_guard_3_8b = "llama-guard-3-8b";
    pub const llama3_70b_8192 = "llama3-70b-8192";
    pub const llama3_8b_8192 = "llama3-8b-8192";
    pub const mixtral_8x7b_32768 = "mixtral-8x7b-32768";
    pub const qwen_qwq_32b = "qwen-qwq-32b";
    pub const qwen_2_5_32b = "qwen-2.5-32b";
    pub const deepseek_r1_distill_qwen_32b = "deepseek-r1-distill-qwen-32b";
};

/// Groq transcription model IDs
pub const TranscriptionModels = struct {
    pub const whisper_large_v3_turbo = "whisper-large-v3-turbo";
    pub const whisper_large_v3 = "whisper-large-v3";
};

/// Reasoning format options
pub const ReasoningFormat = enum {
    parsed,
    raw,
    hidden,

    pub fn toString(self: ReasoningFormat) []const u8 {
        return switch (self) {
            .parsed => "parsed",
            .raw => "raw",
            .hidden => "hidden",
        };
    }
};

/// Reasoning effort levels
pub const ReasoningEffort = enum {
    none,
    default,
    low,
    medium,
    high,

    pub fn toString(self: ReasoningEffort) []const u8 {
        return switch (self) {
            .none => "none",
            .default => "default",
            .low => "low",
            .medium => "medium",
            .high => "high",
        };
    }
};

/// Service tier options
pub const ServiceTier = enum {
    on_demand,
    flex,
    auto,

    pub fn toString(self: ServiceTier) []const u8 {
        return switch (self) {
            .on_demand => "on_demand",
            .flex => "flex",
            .auto => "auto",
        };
    }
};

/// Groq provider options
pub const GroqProviderOptions = struct {
    /// Reasoning format for model inference
    reasoning_format: ?ReasoningFormat = null,

    /// Reasoning effort level for model inference
    reasoning_effort: ?ReasoningEffort = null,

    /// Whether to enable parallel function calling during tool use
    parallel_tool_calls: ?bool = null,

    /// A unique identifier representing your end-user
    user: ?[]const u8 = null,

    /// Whether to use structured outputs (default: true)
    structured_outputs: ?bool = null,

    /// Service tier for the request
    service_tier: ?ServiceTier = null,
};

/// Check if a model supports reasoning
pub fn supportsReasoning(model_id: []const u8) bool {
    return std.mem.indexOf(u8, model_id, "deepseek-r1") != null or
        std.mem.indexOf(u8, model_id, "qwq") != null;
}

test "supportsReasoning" {
    try std.testing.expect(supportsReasoning("deepseek-r1-distill-llama-70b"));
    try std.testing.expect(supportsReasoning("qwen-qwq-32b"));
    try std.testing.expect(!supportsReasoning("llama-3.3-70b-versatile"));
}

test "ChatModels constants" {
    try std.testing.expectEqualStrings("gemma2-9b-it", ChatModels.gemma2_9b_it);
    try std.testing.expectEqualStrings("llama-3.1-8b-instant", ChatModels.llama_3_1_8b_instant);
    try std.testing.expectEqualStrings("llama-3.3-70b-versatile", ChatModels.llama_3_3_70b_versatile);
    try std.testing.expectEqualStrings("meta-llama/llama-guard-4-12b", ChatModels.llama_guard_4_12b);
    try std.testing.expectEqualStrings("openai/gpt-oss-120b", ChatModels.gpt_oss_120b);
    try std.testing.expectEqualStrings("openai/gpt-oss-20b", ChatModels.gpt_oss_20b);
}

test "ChatModels preview models" {
    try std.testing.expectEqualStrings("deepseek-r1-distill-llama-70b", ChatModels.deepseek_r1_distill_llama_70b);
    try std.testing.expectEqualStrings("meta-llama/llama-4-maverick-17b-128e-instruct", ChatModels.llama_4_maverick_17b);
    try std.testing.expectEqualStrings("meta-llama/llama-4-scout-17b-16e-instruct", ChatModels.llama_4_scout_17b);
    try std.testing.expectEqualStrings("moonshotai/kimi-k2-instruct-0905", ChatModels.kimi_k2_instruct);
    try std.testing.expectEqualStrings("qwen/qwen3-32b", ChatModels.qwen3_32b);
    try std.testing.expectEqualStrings("llama-guard-3-8b", ChatModels.llama_guard_3_8b);
    try std.testing.expectEqualStrings("llama3-70b-8192", ChatModels.llama3_70b_8192);
    try std.testing.expectEqualStrings("llama3-8b-8192", ChatModels.llama3_8b_8192);
    try std.testing.expectEqualStrings("mixtral-8x7b-32768", ChatModels.mixtral_8x7b_32768);
    try std.testing.expectEqualStrings("qwen-qwq-32b", ChatModels.qwen_qwq_32b);
    try std.testing.expectEqualStrings("qwen-2.5-32b", ChatModels.qwen_2_5_32b);
    try std.testing.expectEqualStrings("deepseek-r1-distill-qwen-32b", ChatModels.deepseek_r1_distill_qwen_32b);
}

test "TranscriptionModels constants" {
    try std.testing.expectEqualStrings("whisper-large-v3-turbo", TranscriptionModels.whisper_large_v3_turbo);
    try std.testing.expectEqualStrings("whisper-large-v3", TranscriptionModels.whisper_large_v3);
}

test "ReasoningFormat toString" {
    try std.testing.expectEqualStrings("parsed", ReasoningFormat.parsed.toString());
    try std.testing.expectEqualStrings("raw", ReasoningFormat.raw.toString());
    try std.testing.expectEqualStrings("hidden", ReasoningFormat.hidden.toString());
}

test "ReasoningEffort toString" {
    try std.testing.expectEqualStrings("none", ReasoningEffort.none.toString());
    try std.testing.expectEqualStrings("default", ReasoningEffort.default.toString());
    try std.testing.expectEqualStrings("low", ReasoningEffort.low.toString());
    try std.testing.expectEqualStrings("medium", ReasoningEffort.medium.toString());
    try std.testing.expectEqualStrings("high", ReasoningEffort.high.toString());
}

test "ServiceTier toString" {
    try std.testing.expectEqualStrings("on_demand", ServiceTier.on_demand.toString());
    try std.testing.expectEqualStrings("flex", ServiceTier.flex.toString());
    try std.testing.expectEqualStrings("auto", ServiceTier.auto.toString());
}

test "GroqProviderOptions default values" {
    const options = GroqProviderOptions{};

    try std.testing.expect(options.reasoning_format == null);
    try std.testing.expect(options.reasoning_effort == null);
    try std.testing.expect(options.parallel_tool_calls == null);
    try std.testing.expect(options.user == null);
    try std.testing.expect(options.structured_outputs == null);
    try std.testing.expect(options.service_tier == null);
}

test "GroqProviderOptions with custom values" {
    const options = GroqProviderOptions{
        .reasoning_format = .parsed,
        .reasoning_effort = .high,
        .parallel_tool_calls = true,
        .user = "test-user",
        .structured_outputs = true,
        .service_tier = .flex,
    };

    try std.testing.expect(options.reasoning_format != null);
    try std.testing.expectEqual(ReasoningFormat.parsed, options.reasoning_format.?);
    try std.testing.expect(options.reasoning_effort != null);
    try std.testing.expectEqual(ReasoningEffort.high, options.reasoning_effort.?);
    try std.testing.expect(options.parallel_tool_calls != null);
    try std.testing.expectEqual(true, options.parallel_tool_calls.?);
    try std.testing.expect(options.user != null);
    try std.testing.expectEqualStrings("test-user", options.user.?);
    try std.testing.expect(options.structured_outputs != null);
    try std.testing.expectEqual(true, options.structured_outputs.?);
    try std.testing.expect(options.service_tier != null);
    try std.testing.expectEqual(ServiceTier.flex, options.service_tier.?);
}

test "supportsReasoning with various model IDs" {
    // Models that support reasoning
    try std.testing.expect(supportsReasoning("deepseek-r1-distill-llama-70b"));
    try std.testing.expect(supportsReasoning("deepseek-r1-distill-qwen-32b"));
    try std.testing.expect(supportsReasoning("qwen-qwq-32b"));
    try std.testing.expect(supportsReasoning("model-with-deepseek-r1-suffix"));
    try std.testing.expect(supportsReasoning("model-with-qwq-in-name"));

    // Models that do not support reasoning
    try std.testing.expect(!supportsReasoning("llama-3.3-70b-versatile"));
    try std.testing.expect(!supportsReasoning("llama-3.1-8b-instant"));
    try std.testing.expect(!supportsReasoning("gemma2-9b-it"));
    try std.testing.expect(!supportsReasoning("mixtral-8x7b-32768"));
    try std.testing.expect(!supportsReasoning("whisper-large-v3"));
    try std.testing.expect(!supportsReasoning(""));
}

test "ReasoningFormat enum values" {
    const parsed = ReasoningFormat.parsed;
    const raw = ReasoningFormat.raw;
    const hidden = ReasoningFormat.hidden;

    try std.testing.expect(parsed != raw);
    try std.testing.expect(raw != hidden);
    try std.testing.expect(hidden != parsed);
}

test "ReasoningEffort enum values" {
    const none = ReasoningEffort.none;
    const default = ReasoningEffort.default;
    const low = ReasoningEffort.low;
    const medium = ReasoningEffort.medium;
    const high = ReasoningEffort.high;

    try std.testing.expect(none != default);
    try std.testing.expect(low != medium);
    try std.testing.expect(medium != high);
}

test "ServiceTier enum values" {
    const on_demand = ServiceTier.on_demand;
    const flex = ServiceTier.flex;
    const auto = ServiceTier.auto;

    try std.testing.expect(on_demand != flex);
    try std.testing.expect(flex != auto);
    try std.testing.expect(auto != on_demand);
}
