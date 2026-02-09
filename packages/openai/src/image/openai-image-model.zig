const std = @import("std");
const im = @import("provider").image_model;
const shared = @import("provider").shared;
const provider_utils = @import("provider-utils");

const api = @import("openai-image-api.zig");
const options_mod = @import("openai-image-options.zig");
const config_mod = @import("../openai-config.zig");
const error_mod = @import("../openai-error.zig");

/// OpenAI Image Model implementation
pub const OpenAIImageModel = struct {
    const Self = @This();

    /// Model ID
    model_id: []const u8,

    /// Configuration
    config: config_mod.OpenAIConfig,

    /// Allocator for internal operations
    allocator: std.mem.Allocator,

    pub const specification_version = "v3";

    /// Initialize a new OpenAI image model
    pub fn init(
        allocator: std.mem.Allocator,
        model_id: []const u8,
        config: config_mod.OpenAIConfig,
    ) Self {
        return .{
            .model_id = model_id,
            .config = config,
            .allocator = allocator,
        };
    }

    /// Get the provider name
    pub fn getProvider(self: *const Self) []const u8 {
        return self.config.provider;
    }

    /// Get the model ID
    pub fn getModelId(self: *const Self) []const u8 {
        return self.model_id;
    }

    /// Get max images per call (async callback-based)
    pub fn getMaxImagesPerCall(
        self: *const Self,
        callback: *const fn (?*anyopaque, ?u32) void,
        context: ?*anyopaque,
    ) void {
        const max_images = options_mod.modelMaxImagesPerCall(self.model_id);
        callback(context, provider_utils.safeCast(u32, max_images) catch null);
    }

    /// Generate images
    pub fn doGenerate(
        self: *const Self,
        call_options: im.ImageModelV3CallOptions,
        result_allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, im.ImageModelV3.GenerateResult) void,
        context: ?*anyopaque,
    ) void {
        // Use arena for request processing
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const request_allocator = arena.allocator();

        const result = self.doGenerateInternal(request_allocator, result_allocator, call_options) catch |err| {
            callback(context, .{ .failure = err });
            return;
        };

        callback(context, .{ .success = result });
    }

    fn doGenerateInternal(
        self: *const Self,
        request_allocator: std.mem.Allocator,
        result_allocator: std.mem.Allocator,
        call_options: im.ImageModelV3CallOptions,
    ) !im.ImageModelV3.GenerateSuccess {
        const timestamp = std.time.milliTimestamp();
        var warnings: std.ArrayList(shared.SharedV3Warning) = .empty;

        // Check for unsupported features
        if (call_options.aspect_ratio != null) {
            try warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature("aspectRatio", "This model does not support aspect ratio. Use `size` instead."));
        }

        if (call_options.seed != null) {
            try warnings.append(request_allocator, shared.SharedV3Warning.unsupportedFeature("seed", null));
        }

        // Build request
        var request = api.OpenAIImageGenerationRequest{
            .model = self.model_id,
            .prompt = call_options.prompt orelse return error.MissingPrompt,
            .n = call_options.n,
            .size = if (call_options.size) |s| try s.format(request_allocator) else null,
            .quality = null,
            .style = null,
            .user = null,
            .background = null,
            .output_format = null,
            .output_compression = null,
        };

        // Set response format for models that need it
        if (!options_mod.hasDefaultResponseFormat(self.model_id)) {
            request.response_format = "b64_json";
        }

        // Build URL
        const url = try self.config.buildUrl(request_allocator, "/images/generations", self.model_id);

        // Get headers
        var headers = try self.config.getHeaders(request_allocator);
        if (call_options.headers) |user_headers| {
            var iter = user_headers.iterator();
            while (iter.next()) |entry| {
                try headers.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Make HTTP request
        const http_client = self.config.http_client orelse return error.NoHttpClient;

        // Serialize request body
        const body = try serializeRequest(request_allocator, request);

        // Make the request
        var response_data: ?[]const u8 = null;
        var response_headers: ?std.StringHashMap([]const u8) = null;

        try http_client.post(url, headers, body, request_allocator, struct {
            fn onResponse(ctx: *anyopaque, resp_headers: std.StringHashMap([]const u8), resp_body: []const u8) void {
                const data = @as(*struct { body: *?[]const u8, headers: *?std.StringHashMap([]const u8) }, @ptrCast(@alignCast(ctx)));
                data.body.* = resp_body;
                data.headers.* = resp_headers;
            }
            fn onError(_: *anyopaque, _: anyerror) void {}
        }.onResponse, struct {
            fn onError(_: *anyopaque, _: anyerror) void {}
        }.onError, &.{ .body = &response_data, .headers = &response_headers });

        const response_body = response_data orelse return error.NoResponse;

        // Parse response
        const parsed = std.json.parseFromSlice(api.OpenAIImageResponse, request_allocator, response_body, .{}) catch {
            return error.InvalidResponse;
        };
        const response = parsed.value;

        // Extract images as base64
        var images_list = try result_allocator.alloc([]const u8, response.data.len);
        for (response.data, 0..) |item, i| {
            images_list[i] = try result_allocator.dupe(u8, item.b64_json);
        }

        // Convert usage
        const usage: ?im.ImageModelV3Usage = if (response.usage) |u| .{
            .input_tokens = u.input_tokens,
            .output_tokens = u.output_tokens,
            .total_tokens = u.total_tokens,
        } else null;

        // Clone warnings
        var result_warnings = try result_allocator.alloc(shared.SharedV3Warning, warnings.items.len);
        for (warnings.items, 0..) |w, i| {
            result_warnings[i] = w;
        }

        return .{
            .images = .{ .base64 = images_list },
            .usage = usage,
            .warnings = result_warnings,
            .response = .{
                .timestamp = timestamp,
                .model_id = try result_allocator.dupe(u8, self.model_id),
                .headers = response_headers,
            },
        };
    }

    /// Convert to ImageModelV3 interface
    pub fn asImageModel(self: *Self) im.ImageModelV3 {
        return .{
            .vtable = &vtable,
            .impl = self,
        };
    }

    const vtable = im.ImageModelV3.VTable{
        .getProvider = getProviderVtable,
        .getModelId = getModelIdVtable,
        .getMaxImagesPerCall = getMaxImagesPerCallVtable,
        .doGenerate = doGenerateVtable,
    };

    fn getProviderVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getProvider();
    }

    fn getModelIdVtable(impl: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.getModelId();
    }

    fn getMaxImagesPerCallVtable(
        impl: *anyopaque,
        callback: *const fn (?*anyopaque, ?u32) void,
        context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.getMaxImagesPerCall(callback, context);
    }

    fn doGenerateVtable(
        impl: *anyopaque,
        call_options: im.ImageModelV3CallOptions,
        allocator: std.mem.Allocator,
        callback: *const fn (?*anyopaque, im.ImageModelV3.GenerateResult) void,
        context: ?*anyopaque,
    ) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.doGenerate(call_options, allocator, callback, context);
    }
};

