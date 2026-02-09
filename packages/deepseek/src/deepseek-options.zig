const std = @import("std");

/// DeepSeek chat model IDs
pub const ChatModels = struct {
    pub const deepseek_chat = "deepseek-chat";
    pub const deepseek_reasoner = "deepseek-reasoner";
};

/// Thinking configuration
pub const ThinkingConfig = struct {
    type: ThinkingType = .enabled,
};

/// Thinking type
pub const ThinkingType = enum {
    enabled,
    disabled,

    pub fn toString(self: ThinkingType) []const u8 {
        return switch (self) {
            .enabled => "enabled",
            .disabled => "disabled",
        };
    }
};

/// DeepSeek chat options
pub const DeepSeekChatOptions = struct {
    /// Configuration for thinking/reasoning
    thinking: ?ThinkingConfig = null,
};

/// Check if a model supports reasoning
pub fn supportsReasoning(model_id: []const u8) bool {
    return std.mem.eql(u8, model_id, "deepseek-reasoner");
}

test "supportsReasoning" {
    try std.testing.expect(supportsReasoning("deepseek-reasoner"));
    try std.testing.expect(!supportsReasoning("deepseek-chat"));
}

test "ChatModels constants" {
    try std.testing.expectEqualStrings("deepseek-chat", ChatModels.deepseek_chat);
    try std.testing.expectEqualStrings("deepseek-reasoner", ChatModels.deepseek_reasoner);
}

test "ThinkingType toString" {
    try std.testing.expectEqualStrings("enabled", ThinkingType.enabled.toString());
    try std.testing.expectEqualStrings("disabled", ThinkingType.disabled.toString());
}

test "DeepSeekChatOptions defaults" {
    const opts = DeepSeekChatOptions{};
    try std.testing.expect(opts.thinking == null);
}

test "ThinkingConfig default type" {
    const config = ThinkingConfig{};
    try std.testing.expect(config.type == .enabled);
}
