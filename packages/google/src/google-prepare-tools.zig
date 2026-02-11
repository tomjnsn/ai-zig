const std = @import("std");
const lm = @import("provider").language_model;
const shared = @import("provider").shared;
const json_value = @import("provider").json_value;
const options = @import("google-generative-ai-options.zig");

/// Tool configuration for Google API
pub const ToolConfig = struct {
    function_calling_config: ?FunctionCallingConfig = null,
    retrieval_config: ?options.RetrievalConfig = null,

    pub const FunctionCallingConfig = struct {
        mode: Mode,
        allowed_function_names: ?[]const []const u8 = null,

        pub const Mode = enum {
            auto,
            none,
            any,

            pub fn toString(self: Mode) []const u8 {
                return switch (self) {
                    .auto => "AUTO",
                    .none => "NONE",
                    .any => "ANY",
                };
            }
        };
    };
};

/// Function declaration for Google API
pub const FunctionDeclaration = struct {
    name: []const u8,
    description: []const u8,
    parameters: json_value.JsonValue,
};

/// Provider tool types
pub const ProviderTool = union(enum) {
    google_search: GoogleSearch,
    google_search_retrieval: GoogleSearchRetrieval,
    enterprise_web_search: EnterpriseWebSearch,
    url_context: UrlContext,
    code_execution: CodeExecution,
    file_search: FileSearch,
    vertex_rag_store: VertexRagStore,
    google_maps: GoogleMaps,

    pub const GoogleSearch = struct {};

    pub const GoogleSearchRetrieval = struct {
        dynamic_retrieval_config: ?DynamicRetrievalConfig = null,

        pub const DynamicRetrievalConfig = struct {
            mode: ?[]const u8 = null,
            dynamic_threshold: ?f64 = null,
        };
    };

    pub const EnterpriseWebSearch = struct {};

    pub const UrlContext = struct {};

    pub const CodeExecution = struct {};

    pub const FileSearch = struct {
        // File search args would go here
    };

    pub const VertexRagStore = struct {
        rag_corpus: []const u8,
        top_k: ?u32 = null,
    };

    pub const GoogleMaps = struct {};
};

/// Result of preparing tools
pub const PrepareToolsResult = struct {
    /// Function declarations for the API
    function_declarations: ?[]FunctionDeclaration = null,

    /// Provider tools
    provider_tools: ?[]ProviderTool = null,

    /// Tool configuration
    tool_config: ?ToolConfig = null,

    /// Warnings generated during preparation
    tool_warnings: []shared.SharedV3Warning = &[_]shared.SharedV3Warning{},
};

