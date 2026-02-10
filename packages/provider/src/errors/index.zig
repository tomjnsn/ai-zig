// AI SDK Errors
// Re-exports all error types and utilities

// Core error types and utilities
pub const ai_sdk_error = @import("ai-sdk-error.zig");
pub const AiSdkError = ai_sdk_error.AiSdkError;
pub const AiSdkErrorInfo = ai_sdk_error.AiSdkErrorInfo;
pub const ErrorContext = ai_sdk_error.ErrorContext;
pub const isRetryableStatusCode = ai_sdk_error.isRetryableStatusCode;

// Individual error types
pub const api_call_error = @import("api-call-error.zig");
pub const ApiCallError = api_call_error.ApiCallError;

pub const api_error_details = @import("api-error-details.zig");
pub const ApiErrorDetails = api_error_details.ApiErrorDetails;

pub const empty_response_body_error = @import("empty-response-body-error.zig");
pub const EmptyResponseBodyError = empty_response_body_error.EmptyResponseBodyError;

pub const invalid_argument_error = @import("invalid-argument-error.zig");
pub const InvalidArgumentError = invalid_argument_error.InvalidArgumentError;

pub const invalid_prompt_error = @import("invalid-prompt-error.zig");
pub const InvalidPromptError = invalid_prompt_error.InvalidPromptError;

pub const invalid_response_data_error = @import("invalid-response-data-error.zig");
pub const InvalidResponseDataError = invalid_response_data_error.InvalidResponseDataError;

pub const json_parse_error = @import("json-parse-error.zig");
pub const JsonParseError = json_parse_error.JsonParseError;

pub const load_api_key_error = @import("load-api-key-error.zig");
pub const LoadApiKeyError = load_api_key_error.LoadApiKeyError;

pub const load_setting_error = @import("load-setting-error.zig");
pub const LoadSettingError = load_setting_error.LoadSettingError;

pub const no_content_generated_error = @import("no-content-generated-error.zig");
pub const NoContentGeneratedError = no_content_generated_error.NoContentGeneratedError;

pub const no_such_model_error = @import("no-such-model-error.zig");
pub const NoSuchModelError = no_such_model_error.NoSuchModelError;
pub const ModelType = no_such_model_error.ModelType;

pub const too_many_embedding_values_for_call_error = @import("too-many-embedding-values-for-call-error.zig");
pub const TooManyEmbeddingValuesForCallError = too_many_embedding_values_for_call_error.TooManyEmbeddingValuesForCallError;

pub const type_validation_error = @import("type-validation-error.zig");
pub const TypeValidationError = type_validation_error.TypeValidationError;

pub const unsupported_functionality_error = @import("unsupported-functionality-error.zig");
pub const UnsupportedFunctionalityError = unsupported_functionality_error.UnsupportedFunctionalityError;

// Error message utilities
pub const get_error_message = @import("get-error-message.zig");
pub const getErrorMessage = get_error_message.getErrorMessage;
pub const getErrorInfoMessage = get_error_message.getErrorInfoMessage;
pub const getErrorMessageOrUnknown = get_error_message.getErrorMessageOrUnknown;
pub const formatErrorChain = get_error_message.formatErrorChain;

// Context types (re-exported from ai-sdk-error)
pub const ApiCallContext = ai_sdk_error.ApiCallContext;
pub const InvalidArgumentContext = ai_sdk_error.InvalidArgumentContext;
pub const InvalidPromptContext = ai_sdk_error.InvalidPromptContext;
pub const InvalidResponseDataContext = ai_sdk_error.InvalidResponseDataContext;
pub const JsonParseContext = ai_sdk_error.JsonParseContext;
pub const NoSuchModelContext = ai_sdk_error.NoSuchModelContext;
pub const TooManyEmbeddingValuesContext = ai_sdk_error.TooManyEmbeddingValuesContext;
pub const TypeValidationContext = ai_sdk_error.TypeValidationContext;
pub const UnsupportedFunctionalityContext = ai_sdk_error.UnsupportedFunctionalityContext;

test {
    // Run all tests from submodules
    @import("std").testing.refAllDecls(@This());
}
