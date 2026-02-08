const std = @import("std");
const image = @import("../../provider/src/image-model/v3/index.zig");
const shared = @import("../../provider/src/shared/v3/index.zig");
const provider_utils = @import("provider-utils");

const config_mod = @import("google-vertex-config.zig");
const options_mod = @import("google-vertex-options.zig");
const response_types = @import("google-vertex-response.zig");

/// Google Vertex AI Image Model
pub const GoogleVertexImageModel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    model_id: []const u8,
    config: config_mod.GoogleVertexConfig,

    /// Maximum images per API call
    pub const max_images_per_call: u32 = 4;

    /// Create a new Google Vertex AI image model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.GoogleVertexConfig,
    ) Self {
        return .{
            .allocator = allocator,
            .model_id = model_id,
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
        _ = self;
        callback(ctx, max_images_per_call);
    }

    /// Generate images
    pub fn doGenerate(
        self: *const Self,
        call_options: image.ImageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, image.ImageModelV3.GenerateResult) void,
        callback_context: ?*anyopaque,
    ) void {
        const provider_options: ?options_mod.GoogleVertexImageProviderOptions = null;
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        var warnings = std.ArrayList(shared.SharedV3Warning).init(request_allocator);

        // Check for size option (not supported)
        if (call_options.size != null) {
            warnings.append(.{
                .type = .unsupported,
                .message = "size option not supported, use aspectRatio instead",
            }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        // Check if this is an edit operation
        const is_edit_mode = call_options.files != null and call_options.files.?.len > 0;

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

        if (is_edit_mode) {
            // Build edit request with reference images
            var instances = std.json.Array.init(request_allocator);
            var instance = std.json.ObjectMap.init(request_allocator);

            instance.put("prompt", .{ .string = call_options.prompt }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };

            // Build reference images
            var reference_images = std.json.Array.init(request_allocator);
            if (call_options.files) |files| {
                for (files, 0..) |file, i| {
                    var ref = std.json.ObjectMap.init(request_allocator);
                    ref.put("referenceType", .{ .string = "REFERENCE_TYPE_RAW" }) catch |err| {
                        callback(callback_context, .{ .failure = err });
                        return;
                    };
                    ref.put("referenceId", .{ .integer = @intCast(i + 1) }) catch |err| {
                        callback(callback_context, .{ .failure = err });
                        return;
                    };

                    // Add reference image data
                    var ref_image = std.json.ObjectMap.init(request_allocator);
                    ref_image.put("bytesBase64Encoded", .{ .string = file.data }) catch |err| {
                        callback(callback_context, .{ .failure = err });
                        return;
                    };
                    ref.put("referenceImage", .{ .object = ref_image }) catch |err| {
                        callback(callback_context, .{ .failure = err });
                        return;
                    };

                    reference_images.append(.{ .object = ref }) catch |err| {
                        callback(callback_context, .{ .failure = err });
                        return;
                    };
                }
            }

            // Add mask if provided
            if (call_options.mask) |mask| {
                var ref = std.json.ObjectMap.init(request_allocator);
                ref.put("referenceType", .{ .string = "REFERENCE_TYPE_MASK" }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };

                const files_len = if (call_options.files) |f| f.len else 0;
                ref.put("referenceId", .{ .integer = @intCast(files_len + 1) }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };

                var ref_image = std.json.ObjectMap.init(request_allocator);
                ref_image.put("bytesBase64Encoded", .{ .string = mask.data }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
                ref.put("referenceImage", .{ .object = ref_image }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };

                // Add mask config
                var mask_config = std.json.ObjectMap.init(request_allocator);
                if (provider_options) |opts| {
                    if (opts.edit) |edit| {
                        if (edit.mask_mode) |mm| {
                            mask_config.put("maskMode", .{ .string = mm.toString() }) catch |err| {
                                callback(callback_context, .{ .failure = err });
                                return;
                            };
                        }
                        if (edit.mask_dilation) |md| {
                            mask_config.put("dilation", .{ .float = md }) catch |err| {
                                callback(callback_context, .{ .failure = err });
                                return;
                            };
                        }
                    }
                }
                if (mask_config.count() == 0) {
                    mask_config.put("maskMode", .{ .string = "MASK_MODE_USER_PROVIDED" }) catch |err| {
                        callback(callback_context, .{ .failure = err });
                        return;
                    };
                }
                ref.put("maskImageConfig", .{ .object = mask_config }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };

                reference_images.append(.{ .object = ref }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }

            instance.put("referenceImages", .{ .array = reference_images }) catch |err| {
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
        } else {
            // Standard generation request
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
        }

        // Build parameters
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

        if (call_options.seed) |seed| {
            parameters.put("seed", .{ .integer = @intCast(seed) }) catch |err| {
                callback(callback_context, .{ .failure = err });
                return;
            };
        }

        // Add provider options
        if (provider_options) |opts| {
            if (opts.negative_prompt) |np| {
                parameters.put("negativePrompt", .{ .string = np }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
            if (opts.person_generation) |pg| {
                parameters.put("personGeneration", .{ .string = pg.toString() }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
            if (opts.safety_setting) |ss| {
                parameters.put("safetySetting", .{ .string = ss.toString() }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
            if (opts.add_watermark) |aw| {
                parameters.put("addWatermark", .{ .bool = aw }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
            if (opts.storage_uri) |su| {
                parameters.put("storageUri", .{ .string = su }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
            if (opts.sample_image_size) |sis| {
                parameters.put("sampleImageSize", .{ .string = sis.toString() }) catch |err| {
                    callback(callback_context, .{ .failure = err });
                    return;
                };
            }
            if (is_edit_mode) {
                if (opts.edit) |edit| {
                    if (edit.mode) |mode| {
                        parameters.put("editMode", .{ .string = mode.toString() }) catch |err| {
                            callback(callback_context, .{ .failure = err });
                            return;
                        };
                    }
                    if (edit.base_steps) |bs| {
                        var edit_config = std.json.ObjectMap.init(request_allocator);
                        edit_config.put("baseSteps", .{ .integer = @intCast(bs) }) catch |err| {
                            callback(callback_context, .{ .failure = err });
                            return;
                        };
                        parameters.put("editConfig", .{ .object = edit_config }) catch |err| {
                            callback(callback_context, .{ .failure = err });
                            return;
                        };
                    }
                }
            }
        }

        body.put("parameters", .{ .object = parameters }) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };

        // Get headers
        var headers = std.StringHashMap([]const u8).init(request_allocator);
        if (self.config.headers_fn) |headers_fn| {
            headers = headers_fn(&self.config, request_allocator);
        }
        headers.put("Content-Type", "application/json") catch {};

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
            }) catch {};
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
        const parsed = response_types.VertexPredictImageResponse.fromJson(request_allocator, response_body) catch {
            callback(callback_context, .{ .failure = error.InvalidResponse });
            return;
        };
        const response = parsed.value;

        // Extract images from response
        var images_list = std.ArrayList([]const u8).init(result_allocator);
        if (response.predictions) |predictions| {
            for (predictions) |pred| {
                if (pred.bytesBase64Encoded) |b64| {
                    const b64_copy = result_allocator.dupe(u8, b64) catch continue;
                    images_list.append(b64_copy) catch {};
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

test "GoogleVertexImageModel init" {
    const allocator = std.testing.allocator;

    var model = GoogleVertexImageModel.init(
        allocator,
        "imagen-3.0-generate-001",
        .{ .base_url = "https://us-central1-aiplatform.googleapis.com" },
    );

    try std.testing.expectEqualStrings("imagen-3.0-generate-001", model.getModelId());
    try std.testing.expectEqual(@as(u32, 4), model.getMaxImagesPerCall());
}
