const std = @import("std");
const safe_cast = @import("safe-cast.zig");

/// Default alphabet for ID generation
pub const default_alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

/// Default separator for prefixed IDs
pub const default_separator = "-";

/// Default size for random part
pub const default_size = 16;

/// Configuration for ID generation
pub const IdGeneratorConfig = struct {
    /// Prefix to prepend to the ID
    prefix: ?[]const u8 = null,
    /// Separator between prefix and random part
    separator: []const u8 = default_separator,
    /// Size of the random part
    size: usize = default_size,
    /// Alphabet to use for random characters
    alphabet: []const u8 = default_alphabet,
};

/// ID Generator that produces random string IDs
pub const IdGenerator = struct {
    config: IdGeneratorConfig,
    prng: std.Random.DefaultPrng,

    const Self = @This();

    /// Create a new ID generator with the given configuration
    pub fn init(config: IdGeneratorConfig) Self {
        // Get a random seed
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch {
            // Fallback to timestamp-based seed
            seed = safe_cast.safeCast(u64, std.time.milliTimestamp()) catch 0;
        };

        return .{
            .config = config,
            .prng = std.Random.DefaultPrng.init(seed),
        };
    }

    /// Generate a new ID
    pub fn generate(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const random_part = try self.generateRandomPart(allocator);

        if (self.config.prefix) |prefix| {
            // Allocate space for prefix + separator + random part
            const total_len = prefix.len + self.config.separator.len + random_part.len;
            var result = try allocator.alloc(u8, total_len);

            // Copy prefix
            @memcpy(result[0..prefix.len], prefix);
            // Copy separator
            @memcpy(result[prefix.len .. prefix.len + self.config.separator.len], self.config.separator);
            // Copy random part
            @memcpy(result[prefix.len + self.config.separator.len ..], random_part);

            allocator.free(random_part);
            return result;
        }

        return random_part;
    }

    fn generateRandomPart(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const result = try allocator.alloc(u8, self.config.size);
        const alphabet_len = self.config.alphabet.len;

        for (result) |*char| {
            const idx = self.prng.random().uintLessThan(usize, alphabet_len);
            char.* = self.config.alphabet[idx];
        }

        return result;
    }
};

/// Create an ID generator with default settings
pub fn createIdGenerator() IdGenerator {
    return IdGenerator.init(.{});
}

/// Create an ID generator with a prefix
pub fn createPrefixedIdGenerator(prefix: []const u8) IdGenerator {
    return IdGenerator.init(.{ .prefix = prefix });
}

/// Create an ID generator with custom configuration
pub fn createCustomIdGenerator(config: IdGeneratorConfig) IdGenerator {
    return IdGenerator.init(config);
}

/// Generate a single ID with default settings
pub fn generateId(allocator: std.mem.Allocator) ![]u8 {
    var generator = createIdGenerator();
    return generator.generate(allocator);
}

/// Generate a prefixed ID
pub fn generatePrefixedId(
    allocator: std.mem.Allocator,
    prefix: []const u8,
) ![]u8 {
    var generator = createPrefixedIdGenerator(prefix);
    return generator.generate(allocator);
}

/// Generate a UUID-like ID (not a real UUID, but similar format)
pub fn generateUuidLike(allocator: std.mem.Allocator) ![]u8 {
    var generator = IdGenerator.init(.{
        .size = 32,
        .alphabet = "0123456789abcdef",
    });

    const hex = try generator.generate(allocator);
    defer allocator.free(hex);

    // Format as UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    var result = try allocator.alloc(u8, 36);
    @memcpy(result[0..8], hex[0..8]);
    result[8] = '-';
    @memcpy(result[9..13], hex[8..12]);
    result[13] = '-';
    @memcpy(result[14..18], hex[12..16]);
    result[18] = '-';
    @memcpy(result[19..23], hex[16..20]);
    result[23] = '-';
    @memcpy(result[24..36], hex[20..32]);

    return result;
}

/// Validate that an ID has a specific prefix
pub fn hasPrefix(id: []const u8, prefix: []const u8, separator: []const u8) bool {
    if (id.len < prefix.len + separator.len) return false;

    if (!std.mem.startsWith(u8, id, prefix)) return false;

    return std.mem.startsWith(u8, id[prefix.len..], separator);
}

test "IdGenerator basic" {
    const allocator = std.testing.allocator;

    var generator = createIdGenerator();
    const id = try generator.generate(allocator);
    defer allocator.free(id);

    try std.testing.expectEqual(@as(usize, 16), id.len);

    // Verify all characters are from the alphabet
    for (id) |char| {
        try std.testing.expect(std.mem.indexOfScalar(u8, default_alphabet, char) != null);
    }
}

test "IdGenerator with prefix" {
    const allocator = std.testing.allocator;

    var generator = createPrefixedIdGenerator("msg");
    const id = try generator.generate(allocator);
    defer allocator.free(id);

    try std.testing.expect(std.mem.startsWith(u8, id, "msg-"));
    try std.testing.expectEqual(@as(usize, 3 + 1 + 16), id.len);
}

