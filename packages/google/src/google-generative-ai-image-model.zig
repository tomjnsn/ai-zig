const std = @import("std");
const image = @import("provider").image_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");

const config_mod = @import("google-config.zig");
const options_mod = @import("google-generative-ai-options.zig");
const response_types = @import("google-generative-ai-response.zig");

/// Google Generative AI Image Model
pub const GoogleGenerativeAIImageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    settings: options_mod.GoogleGenerativeAIImageSettings,
    config: config_mod.GoogleGenerativeAIConfig,

    /// Default maximum images per call
    pub const default_max_images_per_call: u32 = 4;

    /// Create a new Google Generative AI image model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        settings: options_mod.GoogleGenerativeAIImageSettings,
        config: config_mod.GoogleGenerativeAIConfig,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
            .settings = settings,
            .config = config,
        };
    }

    /// Get the model ID
    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    /// Get the provider name
    pub fn getProvider(self: *const Self) []const u8 {
        return self.config.provider;
    }

    /// Get the maximum images per call
    pub fn getMaxImagesPerCall(
        self: *const Self,
        callback: *const fn (?*anyopaque, ?u32) void,
        ctx: ?*anyopaque,
    ) void {
        const max = self.settings.max_images_per_call orelse default_max_images_per_call;
        callback(ctx, max);
    }

    /// Generate images
    pub fn doGenerate(
        self: *const Self,
        call_options: image.ImageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, image.ImageModelV3.GenerateResult) void,
        callback_context: ?*anyopaque,
    ) void {
        const provider_options: ?options_mod.GoogleGenerativeAIImageProviderOptions = null;
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        var warnings = std.ArrayList(shared.SharedV3Warning).init(request_allocator);

        // Check for unsupported features
        if (call_options.files != null and call_options.files.?.len > 0) {
            callback(callback_context, .{ .failure = error.ImageEditingNotSupported });
            return;
        }

        if (call_options.mask != null) {
            callback(callback_context, .{ .failure = error.ImageEditingNotSupported });
            return;
        }

        if (call_options.size != null) {
            warnings.append(.{
                .type = .unsupported,
                .message = "size option not supported, use aspectRatio instead",
            }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        if (call_options.seed != null) {
            warnings.append(.{
                .type = .unsupported,
                .message = "seed option not supported through this provider",
            }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        // Build URL
        const url = std.fmt.allocPrint(
            request_allocator,
            "{s}/models/{s}:predict",
            .{ self.config.base_url, self.model_id },
        ) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Build request body
        var body = std.json.ObjectMap.init(request_allocator);

        // Instances
        var instances = std.json.Array.init(request_allocator);
        var instance = std.json.ObjectMap.init(request_allocator);
        instance.put("prompt", .{ .string = call_options.prompt }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };
        instances.append(.{ .object = instance }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };
        body.put("instances", .{ .array = instances }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Parameters
        var parameters = std.json.ObjectMap.init(request_allocator);
        parameters.put("sampleCount", .{ .integer = @intCast(call_options.n orelse 1) }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        if (call_options.aspect_ratio) |ar| {
            parameters.put("aspectRatio", .{ .string = ar }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        // Add provider options
        if (provider_options) |opts| {
            if (opts.person_generation) |pg| {
                parameters.put("personGeneration", .{ .string = pg.toString() }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
            if (opts.aspect_ratio) |ar| {
                parameters.put("aspectRatio", .{ .string = ar.toString() }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
        }

        body.put("parameters", .{ .object = parameters }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

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
        var body_buffer = std.ArrayList(u8).init(request_allocator);
        std.json.stringify(.{ .object = body }, .{}, body_buffer.writer()) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Get HTTP client
        const http_client = self.config.http_client orelse {
            callback(callback_context, .{ .failure = error.NoHttpClient });
            return;
        };

        // Convert headers to slice
        var header_list = std.ArrayList(provider_utils.HttpHeader).init(request_allocator);
        var header_iter = headers.iterator();
        while (header_iter.next()) |entry| {
            header_list.append(.{
                .name = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        // Create context for callback
        const ResponseContext = struct {
            response_body: ?[]const u8 = null,
            response_error: ?provider_utils.HttpError = null,
        };
        var response_ctx = ResponseContext{};

        // Make HTTP request
        http_client.request(
            .{
                .method = .POST,
                .url = url,
                .headers = header_list.items,
                .body = body_buffer.items,
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

        // Check for errors
        if (response_ctx.response_error != null) {
            callback(callback_context, .{ .failure = error.HttpRequestFailed });
            return;
        }

        const response_body = response_ctx.response_body orelse {
            callback(callback_context, .{ .failure = error.NoResponse });
            return;
        };

        // Parse response
        const parsed = response_types.GooglePredictResponse.fromJson(request_allocator, response_body) catch {
            callback(callback_context, .{ .failure = error.InvalidResponse });
            return;
        };
        const response = parsed.value;

        // Extract images from response
        var images_list = std.ArrayList([]const u8).init(result_allocator);
        if (response.predictions) |predictions| {
            for (predictions) |pred| {
                if (pred.bytesBase64Encoded) |b64| {
                    const b64_copy = result_allocator.dupe(u8, b64) catch |err| {
                        callback(callback_context, .{ .failure = err });
                        return;
                    };
                    images_list.append(b64_copy) catch |err| {
                        callback(callback_context, .{ .failure = err });
                        return;
                    };
                }
            }
        }

        const result = image.ImageModelV3.GenerateSuccess{
            .images = .{ .base64 = images_list.toOwnedSlice() catch &[_][]const u8{} },
            .warnings = warnings.toOwnedSlice() catch &[_]shared.SharedV3Warning{},
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

test "GoogleGenerativeAIImageModel init" {
    const allocator = std.testing.allocator;

    var model = GoogleGenerativeAIImageModel.init(
        allocator,
        "imagen-4.0-generate-001",
        .{},
        .{},
    );

    try std.testing.expectEqualStrings("imagen-4.0-generate-001", model.getModelId());
    try std.testing.expectEqualStrings("google.generative-ai", model.getProvider());
    try std.testing.expectEqual(@as(u32, 4), GoogleGenerativeAIImageModel.default_max_images_per_call);
}

test "GoogleGenerativeAIImageModel custom max images" {
    const allocator = std.testing.allocator;

    const model = GoogleGenerativeAIImageModel.init(
        allocator,
        "imagen-4.0-generate-001",
        .{ .max_images_per_call = 8 },
        .{},
    );

    try std.testing.expectEqual(@as(u32, 8), model.settings.max_images_per_call.?);
}
