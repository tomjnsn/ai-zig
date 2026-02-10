// Zig AI SDK - High-Level API
//
// This module provides the high-level API for AI SDK functionality.
// It brings together text generation, object generation, embeddings,
// image generation, speech synthesis, transcription, and more.
//
// Example usage:
//
//   const ai = @import("ai");
//   const openai = @import("openai");
//
//   var provider = openai.createOpenAI(allocator);
//   var model = provider.languageModel("gpt-4");
//
//   const result = try ai.generateText(allocator, .{
//       .model = &model,
//       .prompt = "Hello, world!",
//   });
//
//   std.debug.print("{s}\n", .{result.text});

const std = @import("std");
const provider_utils = @import("provider-utils");

// Generate Text - Text generation with tool support
pub const generate_text = @import("generate-text/index.zig");
pub const generateText = generate_text.generateText;
pub const streamText = generate_text.streamText;
pub const GenerateTextResult = generate_text.GenerateTextResult;
pub const GenerateTextOptions = generate_text.GenerateTextOptions;
pub const StreamTextResult = generate_text.StreamTextResult;
pub const StreamTextOptions = generate_text.StreamTextOptions;
pub const StreamCallbacks = generate_text.StreamCallbacks;
pub const StreamPart = generate_text.StreamPart;
pub const FinishReason = generate_text.FinishReason;
pub const LanguageModelUsage = generate_text.LanguageModelUsage;
pub const ToolCall = generate_text.ToolCall;
pub const ToolResult = generate_text.ToolResult;
pub const ContentPart = generate_text.ContentPart;
pub const Message = generate_text.Message;
pub const MessageRole = generate_text.MessageRole;
pub const CallSettings = generate_text.CallSettings;
pub const TextGenerationBuilder = generate_text.TextGenerationBuilder;
pub const StreamTextBuilder = generate_text.StreamTextBuilder;

// Generate Object - Structured object generation
pub const generate_object = @import("generate-object/index.zig");
pub const generateObject = generate_object.generateObject;
pub const streamObject = generate_object.streamObject;
pub const GenerateObjectResult = generate_object.GenerateObjectResult;
pub const GenerateObjectOptions = generate_object.GenerateObjectOptions;
pub const StreamObjectResult = generate_object.StreamObjectResult;
pub const StreamObjectOptions = generate_object.StreamObjectOptions;
pub const Schema = generate_object.Schema;
pub const OutputMode = generate_object.OutputMode;

// Embed - Text embeddings
pub const embed_mod = @import("embed/index.zig");
pub const embed = embed_mod.embed;
pub const embedMany = embed_mod.embedMany;
pub const EmbedResult = embed_mod.EmbedResult;
pub const EmbedManyResult = embed_mod.EmbedManyResult;
pub const EmbedOptions = embed_mod.EmbedOptions;
pub const EmbedManyOptions = embed_mod.EmbedManyOptions;
pub const Embedding = embed_mod.Embedding;
pub const EmbedBuilder = embed_mod.EmbedBuilder;
pub const cosineSimilarity = embed_mod.cosineSimilarity;
pub const euclideanDistance = embed_mod.euclideanDistance;
pub const dotProduct = embed_mod.dotProduct;

// Generate Image - Image generation
pub const generate_image = @import("generate-image/index.zig");
pub const generateImage = generate_image.generateImage;
pub const GenerateImageResult = generate_image.GenerateImageResult;
pub const GenerateImageOptions = generate_image.GenerateImageOptions;
pub const GeneratedImage = generate_image.GeneratedImage;
pub const ImageSize = generate_image.ImageSize;
pub const ImageQuality = generate_image.ImageQuality;
pub const ImageStyle = generate_image.ImageStyle;

// Generate Speech - Text-to-speech
pub const generate_speech = @import("generate-speech/index.zig");
pub const generateSpeech = generate_speech.generateSpeech;
pub const streamSpeech = generate_speech.streamSpeech;
pub const GenerateSpeechResult = generate_speech.GenerateSpeechResult;
pub const GenerateSpeechOptions = generate_speech.GenerateSpeechOptions;
pub const GeneratedAudio = generate_speech.GeneratedAudio;
pub const AudioFormat = generate_speech.AudioFormat;
pub const VoiceSettings = generate_speech.VoiceSettings;

// Transcribe - Speech-to-text
pub const transcribe_mod = @import("transcribe/index.zig");
pub const transcribe = transcribe_mod.transcribe;
pub const TranscribeResult = transcribe_mod.TranscribeResult;
pub const TranscribeOptions = transcribe_mod.TranscribeOptions;
pub const TranscriptionSegment = transcribe_mod.TranscriptionSegment;
pub const TranscriptionWord = transcribe_mod.TranscriptionWord;
pub const AudioSource = transcribe_mod.AudioSource;

// Tools - Function calling
pub const tool_mod = @import("tool/index.zig");
pub const Tool = tool_mod.Tool;
pub const ToolConfig = tool_mod.ToolConfig;
pub const DynamicTool = tool_mod.DynamicTool;
pub const ToolExecutionContext = tool_mod.ToolExecutionContext;
pub const ToolExecutionResult = tool_mod.ToolExecutionResult;
pub const ApprovalRequirement = tool_mod.ApprovalRequirement;

// Context - Request timeout and cancellation
pub const context = @import("context.zig");
pub const RequestContext = context.RequestContext;

// Retry - Configurable retry policy with backoff
pub const retry = @import("retry.zig");
pub const RetryPolicy = retry.RetryPolicy;

// Middleware - Request/response transformation
pub const middleware = @import("middleware/index.zig");
pub const MiddlewareChain = middleware.MiddlewareChain;
pub const MiddlewareContext = middleware.MiddlewareContext;
pub const MiddlewareRequest = middleware.MiddlewareRequest;
pub const MiddlewareResponse = middleware.MiddlewareResponse;
pub const RequestMiddleware = middleware.RequestMiddleware;
pub const ResponseMiddleware = middleware.ResponseMiddleware;

// Version
pub const VERSION = "0.1.0";

/// Create a unique ID
pub fn generateId(allocator: std.mem.Allocator) ![]const u8 {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch {
            seed = provider_utils.safeCast(u64, std.time.milliTimestamp()) catch 0;
        };
        break :blk seed;
    });

    const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    const id_len = 24;

    var id = try allocator.alloc(u8, id_len);
    for (0..id_len) |i| {
        id[i] = charset[prng.random().intRangeAtMost(usize, 0, charset.len - 1)];
    }

    return id;
}

/// Create a timestamped ID with prefix
pub fn createId(allocator: std.mem.Allocator, prefix: []const u8) ![]const u8 {
    const random_part = try generateId(allocator);
    defer allocator.free(random_part);

    return std.fmt.allocPrint(allocator, "{s}-{s}", .{ prefix, random_part });
}

test {
    // Run tests for all submodules
    std.testing.refAllDecls(@This());
}

test "generateId creates unique IDs" {
    const allocator = std.testing.allocator;

    const id1 = try generateId(allocator);
    defer allocator.free(id1);

    const id2 = try generateId(allocator);
    defer allocator.free(id2);

    try std.testing.expect(!std.mem.eql(u8, id1, id2));
    try std.testing.expectEqual(@as(usize, 24), id1.len);
}

test "createId adds prefix" {
    const allocator = std.testing.allocator;

    const id = try createId(allocator, "test");
    defer allocator.free(id);

    try std.testing.expect(std.mem.startsWith(u8, id, "test-"));
}