test "IdGenerator uniqueness" {
    const allocator = std.testing.allocator;

    var generator = createIdGenerator();

    var ids = std.ArrayList([]u8).empty;
    defer {
        for (ids.items) |id| allocator.free(id);
        ids.deinit(allocator);
    }

    // Generate multiple IDs and verify they're unique
    for (0..100) |_| {
        const id = try generator.generate(allocator);
        try ids.append(allocator, id);
    }

    // Check uniqueness
    for (ids.items, 0..) |id1, i| {
        for (ids.items[i + 1 ..]) |id2| {
            try std.testing.expect(!std.mem.eql(u8, id1, id2));
        }
    }
}

test "hasPrefix" {
    try std.testing.expect(hasPrefix("msg-abc123", "msg", "-"));
    try std.testing.expect(!hasPrefix("msg-abc123", "chat", "-"));
    try std.testing.expect(!hasPrefix("msgabc123", "msg", "-"));
}

test "generateUuidLike format" {
    const allocator = std.testing.allocator;

    const uuid = try generateUuidLike(allocator);
    defer allocator.free(uuid);

    try std.testing.expectEqual(@as(usize, 36), uuid.len);
    try std.testing.expectEqual(@as(u8, '-'), uuid[8]);
    try std.testing.expectEqual(@as(u8, '-'), uuid[13]);
    try std.testing.expectEqual(@as(u8, '-'), uuid[18]);
    try std.testing.expectEqual(@as(u8, '-'), uuid[23]);
}

test "IdGenerator custom alphabet" {
    const allocator = std.testing.allocator;

    var generator = IdGenerator.init(.{
        .alphabet = "ABC",
        .size = 10,
    });

    const id = try generator.generate(allocator);
    defer allocator.free(id);

    try std.testing.expectEqual(@as(usize, 10), id.len);

    // Verify all characters are from custom alphabet
    for (id) |char| {
        try std.testing.expect(char == 'A' or char == 'B' or char == 'C');
    }
}

test "IdGenerator custom size" {
    const allocator = std.testing.allocator;

    var generator = IdGenerator.init(.{ .size = 32 });
    const id = try generator.generate(allocator);
    defer allocator.free(id);

    try std.testing.expectEqual(@as(usize, 32), id.len);
}

test "IdGenerator custom separator" {
    const allocator = std.testing.allocator;

    var generator = IdGenerator.init(.{
        .prefix = "user",
        .separator = "_",
        .size = 8,
    });

    const id = try generator.generate(allocator);
    defer allocator.free(id);

    try std.testing.expect(std.mem.startsWith(u8, id, "user_"));
    try std.testing.expectEqual(@as(usize, 4 + 1 + 8), id.len);
}

test "generateId simple" {
    const allocator = std.testing.allocator;

    const id = try generateId(allocator);
    defer allocator.free(id);

    try std.testing.expectEqual(@as(usize, 16), id.len);
}

test "generatePrefixedId simple" {
    const allocator = std.testing.allocator;

    const id = try generatePrefixedId(allocator, "test");
    defer allocator.free(id);

    try std.testing.expect(std.mem.startsWith(u8, id, "test-"));
}

test "hasPrefix with different separators" {
    try std.testing.expect(hasPrefix("user_123abc", "user", "_"));
    try std.testing.expect(!hasPrefix("user_123abc", "user", "-"));
    try std.testing.expect(!hasPrefix("user123abc", "user", "_"));
}

test "hasPrefix edge cases" {
    try std.testing.expect(!hasPrefix("", "prefix", "-"));
    try std.testing.expect(!hasPrefix("p", "prefix", "-"));
    try std.testing.expect(!hasPrefix("prefix", "prefix", "-"));
    try std.testing.expect(hasPrefix("prefix-", "prefix", "-"));
}

test "generateUuidLike uniqueness" {
    const allocator = std.testing.allocator;

    const uuid1 = try generateUuidLike(allocator);
    defer allocator.free(uuid1);

    const uuid2 = try generateUuidLike(allocator);
    defer allocator.free(uuid2);

    // Should be different
    try std.testing.expect(!std.mem.eql(u8, uuid1, uuid2));
}

test "generateUuidLike contains only hex" {
    const allocator = std.testing.allocator;

    const uuid = try generateUuidLike(allocator);
    defer allocator.free(uuid);

    for (uuid) |char| {
        if (char != '-') {
            try std.testing.expect((char >= '0' and char <= '9') or (char >= 'a' and char <= 'f'));
        }
    }
}

test "createCustomIdGenerator" {
    const allocator = std.testing.allocator;

    var generator = createCustomIdGenerator(.{
        .prefix = "custom",
        .separator = ":",
        .size = 12,
        .alphabet = "0123456789",
    });

    const id = try generator.generate(allocator);
    defer allocator.free(id);

    try std.testing.expect(std.mem.startsWith(u8, id, "custom:"));
    try std.testing.expectEqual(@as(usize, 6 + 1 + 12), id.len);

    // Check that only digits are used
    const random_part = id[7..];
    for (random_part) |char| {
        try std.testing.expect(char >= '0' and char <= '9');
    }
}
