// Google Generative AI Provider for Zig AI SDK
//
// This module provides Google Generative AI API integration including:
// - Gemini models (1.5, 2.0, 2.5, 3.0)
// - Gemma models
// - Extended thinking support
// - Tool use / function calling
// - Code execution, web search, and other provider tools
// - Embedding models
// - Image generation (Imagen)

// Provider
pub const provider = @import("google-provider.zig");
pub const GoogleGenerativeAIProvider = provider.GoogleGenerativeAIProvider;
pub const GoogleGenerativeAIProviderSettings = provider.GoogleGenerativeAIProviderSettings;
pub const createGoogleGenerativeAI = provider.createGoogleGenerativeAI;
pub const createGoogleGenerativeAIWithSettings = provider.createGoogleGenerativeAIWithSettings;

// Configuration
pub const config = @import("google-config.zig");
pub const GoogleGenerativeAIConfig = config.GoogleGenerativeAIConfig;
pub const default_base_url = config.default_base_url;
pub const google_ai_version = config.google_ai_version;

// Error handling
pub const errors = @import("google-error.zig");
pub const GoogleErrorData = errors.GoogleErrorData;
pub const ErrorStatus = errors.ErrorStatus;

// Language model
pub const lang_model = @import("google-generative-ai-language-model.zig");
pub const GoogleGenerativeAILanguageModel = lang_model.GoogleGenerativeAILanguageModel;

// Embedding model
pub const embed_model = @import("google-generative-ai-embedding-model.zig");
pub const GoogleGenerativeAIEmbeddingModel = embed_model.GoogleGenerativeAIEmbeddingModel;

// Image model (Imagen predict API)
pub const image_model = @import("google-generative-ai-image-model.zig");
pub const GoogleGenerativeAIImageModel = image_model.GoogleGenerativeAIImageModel;

// Image model (Gemini generateContent API)
pub const gemini_image = @import("google-gemini-image-model.zig");
pub const GoogleGeminiImageModel = gemini_image.GoogleGeminiImageModel;
pub const isGeminiImageModel = gemini_image.isGeminiImageModel;

// Options
pub const options = @import("google-generative-ai-options.zig");
pub const Models = options.Models;
pub const EmbeddingModels = options.EmbeddingModels;
pub const ImageModels = options.ImageModels;
pub const GoogleGenerativeAIProviderOptions = options.GoogleGenerativeAIProviderOptions;
pub const GoogleGenerativeAIEmbeddingProviderOptions = options.GoogleGenerativeAIEmbeddingProviderOptions;
pub const GoogleGenerativeAIImageSettings = options.GoogleGenerativeAIImageSettings;
pub const GoogleGenerativeAIImageProviderOptions = options.GoogleGenerativeAIImageProviderOptions;
pub const HarmCategory = options.HarmCategory;
pub const HarmBlockThreshold = options.HarmBlockThreshold;
pub const SafetySetting = options.SafetySetting;
pub const ThinkingConfig = options.ThinkingConfig;
pub const ResponseModality = options.ResponseModality;
pub const MediaResolution = options.MediaResolution;
pub const ImageConfig = options.ImageConfig;
pub const RetrievalConfig = options.RetrievalConfig;
pub const isGemmaModel = options.isGemmaModel;
pub const isGemini2OrNewer = options.isGemini2OrNewer;
pub const supportsDynamicRetrieval = options.supportsDynamicRetrieval;
pub const supportsFileSearch = options.supportsFileSearch;

// Prompt types
pub const prompt = @import("google-generative-ai-prompt.zig");
pub const GoogleGenerativeAIPrompt = prompt.GoogleGenerativeAIPrompt;
pub const GoogleGenerativeAIContent = prompt.GoogleGenerativeAIContent;
pub const GoogleGenerativeAIContentPart = prompt.GoogleGenerativeAIContentPart;

// Message conversion
pub const convert = @import("convert-to-google-generative-ai-messages.zig");
pub const convertToGoogleGenerativeAIMessages = convert.convertToGoogleGenerativeAIMessages;
pub const freeConvertResult = convert.freeConvertResult;

// Tool preparation
pub const prepare_tools = @import("google-prepare-tools.zig");
pub const prepareTools = prepare_tools.prepareTools;
pub const freePrepareToolsResult = prepare_tools.freePrepareToolsResult;
pub const ToolConfig = prepare_tools.ToolConfig;
pub const FunctionDeclaration = prepare_tools.FunctionDeclaration;
pub const ProviderTool = prepare_tools.ProviderTool;

// Stop reason mapping
pub const map_finish = @import("map-google-generative-ai-finish-reason.zig");
pub const mapGoogleGenerativeAIFinishReason = map_finish.mapGoogleGenerativeAIFinishReason;

// Response types
pub const response = @import("google-generative-ai-response.zig");
pub const GoogleGenerateContentResponse = response.GoogleGenerateContentResponse;
pub const GoogleEmbedContentResponse = response.GoogleEmbedContentResponse;
pub const GoogleBatchEmbedContentsResponse = response.GoogleBatchEmbedContentsResponse;
pub const GooglePredictResponse = response.GooglePredictResponse;

test {
    // Run all module tests
    @import("std").testing.refAllDecls(@This());
}
