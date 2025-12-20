const std = @import("std");
const shared = @import("../../shared/v3/index.zig");

/// A source that has been used as input to generate the response.
pub const LanguageModelV3Source = struct {
    /// The type identifier (always "source")
    type: Type = .source,

    /// The source type - either URL or document
    source_type: SourceType,

    /// The ID of the source.
    id: []const u8,

    /// Source-specific data
    data: SourceData,

    /// Additional provider metadata for the source.
    provider_metadata: ?shared.SharedV3ProviderMetadata = null,

    pub const Type = enum {
        source,

        pub fn toString(self: Type) []const u8 {
            return switch (self) {
                .source => "source",
            };
        }
    };

    /// The type of source
    pub const SourceType = enum {
        /// URL sources reference web content.
        url,
        /// Document sources reference files/documents.
        document,

        pub fn toString(self: SourceType) []const u8 {
            return switch (self) {
                .url => "url",
                .document => "document",
            };
        }
    };

    /// Source-specific data union
    pub const SourceData = union(SourceType) {
        /// URL source data
        url: UrlSourceData,
        /// Document source data
        document: DocumentSourceData,
    };

    /// Data for URL sources
    pub const UrlSourceData = struct {
        /// The URL of the source.
        url: []const u8,
        /// The title of the source (optional).
        title: ?[]const u8 = null,
    };

    /// Data for document sources
    pub const DocumentSourceData = struct {
        /// IANA media type of the document (e.g., 'application/pdf').
        media_type: []const u8,
        /// The title of the document.
        title: []const u8,
        /// Optional filename of the document.
        filename: ?[]const u8 = null,
    };

    const Self = @This();

    /// Create a URL source
    pub fn initUrl(id: []const u8, url: []const u8, title: ?[]const u8) Self {
        return .{
            .source_type = .url,
            .id = id,
            .data = .{
                .url = .{
                    .url = url,
                    .title = title,
                },
            },
        };
    }

    /// Create a document source
    pub fn initDocument(
        id: []const u8,
        media_type: []const u8,
        title: []const u8,
        filename: ?[]const u8,
    ) Self {
        return .{
            .source_type = .document,
            .id = id,
            .data = .{
                .document = .{
                    .media_type = media_type,
                    .title = title,
                    .filename = filename,
                },
            },
        };
    }

    /// Clone the source
    pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
        const cloned_data: SourceData = switch (self.data) {
            .url => |u| .{
                .url = .{
                    .url = try allocator.dupe(u8, u.url),
                    .title = if (u.title) |t| try allocator.dupe(u8, t) else null,
                },
            },
            .document => |d| .{
                .document = .{
                    .media_type = try allocator.dupe(u8, d.media_type),
                    .title = try allocator.dupe(u8, d.title),
                    .filename = if (d.filename) |f| try allocator.dupe(u8, f) else null,
                },
            },
        };

        return .{
            .type = self.type,
            .source_type = self.source_type,
            .id = try allocator.dupe(u8, self.id),
            .data = cloned_data,
            .provider_metadata = if (self.provider_metadata) |pm| try pm.clone(allocator) else null,
        };
    }

    /// Free memory allocated for this source
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.id);

        switch (self.data) {
            .url => |u| {
                allocator.free(u.url);
                if (u.title) |t| allocator.free(t);
            },
            .document => |d| {
                allocator.free(d.media_type);
                allocator.free(d.title);
                if (d.filename) |f| allocator.free(f);
            },
        }

        if (self.provider_metadata) |*pm| {
            pm.deinit();
        }
    }
};

test "LanguageModelV3Source url" {
    const source = LanguageModelV3Source.initUrl("src-1", "https://example.com", "Example");
    try std.testing.expectEqualStrings("src-1", source.id);
    try std.testing.expectEqual(LanguageModelV3Source.SourceType.url, source.source_type);
    try std.testing.expectEqualStrings("https://example.com", source.data.url.url);
}

test "LanguageModelV3Source document" {
    const source = LanguageModelV3Source.initDocument("doc-1", "application/pdf", "My Document", "doc.pdf");
    try std.testing.expectEqualStrings("doc-1", source.id);
    try std.testing.expectEqual(LanguageModelV3Source.SourceType.document, source.source_type);
    try std.testing.expectEqualStrings("application/pdf", source.data.document.media_type);
}