/// Options for image generation
pub const GenerateOptions = struct {
    prompt: []const u8,
    n: ?u32 = null,
    size: ?[]const u8 = null,
    aspect_ratio: ?[]const u8 = null,
    seed: ?i64 = null,
    quality: ?options_mod.ImageQuality = null,
    style: ?options_mod.ImageStyle = null,
    user: ?[]const u8 = null,
    output_format: ?options_mod.ImageOutputFormat = null,
    background: ?options_mod.ImageBackground = null,
    output_compression: ?u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,
};

/// Result of generate call (legacy compatibility)
pub const GenerateResult = im.ImageModelV3.GenerateResult;

/// Serialize request to JSON
fn serializeRequest(allocator: std.mem.Allocator, request: api.OpenAIImageGenerationRequest) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, request, .{});
}

test "OpenAIImageModel basic" {
    const allocator = std.testing.allocator;

    const config = config_mod.OpenAIConfig{
        .provider = "openai.image",
        .base_url = "https://api.openai.com/v1",
        .headers_fn = struct {
            fn getHeaders(_: *const config_mod.OpenAIConfig, alloc: std.mem.Allocator) error{OutOfMemory}!std.StringHashMap([]const u8) {
                return std.StringHashMap([]const u8).init(alloc);
            }
        }.getHeaders,
    };

    const model = OpenAIImageModel.init(allocator, "dall-e-3", config);
    try std.testing.expectEqualStrings("openai.image", model.getProvider());
    try std.testing.expectEqualStrings("dall-e-3", model.getModelId());
}
