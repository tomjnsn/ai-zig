// Google Vertex AI Provider for Zig AI SDK
//
// This module provides Google Vertex AI API integration including:
// - Gemini models via Vertex AI
// - Express mode with API key authentication
// - Standard mode with project/location authentication
// - Embedding models
// - Image generation (Imagen) with editing support

// Provider
pub const provider = @import("google-vertex-provider.zig");
pub const GoogleVertexProvider = provider.GoogleVertexProvider;
pub const GoogleVertexProviderSettings = provider.GoogleVertexProviderSettings;
pub const createVertex = provider.createVertex;
pub const createVertexWithSettings = provider.createVertexWithSettings;

// Configuration
pub const config = @import("google-vertex-config.zig");
pub const GoogleVertexConfig = config.GoogleVertexConfig;
pub const express_mode_base_url = config.express_mode_base_url;
pub const buildBaseUrl = config.buildBaseUrl;

// Error handling
pub const errors = @import("google-vertex-error.zig");
pub const GoogleVertexErrorData = errors.GoogleVertexErrorData;

// Embedding model
pub const embed_model = @import("google-vertex-embedding-model.zig");
pub const GoogleVertexEmbeddingModel = embed_model.GoogleVertexEmbeddingModel;

// Image model
pub const image_model = @import("google-vertex-image-model.zig");
pub const GoogleVertexImageModel = image_model.GoogleVertexImageModel;

// Options
pub const options = @import("google-vertex-options.zig");
pub const Models = options.Models;
pub const EmbeddingModels = options.EmbeddingModels;
pub const ImageModels = options.ImageModels;
pub const GoogleVertexEmbeddingProviderOptions = options.GoogleVertexEmbeddingProviderOptions;
pub const GoogleVertexImageProviderOptions = options.GoogleVertexImageProviderOptions;
pub const TaskType = options.TaskType;
pub const EditMode = options.EditMode;
pub const MaskMode = options.MaskMode;
pub const ImageEditConfig = options.ImageEditConfig;
pub const PersonGeneration = options.PersonGeneration;
pub const SafetySetting = options.SafetySetting;
pub const SampleImageSize = options.SampleImageSize;

// Response types
pub const response = @import("google-vertex-response.zig");
pub const VertexPredictEmbeddingResponse = response.VertexPredictEmbeddingResponse;
pub const VertexPredictImageResponse = response.VertexPredictImageResponse;

test {
    // Run all module tests
    @import("std").testing.refAllDecls(@This());
}
