const std = @import("std");

// Memory management
pub const arena = @import("memory/arena.zig");
pub const ownership = @import("memory/ownership.zig");

pub const RequestArena = arena.RequestArena;
pub const ResponseArena = arena.ResponseArena;
pub const StreamingArena = arena.StreamingArena;

// HTTP client
pub const http = struct {
    pub const client = @import("http/client.zig");
    pub const std_client = @import("http/std-client.zig");
    pub const mock_client = @import("http/mock-client.zig");
};

pub const HttpClient = http.client.HttpClient;
pub const HttpMethod = http.client.HttpClient.Method;
pub const HttpRequest = http.client.HttpClient.Request;
pub const HttpResponse = http.client.HttpClient.Response;
pub const HttpError = http.client.HttpClient.HttpError;
pub const HttpHeader = http.client.HttpClient.Header;
pub const HttpStreamCallbacks = http.client.HttpClient.StreamCallbacks;
pub const RequestBuilder = http.client.RequestBuilder;
pub const createStdHttpClient = http.std_client.createStdHttpClient;

// Mock HTTP client for testing
pub const MockHttpClient = http.mock_client.MockHttpClient;
pub const createMockHttpClient = http.mock_client.createMockHttpClient;

// Streaming
pub const streaming = struct {
    pub const callbacks = @import("streaming/callbacks.zig");
};

pub const StreamCallbacks = streaming.callbacks.StreamCallbacks;
pub const CallbackBuilder = streaming.callbacks.CallbackBuilder;
pub const TextStreamCallbacks = streaming.callbacks.TextStreamCallbacks;
pub const ToolCallStreamCallbacks = streaming.callbacks.ToolCallStreamCallbacks;
pub const LanguageModelStreamCallbacks = streaming.callbacks.LanguageModelStreamCallbacks;
pub const StreamAccumulator = streaming.callbacks.StreamAccumulator;

// API utilities
pub const post_to_api = @import("post-to-api.zig");
pub const response_handler = @import("response-handler.zig");
pub const combine_headers = @import("combine-headers.zig");
pub const extract_response_headers = @import("extract-response-headers.zig");

pub const postToApi = post_to_api.postToApi;
pub const postJsonToApi = post_to_api.postJsonToApi;
pub const postJsonToApiStreaming = post_to_api.postJsonToApiStreaming;
pub const PostJsonToApiOptions = post_to_api.PostJsonToApiOptions;
pub const PostToApiOptions = post_to_api.PostToApiOptions;
pub const ApiResponse = post_to_api.ApiResponse;
pub const ApiError = post_to_api.ApiError;
pub const ApiCallbacks = post_to_api.ApiCallbacks;
pub const StreamingApiCallbacks = post_to_api.StreamingApiCallbacks;

pub const ResponseHandler = response_handler.ResponseHandler;
pub const createJsonResponseHandler = response_handler.createJsonResponseHandler;
pub const createBinaryResponseHandler = response_handler.createBinaryResponseHandler;

pub const combineHeaders = combine_headers.combineHeaders;

pub const extractResponseHeaders = extract_response_headers.extractResponseHeaders;

// JSON utilities
pub const parse_json = @import("parse-json.zig");
pub const parse_json_event_stream = @import("parse-json-event-stream.zig");

pub const safeParseJson = parse_json.safeParseJson;
pub const parseJson = parse_json.parseJson;
pub const isParsableJson = parse_json.isParsableJson;
pub const parseJsonTyped = parse_json.parseJsonTyped;
pub const extractJsonField = parse_json.extractJsonField;
pub const ParseResult = parse_json.ParseResult;
pub const ParseError = parse_json.ParseError;
pub const TypedParseResult = parse_json.TypedParseResult;

pub const EventSourceParser = parse_json_event_stream.EventSourceParser;
pub const parseJsonEventStream = parse_json_event_stream.parseJsonEventStream;
pub const JsonEventStreamParser = parse_json_event_stream.JsonEventStreamParser;
pub const ParseEventResult = parse_json_event_stream.ParseEventResult;
pub const JsonEventStreamCallbacks = parse_json_event_stream.JsonEventStreamCallbacks;
pub const SimpleJsonEventStreamParser = parse_json_event_stream.SimpleJsonEventStreamParser;

// ID generation
pub const generate_id = @import("generate-id.zig");

pub const IdGenerator = generate_id.IdGenerator;
pub const IdGeneratorConfig = generate_id.IdGeneratorConfig;
pub const createIdGenerator = generate_id.createIdGenerator;
pub const createPrefixedIdGenerator = generate_id.createPrefixedIdGenerator;
pub const createCustomIdGenerator = generate_id.createCustomIdGenerator;
pub const generateId = generate_id.generateId;
pub const generatePrefixedId = generate_id.generatePrefixedId;
pub const generateUuidLike = generate_id.generateUuidLike;
pub const hasPrefix = generate_id.hasPrefix;

// Security utilities (re-exported from provider)
pub const security = @import("provider").security;
pub const redactApiKey = security.redactApiKey;
pub const containsApiKey = security.containsApiKey;

// URL validation
pub const url_validation = @import("url-validation.zig");
pub const validateUrl = url_validation.validateUrl;
pub const normalizeUrl = url_validation.normalizeUrl;

// API key and settings loading
pub const load_api_key = @import("load-api-key.zig");

pub const loadApiKey = load_api_key.loadApiKey;
pub const loadOptionalApiKey = load_api_key.loadOptionalApiKey;
pub const hasApiKey = load_api_key.hasApiKey;
pub const LoadApiKeyOptions = load_api_key.LoadApiKeyOptions;

pub const loadOptionalSetting = load_api_key.loadOptionalSetting;
pub const LoadSettingOptions = load_api_key.LoadSettingOptions;

pub const withoutTrailingSlash = load_api_key.withoutTrailingSlash;
pub const loadOpenAIStyleConfig = load_api_key.loadOpenAIStyleConfig;
pub const ProviderConfig = load_api_key.ProviderConfig;

test {
    std.testing.refAllDecls(@This());
}
