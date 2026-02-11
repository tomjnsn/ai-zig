const std = @import("std");

// JSON Value Types
pub const json_value = @import("json-value/index.zig");
pub const JsonValue = json_value.JsonValue;
pub const JsonObject = json_value.JsonObject;
pub const JsonArray = json_value.JsonArray;
pub const isJsonValue = json_value.isJsonValue;

// Error Types
pub const errors = @import("errors/index.zig");
pub const AiSdkError = errors.AiSdkError;
pub const AiSdkErrorInfo = errors.AiSdkErrorInfo;
pub const ApiCallError = errors.ApiCallError;
pub const InvalidArgumentError = errors.InvalidArgumentError;
pub const InvalidResponseDataError = errors.InvalidResponseDataError;
pub const NoSuchModelError = errors.NoSuchModelError;
pub const TypeValidationError = errors.TypeValidationError;
pub const UnsupportedFunctionalityError = errors.UnsupportedFunctionalityError;
pub const ErrorDiagnostic = errors.ErrorDiagnostic;
pub const getErrorMessage = errors.getErrorMessage;

// Shared Types
pub const shared = @import("shared/v3/index.zig");
pub const SharedV3Warning = shared.SharedV3Warning;
pub const SharedV3ProviderMetadata = shared.SharedV3ProviderMetadata;
pub const SharedV3ProviderOptions = shared.SharedV3ProviderOptions;
pub const SharedV3Headers = shared.SharedV3Headers;

// Language Model
pub const language_model = @import("language-model/v3/index.zig");
pub const LanguageModelV3 = language_model.LanguageModelV3;
pub const LanguageModelV3CallOptions = language_model.LanguageModelV3CallOptions;
pub const LanguageModelV3Content = language_model.LanguageModelV3Content;
pub const LanguageModelV3FinishReason = language_model.LanguageModelV3FinishReason;
pub const LanguageModelV3Usage = language_model.LanguageModelV3Usage;
pub const LanguageModelV3StreamPart = language_model.LanguageModelV3StreamPart;
pub const LanguageModelV3Prompt = language_model.LanguageModelV3Prompt;
pub const LanguageModelV3Message = language_model.LanguageModelV3Message;
pub const LanguageModelV3ToolCall = language_model.LanguageModelV3ToolCall;
pub const LanguageModelV3ToolResult = language_model.LanguageModelV3ToolResult;
pub const LanguageModelV3ToolChoice = language_model.LanguageModelV3ToolChoice;
pub const LanguageModelV3FunctionTool = language_model.LanguageModelV3FunctionTool;
pub const LanguageModelV3ProviderTool = language_model.LanguageModelV3ProviderTool;
pub const implementLanguageModel = language_model.implementLanguageModel;
pub const asLanguageModel = language_model.asLanguageModel;

// Embedding Model
pub const embedding_model = @import("embedding-model/v3/index.zig");
pub const EmbeddingModelV3 = embedding_model.EmbeddingModelV3;
pub const EmbeddingModelCallOptions = embedding_model.EmbeddingModelCallOptions;
pub const EmbeddingModelV3Embedding = embedding_model.EmbeddingModelV3Embedding;
pub const Embedding = embedding_model.Embedding;
pub const implementEmbeddingModel = embedding_model.implementEmbeddingModel;
pub const asEmbeddingModel = embedding_model.asEmbeddingModel;

// Image Model
pub const image_model = @import("image-model/v3/index.zig");
pub const ImageModelV3 = image_model.ImageModelV3;
pub const ImageModelV3CallOptions = image_model.ImageModelV3CallOptions;
pub const ImageModelV3File = image_model.ImageModelV3File;
pub const ImageModelV3Usage = image_model.ImageModelV3Usage;
pub const implementImageModel = image_model.implementImageModel;
pub const asImageModel = image_model.asImageModel;

// Speech Model
pub const speech_model = @import("speech-model/v3/index.zig");
pub const SpeechModelV3 = speech_model.SpeechModelV3;
pub const SpeechModelV3CallOptions = speech_model.SpeechModelV3CallOptions;
pub const implementSpeechModel = speech_model.implementSpeechModel;
pub const asSpeechModel = speech_model.asSpeechModel;

// Transcription Model
pub const transcription_model = @import("transcription-model/v3/index.zig");
pub const TranscriptionModelV3 = transcription_model.TranscriptionModelV3;
pub const TranscriptionModelV3CallOptions = transcription_model.TranscriptionModelV3CallOptions;
pub const TranscriptionSegment = transcription_model.TranscriptionSegment;
pub const implementTranscriptionModel = transcription_model.implementTranscriptionModel;
pub const asTranscriptionModel = transcription_model.asTranscriptionModel;

// Security
pub const security = @import("security.zig");
pub const redactApiKey = security.redactApiKey;
pub const containsApiKey = security.containsApiKey;

// Provider
pub const provider = @import("provider/v3/index.zig");
pub const ProviderV3 = provider.ProviderV3;
pub const implementProvider = provider.implementProvider;
pub const asProvider = provider.asProvider;

test {
    std.testing.refAllDecls(@This());
}