/// Prepare tools for Google Generative AI API
pub fn prepareTools(
    allocator: std.mem.Allocator,
    tools: ?[]const lm.LanguageModelV3CallOptions.Tool,
    tool_choice: ?lm.LanguageModelV3ToolChoice,
    model_id: []const u8,
) !PrepareToolsResult {
    var warnings = std.ArrayList(shared.SharedV3Warning).empty;

    // Check for empty tools array
    if (tools == null or tools.?.len == 0) {
        return .{
            .function_declarations = null,
            .provider_tools = null,
            .tool_config = null,
            .tool_warnings = &[_]shared.SharedV3Warning{},
        };
    }

    const tools_list = tools.?;
    const is_gemini_2_or_newer = options.isGemini2OrNewer(model_id);
    const supports_dynamic_retrieval = options.supportsDynamicRetrieval(model_id);
    const supports_file_search = options.supportsFileSearch(model_id);

    // Check for mixed tool types
    var has_function_tools = false;
    var has_provider_tools = false;
    for (tools_list) |tool| {
        switch (tool) {
            .function => has_function_tools = true,
            .provider => has_provider_tools = true,
        }
    }

    if (has_function_tools and has_provider_tools) {
        try warnings.append(allocator, .{
            .unsupported = .{
                .feature = "combination of function and provider-defined tools",
            },
        });
    }

    // Handle provider tools
    if (has_provider_tools) {
        var provider_tools = std.ArrayList(ProviderTool).empty;

        for (tools_list) |tool| {
            switch (tool) {
                .provider => |prov| {
                    if (std.mem.eql(u8, prov.name, "google.google_search")) {
                        if (is_gemini_2_or_newer) {
                            try provider_tools.append(allocator, .{ .google_search = .{} });
                        } else if (supports_dynamic_retrieval) {
                            try provider_tools.append(allocator, .{
                                .google_search_retrieval = .{
                                    .dynamic_retrieval_config = .{},
                                },
                            });
                        } else {
                            try provider_tools.append(allocator, .{
                                .google_search_retrieval = .{},
                            });
                        }
                    } else if (std.mem.eql(u8, prov.name, "google.enterprise_web_search")) {
                        if (is_gemini_2_or_newer) {
                            try provider_tools.append(allocator, .{ .enterprise_web_search = .{} });
                        } else {
                            try warnings.append(allocator, .{
                                .unsupported = .{
                                    .feature = "provider-defined tool google.enterprise_web_search requires Gemini 2.0 or newer",
                                },
                            });
                        }
                    } else if (std.mem.eql(u8, prov.name, "google.url_context")) {
                        if (is_gemini_2_or_newer) {
                            try provider_tools.append(allocator, .{ .url_context = .{} });
                        } else {
                            try warnings.append(allocator, .{
                                .unsupported = .{
                                    .feature = "provider-defined tool google.url_context requires Gemini 2.0 or newer",
                                },
                            });
                        }
                    } else if (std.mem.eql(u8, prov.name, "google.code_execution")) {
                        if (is_gemini_2_or_newer) {
                            try provider_tools.append(allocator, .{ .code_execution = .{} });
                        } else {
                            try warnings.append(allocator, .{
                                .unsupported = .{
                                    .feature = "provider-defined tool google.code_execution requires Gemini 2.0 or newer",
                                },
                            });
                        }
                    } else if (std.mem.eql(u8, prov.name, "google.file_search")) {
                        if (supports_file_search) {
                            try provider_tools.append(allocator, .{ .file_search = .{} });
                        } else {
                            try warnings.append(allocator, .{
                                .unsupported = .{
                                    .feature = "provider-defined tool google.file_search requires Gemini 2.5 models",
                                },
                            });
                        }
                    } else if (std.mem.eql(u8, prov.name, "google.google_maps")) {
                        if (is_gemini_2_or_newer) {
                            try provider_tools.append(allocator, .{ .google_maps = .{} });
                        } else {
                            try warnings.append(allocator, .{
                                .unsupported = .{
                                    .feature = "provider-defined tool google.google_maps requires Gemini 2.0 or newer",
                                },
                            });
                        }
                    } else {
                        try warnings.append(allocator, .{
                            .unsupported = .{
                                .feature = try std.fmt.allocPrint(
                                    allocator,
                                    "provider-defined tool {s}",
                                    .{prov.name},
                                ),
                                .details = "not supported",
                            },
                        });
                    }
                },
                else => {},
            }
        }

        return .{
            .function_declarations = null,
            .provider_tools = if (provider_tools.items.len > 0)
                try provider_tools.toOwnedSlice(allocator)
            else
                null,
            .tool_config = null,
            .tool_warnings = try warnings.toOwnedSlice(allocator),
        };
    }

    // Handle function tools
    var function_declarations = std.ArrayList(FunctionDeclaration).empty;

    for (tools_list) |tool| {
        switch (tool) {
            .function => |func| {
                try function_declarations.append(allocator, .{
                    .name = func.name,
                    .description = func.description orelse "",
                    .parameters = func.input_schema,
                });
            },
            .provider => {
                try warnings.append(allocator, .{
                    .unsupported = .{
                        .feature = "provider tool in function tools context",
                    },
                });
            },
        }
    }

    // Handle tool choice
    var tool_config: ?ToolConfig = null;
    if (tool_choice) |choice| {
        tool_config = switch (choice) {
            .auto => .{
                .function_calling_config = .{ .mode = .auto },
            },
            .none => .{
                .function_calling_config = .{ .mode = .none },
            },
            .required => .{
                .function_calling_config = .{ .mode = .any },
            },
            .tool => |t| .{
                .function_calling_config = .{
                    .mode = .any,
                    .allowed_function_names = &[_][]const u8{t.tool_name},
                },
            },
        };
    }

    return .{
        .function_declarations = if (function_declarations.items.len > 0)
            try function_declarations.toOwnedSlice(allocator)
        else
            null,
        .provider_tools = null,
        .tool_config = tool_config,
        .tool_warnings = try warnings.toOwnedSlice(allocator),
    };
}

/// Free the prepared tools result
pub fn freePrepareToolsResult(allocator: std.mem.Allocator, result: *PrepareToolsResult) void {
    if (result.function_declarations) |decls| {
        allocator.free(decls);
    }
    if (result.provider_tools) |tools| {
        allocator.free(tools);
    }
    allocator.free(result.tool_warnings);
}

test "prepareTools with no tools" {
    const allocator = std.testing.allocator;

    var result = try prepareTools(allocator, null, null, "gemini-2.0-flash");
    defer freePrepareToolsResult(allocator, &result);

    try std.testing.expect(result.function_declarations == null);
    try std.testing.expect(result.provider_tools == null);
    try std.testing.expect(result.tool_config == null);
}

test "prepareTools with function tool" {
    const allocator = std.testing.allocator;
    const jv = @import("provider").json_value;

    const schema = jv.JsonValue{ .object = jv.JsonObject.init(allocator) };

    const tools = [_]lm.LanguageModelV3CallOptions.Tool{
        .{
            .function = .{
                .name = "search",
                .description = "Search the web",
                .input_schema = schema,
            },
        },
    };

    var result = try prepareTools(allocator, &tools, .auto, "gemini-2.0-flash");
    defer freePrepareToolsResult(allocator, &result);

    try std.testing.expect(result.function_declarations != null);
    try std.testing.expectEqual(@as(usize, 1), result.function_declarations.?.len);
    try std.testing.expectEqualStrings("search", result.function_declarations.?[0].name);
}
