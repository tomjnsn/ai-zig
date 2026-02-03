const std = @import("std");
const image = @import("../../provider/src/image-model/v3/index.zig");
const shared = @import("../../provider/src/shared/v3/index.zig");

const config_mod = @import("google-vertex-config.zig");
const options_mod = @import("google-vertex-options.zig");

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

        _ = url;
        _ = headers;

        // For now, return placeholder result
        const n = call_options.n orelse 1;
        var images = result_allocator.alloc([]const u8, n) catch |err| {
            callback(callback_context, .{ .failure = err });
            return;
        };
        for (images, 0..) |*img, i| {
            _ = i;
            img.* = ""; // Placeholder base64 data
        }

        const result = image.ImageModelV3.GenerateSuccess{
            .images = .{ .base64 = images },
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
