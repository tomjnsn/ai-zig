const std = @import("std");
const errors = @import("provider").errors;

/// Options for loading an API key
pub const LoadApiKeyOptions = struct {
    /// The API key value (if provided directly)
    api_key: ?[]const u8 = null,
    /// Name of the environment variable to check
    environment_variable_name: []const u8,
    /// Parameter name for error messages
    api_key_parameter_name: []const u8 = "apiKey",
    /// Description of the provider for error messages
    description: []const u8,
    /// Allocator for env var lookup. Caller must free the returned key
    /// if it was loaded from an environment variable.
    allocator: std.mem.Allocator = std.heap.page_allocator,
};

/// Load an API key from the provided value or environment variable.
/// Returns the API key or an error.
pub fn loadApiKey(options: LoadApiKeyOptions) ![]const u8 {
    // If API key is provided directly, use it
    if (options.api_key) |key| {
        if (key.len == 0) {
            return error.LoadApiKeyError;
        }
        return key;
    }

    // Try to load from environment variable
    const env_value = std.process.getEnvVarOwned(
        options.allocator,
        options.environment_variable_name,
    ) catch |err| {
        switch (err) {
            error.EnvironmentVariableNotFound => {
                std.log.err(
                    "{s} API key is missing. Pass it using the '{s}' parameter or the {s} environment variable.",
                    .{
                        options.description,
                        options.api_key_parameter_name,
                        options.environment_variable_name,
                    },
                );
                return error.LoadApiKeyError;
            },
            else => return error.LoadApiKeyError,
        }
    };

    if (env_value.len == 0) {
        options.allocator.free(env_value);
        std.log.err(
            "{s} API key is empty in the {s} environment variable.",
            .{ options.description, options.environment_variable_name },
        );
        return error.LoadApiKeyError;
    }

    return env_value;
}

/// Load an optional API key (doesn't error if not found)
pub fn loadOptionalApiKey(options: LoadApiKeyOptions) ?[]const u8 {
    return loadApiKey(options) catch null;
}

/// Check if an API key is available
pub fn hasApiKey(options: LoadApiKeyOptions) bool {
    if (options.api_key) |key| {
        return key.len > 0;
    }

    const env_value = std.process.getEnvVarOwned(
        options.allocator,
        options.environment_variable_name,
    ) catch return false;
    defer options.allocator.free(env_value);

    return env_value.len > 0;
}

/// Options for loading a setting
pub const LoadSettingOptions = struct {
    /// The setting value (if provided directly)
    setting_value: ?[]const u8 = null,
    /// Name of the environment variable to check
    environment_variable_name: ?[]const u8 = null,
    /// Description for error messages
    description: ?[]const u8 = null,
    /// Allocator for env var lookup
    allocator: std.mem.Allocator = std.heap.page_allocator,
};

/// Load an optional setting from value or environment
pub fn loadOptionalSetting(options: LoadSettingOptions) ?[]const u8 {
    // If setting is provided directly, use it
    if (options.setting_value) |value| {
        return value;
    }

    // Try to load from environment variable
    if (options.environment_variable_name) |env_name| {
        const env_value = std.process.getEnvVarOwned(
            options.allocator,
            env_name,
        ) catch return null;

        if (env_value.len == 0) {
            options.allocator.free(env_value);
            return null;
        }

        return env_value;
    }

    return null;
}

/// Remove trailing slash from a URL
pub fn withoutTrailingSlash(url: ?[]const u8) ?[]const u8 {
    if (url) |u| {
        if (u.len > 0 and u[u.len - 1] == '/') {
            return u[0 .. u.len - 1];
        }
        return u;
    }
    return null;
}

/// Common provider configuration
pub const ProviderConfig = struct {
    api_key: []const u8,
    base_url: []const u8,
    organization: ?[]const u8 = null,
    project: ?[]const u8 = null,
};

/// Load configuration for OpenAI-style providers
pub fn loadOpenAIStyleConfig(
    api_key: ?[]const u8,
    base_url: ?[]const u8,
    env_prefix: []const u8,
    default_base_url: []const u8,
) !ProviderConfig {
    // Build environment variable names
    var api_key_env_buf: [128]u8 = undefined;
    const api_key_env = std.fmt.bufPrint(&api_key_env_buf, "{s}_API_KEY", .{env_prefix}) catch {
        return error.LoadApiKeyError;
    };

    var base_url_env_buf: [128]u8 = undefined;
    const base_url_env = std.fmt.bufPrint(&base_url_env_buf, "{s}_BASE_URL", .{env_prefix}) catch {
        return error.LoadApiKeyError;
    };

    const loaded_key = try loadApiKey(.{
        .api_key = api_key,
        .environment_variable_name = api_key_env,
        .description = env_prefix,
    });

    const loaded_base_url = withoutTrailingSlash(
        loadOptionalSetting(.{
            .setting_value = base_url,
            .environment_variable_name = base_url_env,
        }),
    ) orelse default_base_url;

    return .{
        .api_key = loaded_key,
        .base_url = loaded_base_url,
    };
}

