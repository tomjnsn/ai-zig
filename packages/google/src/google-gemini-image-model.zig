const std = @import("std");
const image = @import("provider").image_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");

const config_mod = @import("google-config.zig");
const options_mod = @import("google-generative-ai-options.zig");
const response_types = @import("google-generative-ai-response.zig");

/// Google Gemini Image Model - uses generateContent endpoint with responseModalities: ["TEXT","IMAGE"].
/// For Gemini models that support native image generation (e.g. gemini-2.5-flash-image).
pub const GoogleGeminiImageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    settings: GeminiImageSettings,
    config: config_mod.GoogleGenerativeAIConfig,

    pub const default_max_images_per_call: u32 = 4;

    pub const GeminiImageSettings = struct {
        max_images_per_call: ?u32 = null,
        aspect_ratio: ?options_mod.ImageConfig.AspectRatio = null,
        image_size: ?options_mod.ImageConfig.ImageSize = null,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        settings: GeminiImageSettings,
        config: config_mod.GoogleGenerativeAIConfig,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .settings = settings,
            .config = config,
        };
    }

    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    pub fn getProvider(self: *const Self) []const u8 {
        return self.config.provider;
    }

    pub fn getMaxImagesPerCall(
        self: *const Self,
        callback: *const fn (?*anyopaque, ?u32) void,
        ctx: ?*anyopaque,
    ) void {
        const max = self.settings.max_images_per_call orelse default_max_images_per_call;
        callback(ctx, max);
    }

    pub fn doGenerate(
        self: *const Self,
        call_options: image.ImageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, image.ImageModelV3.GenerateResult) void,
        callback_context: ?*anyopaque,
    ) void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        var warnings = std.ArrayList(shared.SharedV3Warning).empty;

        // Build URL: {base_url}/models/{model_id}:generateContent
        const url = std.fmt.allocPrint(
            request_allocator,
            "{s}/models/{s}:generateContent",
            .{ self.config.base_url, self.model_id },
        ) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Build request body
        var body = std.json.ObjectMap.init(request_allocator);

        // Contents: [{ parts: [{ text: prompt }] }]
        const prompt_text = call_options.prompt orelse {
            callback(callback_context, .{ .failure = error.PromptRequired });
            return;
        };
        var parts = std.json.Array.init(request_allocator);
        var text_part = std.json.ObjectMap.init(request_allocator);
        text_part.put("text", .{ .string = prompt_text }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };
        parts.append(.{ .object = text_part }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        var content = std.json.ObjectMap.init(request_allocator);
        content.put("parts", .{ .array = parts }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        var contents = std.json.Array.init(request_allocator);
        contents.append(.{ .object = content }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };
        body.put("contents", .{ .array = contents }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // GenerationConfig: { responseModalities: ["TEXT", "IMAGE"], imageConfig: { ... } }
        var gen_config = std.json.ObjectMap.init(request_allocator);

        var modalities = std.json.Array.init(request_allocator);
        modalities.append(.{ .string = "TEXT" }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };
        modalities.append(.{ .string = "IMAGE" }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };
        gen_config.put("responseModalities", .{ .array = modalities }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Add imageConfig if settings specify aspect ratio or size
        if (self.settings.aspect_ratio != null or self.settings.image_size != null) {
            var image_config = std.json.ObjectMap.init(request_allocator);
            if (self.settings.aspect_ratio) |ar| {
                image_config.put("aspectRatio", .{ .string = ar.toString() }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
            if (self.settings.image_size) |sz| {
                image_config.put("imageSize", .{ .string = sz.toString() }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
            gen_config.put("imageConfig", .{ .object = image_config }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        body.put("generationConfig", .{ .object = gen_config }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Warn about unsupported options
        if (call_options.size != null) {
            warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature(
                "size",
                "use aspectRatio in settings instead",
            )) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        if (call_options.seed != null) {
            warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature(
                "seed",
                "not supported through this provider",
            )) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        // Get headers
        var headers = if (self.config.headers_fn) |headers_fn|
            headers_fn(&self.config, request_allocator) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            }
        else
            std.StringHashMap([]const u8).init(request_allocator);

        headers.put("Content-Type", "application/json") catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Serialize request body
        const body_bytes = std.json.Stringify.valueAlloc(request_allocator, std.json.Value{ .object = body }, .{}) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Get HTTP client
        const http_client = self.config.http_client orelse {
            callback(callback_context, .{ .failure = error.NoHttpClient });
            return;
        };

        // Convert headers to slice
        var header_list = std.ArrayList(provider_utils.HttpHeader).empty;
        var header_iter = headers.iterator();
        while (header_iter.next()) |entry| {
            header_list.append(request_allocator, .{
                .name = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        // HTTP response context
        const ResponseContext = struct {
            response_body: ?[]const u8 = null,
            response_error: ?provider_utils.HttpError = null,
        };
        var response_ctx = ResponseContext{};

        http_client.request(
            .{
                .method = .POST,
                .url = url,
                .headers = header_list.items,
                .body = body_bytes,
            },
            request_allocator,
            struct {
                fn onResponse(ctx: ?*anyopaque, response: provider_utils.HttpResponse) void {
                    const rctx: *ResponseContext = @ptrCast(@alignCast(ctx.?));
                    rctx.response_body = response.body;
                }
            }.onResponse,
            struct {
                fn onError(ctx: ?*anyopaque, err: provider_utils.HttpError) void {
                    const rctx: *ResponseContext = @ptrCast(@alignCast(ctx.?));
                    rctx.response_error = err;
                }
            }.onError,
            &response_ctx,
        );

        // Handle errors
        if (response_ctx.response_error) |http_err| {
            if (call_options.error_diagnostic) |diag| {
                diag.provider = self.config.provider;
                diag.kind = .network;
                diag.setMessage(http_err.message);
                if (http_err.status_code) |code| {
                    diag.status_code = code;
                    diag.classifyStatus();
                }
            }
            callback(callback_context, .{ .failure = error.HttpRequestFailed });
            return;
        }

        const response_body = response_ctx.response_body orelse {
            callback(callback_context, .{ .failure = error.NoResponse });
            return;
        };

        // Parse generateContent response
        const parsed = response_types.GoogleGenerateContentResponse.fromJson(request_allocator, response_body) catch {
            callback(callback_context, .{ .failure = error.InvalidResponse });
            return;
        };
        const response = parsed.value;

        // Extract images from response parts where inlineData.mimeType starts with "image/"
        var images_list = std.ArrayList([]const u8).empty;
        if (response.candidates) |candidates| {
            for (candidates) |candidate| {
                if (candidate.content) |cand_content| {
                    if (cand_content.parts) |resp_parts| {
                        for (resp_parts) |part| {
                            if (part.inlineData) |inline_data| {
                                if (inline_data.mimeType) |mime| {
                                    if (std.mem.startsWith(u8, mime, "image/")) {
                                        if (inline_data.data) |b64| {
                                            const b64_copy = result_allocator.dupe(u8, b64) catch |err| {
                                                callback(callback_context, .{ .failure = err });
                                                return;
                                            };
                                            images_list.append(result_allocator, b64_copy) catch |err| {
                                                callback(callback_context, .{ .failure = err });
                                                return;
                                            };
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        const result = image.ImageModelV3.GenerateSuccess{
            .images = .{ .base64 = images_list.toOwnedSlice(result_allocator) catch &[_][]const u8{} },
            .warnings = warnings.toOwnedSlice(request_allocator) catch &[_]shared.SharedV3Warning{},
            .response = .{
                .timestamp = std.time.milliTimestamp(),
                .model_id = self.model_id,
            },
        };

        callback(callback_context, .{ .success = result });
    }

    /// Convert to ImageModelV3 interface
    pub fn asImageModel(self: *Self) image.ImageModelV3 {
        return image.asImageModel(Self, self);
    }
};

/// Check if a model ID is a Gemini image model (uses generateContent, not predict)
pub fn isGeminiImageModel(model_id: []const u8) bool {
    return std.mem.startsWith(u8, model_id, "gemini-") and
        std.mem.indexOf(u8, model_id, "image") != null;
}

test "GoogleGeminiImageModel init" {
    const allocator = std.testing.allocator;

    var model = GoogleGeminiImageModel.init(
        allocator,
        "gemini-2.5-flash-image",
        .{},
        .{},
    );

    try std.testing.expectEqualStrings("gemini-2.5-flash-image", model.getModelId());
    try std.testing.expectEqualStrings("google.generative-ai", model.getProvider());
    try std.testing.expectEqual(@as(u32, 4), GoogleGeminiImageModel.default_max_images_per_call);
}

test "GoogleGeminiImageModel custom settings" {
    const allocator = std.testing.allocator;

    const model = GoogleGeminiImageModel.init(
        allocator,
        "gemini-3-pro-image-preview",
        .{
            .max_images_per_call = 2,
            .aspect_ratio = .@"16:9",
        },
        .{},
    );

    try std.testing.expectEqualStrings("gemini-3-pro-image-preview", model.getModelId());
    try std.testing.expectEqual(@as(u32, 2), model.settings.max_images_per_call.?);
}

test "isGeminiImageModel" {
    try std.testing.expect(isGeminiImageModel("gemini-2.5-flash-image"));
    try std.testing.expect(isGeminiImageModel("gemini-3-pro-image-preview"));
    try std.testing.expect(!isGeminiImageModel("imagen-4.0-generate-001"));
    try std.testing.expect(!isGeminiImageModel("gemini-2.0-flash"));
}

test "GoogleGeminiImageModel doGenerate with no http client" {
    const allocator = std.testing.allocator;

    var model = GoogleGeminiImageModel.init(
        allocator,
        "gemini-2.5-flash-image",
        .{},
        .{ .http_client = null },
    );

    const State = struct {
        var got_error: bool = false;
        fn onResult(_: ?*anyopaque, result: image.ImageModelV3.GenerateResult) void {
            switch (result) {
                .failure => {
                    got_error = true;
                },
                .success => {},
            }
        }
    };

    State.got_error = false;
    model.doGenerate(
        .{ .prompt = "Draw a cat" },
        allocator,
        State.onResult,
        null,
    );

    try std.testing.expect(State.got_error);
}