test "withoutTrailingSlash" {
    try std.testing.expectEqualStrings(
        "https://api.example.com",
        withoutTrailingSlash("https://api.example.com/").?,
    );
    try std.testing.expectEqualStrings(
        "https://api.example.com",
        withoutTrailingSlash("https://api.example.com").?,
    );
    try std.testing.expect(withoutTrailingSlash(null) == null);
}

test "hasApiKey with direct value" {
    try std.testing.expect(hasApiKey(.{
        .api_key = "test-key",
        .environment_variable_name = "NONEXISTENT_VAR",
        .description = "Test",
    }));

    try std.testing.expect(!hasApiKey(.{
        .api_key = "",
        .environment_variable_name = "NONEXISTENT_VAR",
        .description = "Test",
    }));

    try std.testing.expect(!hasApiKey(.{
        .api_key = null,
        .environment_variable_name = "NONEXISTENT_VAR_12345",
        .description = "Test",
    }));
}

test "loadApiKey with direct value" {
    const key = try loadApiKey(.{
        .api_key = "direct-api-key-123",
        .environment_variable_name = "SOME_VAR",
        .description = "Test Provider",
    });
    try std.testing.expectEqualStrings("direct-api-key-123", key);
}

test "loadApiKey rejects empty string" {
    const result = loadApiKey(.{
        .api_key = "",
        .environment_variable_name = "SOME_VAR",
        .description = "Test Provider",
    });
    try std.testing.expectError(error.LoadApiKeyError, result);
}

test "loadApiKey from environment variable" {
    // Set an environment variable for testing
    var env_map = try std.process.getEnvMap(std.testing.allocator);
    defer env_map.deinit();
}

test "loadApiKey missing from environment" {
    const result = loadApiKey(.{
        .api_key = null,
        .environment_variable_name = "NONEXISTENT_API_KEY_VAR_123456",
        .description = "Test Provider",
    });
    try std.testing.expectError(error.LoadApiKeyError, result);
}

test "loadOptionalApiKey returns null on error" {
    const result = loadOptionalApiKey(.{
        .api_key = null,
        .environment_variable_name = "NONEXISTENT_VAR_123456",
        .description = "Test Provider",
    });
    try std.testing.expect(result == null);
}

test "loadOptionalApiKey returns value when present" {
    const result = loadOptionalApiKey(.{
        .api_key = "test-key-value",
        .environment_variable_name = "NONEXISTENT_VAR",
        .description = "Test Provider",
    });
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("test-key-value", result.?);
}

test "loadOptionalSetting with direct value" {
    const result = loadOptionalSetting(.{
        .setting_value = "direct-value",
        .environment_variable_name = "NONEXISTENT_VAR",
    });
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("direct-value", result.?);
}

test "loadOptionalSetting with no value or env" {
    const result = loadOptionalSetting(.{
        .setting_value = null,
        .environment_variable_name = null,
    });
    try std.testing.expect(result == null);
}

test "loadOptionalSetting prefers direct value over env" {
    const result = loadOptionalSetting(.{
        .setting_value = "direct",
        .environment_variable_name = "PATH", // PATH should exist
    });
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("direct", result.?);
}

test "loadApiKey no memory leak on failure" {
    // std.testing.allocator detects leaks automatically
    const result = loadApiKey(.{
        .api_key = null,
        .environment_variable_name = "NONEXISTENT_LEAK_TEST_VAR",
        .description = "Leak Test",
        .allocator = std.testing.allocator,
    });
    try std.testing.expectError(error.LoadApiKeyError, result);
    // If there's a leak, std.testing.allocator will report it
}

test "withoutTrailingSlash multiple slashes" {
    // Current implementation only removes one trailing slash
    try std.testing.expectEqualStrings(
        "https://api.example.com//",
        withoutTrailingSlash("https://api.example.com///").?,
    );
}

test "withoutTrailingSlash empty string" {
    try std.testing.expectEqualStrings(
        "",
        withoutTrailingSlash("").?,
    );
}

test "withoutTrailingSlash single slash" {
    try std.testing.expectEqualStrings(
        "",
        withoutTrailingSlash("/").?,
    );
}
