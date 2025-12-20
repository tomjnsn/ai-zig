// Image Generation Example
//
// This example demonstrates how to generate images using different
// AI image models. The SDK supports multiple providers including
// OpenAI (DALL-E), Fal (FLUX, Stable Diffusion), and more.

const std = @import("std");
const ai = @import("ai");
const openai = @import("openai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Image Generation Example\n", .{});
    std.debug.print("========================\n\n", .{});

    // Example 1: OpenAI DALL-E Models
    std.debug.print("1. OpenAI DALL-E Image Generation\n", .{});
    std.debug.print("----------------------------------\n", .{});

    var openai_provider = openai.createOpenAI(allocator);
    defer openai_provider.deinit();

    std.debug.print("Provider: {s}\n", .{openai_provider.getProvider()});
    std.debug.print("Available models:\n", .{});
    std.debug.print("  - dall-e-2: Fast, multiple images per request\n", .{});
    std.debug.print("  - dall-e-3: High quality, improved prompt adherence\n", .{});
    std.debug.print("  - gpt-image-1: Latest model with advanced features\n", .{});
    std.debug.print("  - gpt-image-1-mini: Faster, cost-effective variant\n", .{});
    std.debug.print("\n", .{});

    // Create an image model
    var dalle3_model = openai_provider.imageModel("dall-e-3");
    std.debug.print("Model ID: {s}\n", .{dalle3_model.getModelId()});
    std.debug.print("Model Provider: {s}\n", .{dalle3_model.getProvider()});
    std.debug.print("\n", .{});

    // Example generateImage call (requires API key)
    std.debug.print("Example usage:\n", .{});
    std.debug.print("  const result = try ai.generateImage(allocator, .{{\n", .{});
    std.debug.print("      .model = &dalle3_model,\n", .{});
    std.debug.print("      .prompt = \"A serene mountain landscape at sunset\",\n", .{});
    std.debug.print("      .size = .{{ .preset = .large }},\n", .{});
    std.debug.print("      .quality = .hd,\n", .{});
    std.debug.print("      .style = .vivid,\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("  defer result.deinit(allocator);\n", .{});
    std.debug.print("\n", .{});

    // Example 2: Fal FLUX Models
    std.debug.print("2. Fal FLUX Image Generation\n", .{});
    std.debug.print("-----------------------------\n", .{});

    std.debug.print("The Fal provider supports advanced image models:\n", .{});
    std.debug.print("  - fal-ai/flux-pro: High quality, commercial use\n", .{});
    std.debug.print("  - fal-ai/flux-dev: Development model, fast iteration\n", .{});
    std.debug.print("  - fal-ai/flux-schnell: Ultra-fast generation\n", .{});
    std.debug.print("  - fal-ai/stable-diffusion-v3: Classic Stable Diffusion\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("To use Fal models:\n", .{});
    std.debug.print("  const fal = @import(\"fal\");\n", .{});
    std.debug.print("  var fal_provider = fal.createFal(allocator);\n", .{});
    std.debug.print("  defer fal_provider.deinit();\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  var flux_model = fal_provider.imageModel(\"fal-ai/flux-pro\");\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example usage:\n", .{});
    std.debug.print("  const result = try ai.generateImage(allocator, .{{\n", .{});
    std.debug.print("      .model = &flux_model,\n", .{});
    std.debug.print("      .prompt = \"A futuristic cityscape with flying cars\",\n", .{});
    std.debug.print("      .negative_prompt = \"blurry, low quality, distorted\",\n", .{});
    std.debug.print("      .size = .{{ .custom = .{{ .width = 1024, .height = 768 }} }},\n", .{});
    std.debug.print("      .seed = 42,\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("  defer result.deinit(allocator);\n", .{});
    std.debug.print("\n", .{});

    // Example 3: Image Size Options
    std.debug.print("3. Image Size Options\n", .{});
    std.debug.print("----------------------\n", .{});

    std.debug.print("Preset sizes:\n", .{});
    std.debug.print("  - small: 256x256\n", .{});
    std.debug.print("  - medium: 512x512\n", .{});
    std.debug.print("  - large: 1024x1024\n", .{});
    std.debug.print("  - wide: 1792x1024\n", .{});
    std.debug.print("  - tall: 1024x1792\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Usage:\n", .{});
    std.debug.print("  .size = .{{ .preset = .large }}\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Custom size:\n", .{});
    std.debug.print("  .size = .{{ .custom = .{{ .width = 1280, .height = 720 }} }}\n", .{});
    std.debug.print("\n", .{});

    // Example 4: Quality and Style Options
    std.debug.print("4. Quality and Style Options\n", .{});
    std.debug.print("-----------------------------\n", .{});

    std.debug.print("Quality levels:\n", .{});
    std.debug.print("  - .standard: Faster generation, good quality\n", .{});
    std.debug.print("  - .hd: Higher detail and consistency (DALL-E 3 only)\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Style options:\n", .{});
    std.debug.print("  - .natural: More natural, less hyper-real looking images\n", .{});
    std.debug.print("  - .vivid: Hyper-real and dramatic images (DALL-E 3 only)\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example combining options:\n", .{});
    std.debug.print("  .quality = .hd,\n", .{});
    std.debug.print("  .style = .vivid,\n", .{});
    std.debug.print("  .size = .{{ .preset = .wide }},\n", .{});
    std.debug.print("\n", .{});

    // Example 5: Handling Generated Images
    std.debug.print("5. Handling Generated Images\n", .{});
    std.debug.print("-----------------------------\n", .{});

    std.debug.print("The GenerateImageResult contains:\n", .{});
    std.debug.print("  - images: Array of generated images\n", .{});
    std.debug.print("  - usage: Token/credit usage information\n", .{});
    std.debug.print("  - response: Metadata (model_id, timestamp, headers)\n", .{});
    std.debug.print("  - warnings: Optional warnings from the provider\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Each GeneratedImage contains:\n", .{});
    std.debug.print("  - url: URL to download the image\n", .{});
    std.debug.print("  - base64: Base64-encoded image data (if available)\n", .{});
    std.debug.print("  - mime_type: MIME type (default: \"image/png\")\n", .{});
    std.debug.print("  - revised_prompt: Model's interpretation of your prompt\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example result handling:\n", .{});
    std.debug.print("  const result = try ai.generateImage(allocator, options);\n", .{});
    std.debug.print("  defer result.deinit(allocator);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Get the first image\n", .{});
    std.debug.print("  if (result.getImage()) |image| {{\n", .{});
    std.debug.print("      std.debug.print(\"Image URL: {{s}}\\n\", .{{image.url orelse \"none\"}});\n", .{});
    std.debug.print("      std.debug.print(\"MIME Type: {{s}}\\n\", .{{image.mime_type}});\n", .{});
    std.debug.print("      \n", .{});
    std.debug.print("      // If model revised the prompt\n", .{});
    std.debug.print("      if (image.revised_prompt) |revised| {{\n", .{});
    std.debug.print("          std.debug.print(\"Revised prompt: {{s}}\\n\", .{{revised}});\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("      \n", .{});
    std.debug.print("      // Get decoded image data\n", .{});
    std.debug.print("      if (image.base64 != null) {{\n", .{});
    std.debug.print("          const data = try image.getData(allocator);\n", .{});
    std.debug.print("          defer allocator.free(data);\n", .{});
    std.debug.print("          // Save to file or process\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Access all images\n", .{});
    std.debug.print("  for (result.images, 0..) |image, i| {{\n", .{});
    std.debug.print("      std.debug.print(\"Image {{d}}: {{s}}\\n\", .{{i + 1, image.url orelse \"no url\"}});\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // Example 6: Advanced Options
    std.debug.print("6. Advanced Options\n", .{});
    std.debug.print("-------------------\n", .{});

    std.debug.print("Generate multiple images:\n", .{});
    std.debug.print("  .n = 4,  // Generate 4 images (DALL-E 2 supports up to 10)\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Reproducible generation:\n", .{});
    std.debug.print("  .seed = 12345,  // Use same seed for consistent results\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Negative prompts (Fal models):\n", .{});
    std.debug.print("  .negative_prompt = \"blurry, watermark, text, low quality\",\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Retry on failure:\n", .{});
    std.debug.print("  .max_retries = 3,  // Retry up to 3 times on failure\n", .{});
    std.debug.print("\n", .{});

    // Example 7: Use Cases
    std.debug.print("7. Common Use Cases\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("  - Product visualization: Generate mockups and variations\n", .{});
    std.debug.print("  - Creative content: Illustrations, concept art, marketing materials\n", .{});
    std.debug.print("  - Prototyping: Quick visual ideation and design exploration\n", .{});
    std.debug.print("  - Data augmentation: Generate training data for ML models\n", .{});
    std.debug.print("  - Personalization: Custom images based on user preferences\n", .{});
    std.debug.print("  - Storyboarding: Visual storytelling and narrative development\n", .{});
    std.debug.print("\n", .{});

    // Example 8: Model Comparison
    std.debug.print("8. Model Comparison\n", .{});
    std.debug.print("-------------------\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("| Model          | Provider | Strengths                           |\n", .{});
    std.debug.print("|----------------|----------|-------------------------------------|\n", .{});
    std.debug.print("| DALL-E 3       | OpenAI   | Prompt adherence, quality, safety   |\n", .{});
    std.debug.print("| DALL-E 2       | OpenAI   | Fast, multiple images per call      |\n", .{});
    std.debug.print("| gpt-image-1    | OpenAI   | Latest features, transparency       |\n", .{});
    std.debug.print("| FLUX Pro       | Fal      | High quality, commercial use        |\n", .{});
    std.debug.print("| FLUX Dev       | Fal      | Fast iteration, development         |\n", .{});
    std.debug.print("| FLUX Schnell   | Fal      | Ultra-fast, real-time generation    |\n", .{});
    std.debug.print("| Stable Diff    | Fal      | Open source, customizable           |\n", .{});
    std.debug.print("\n", .{});

    // Example 9: Error Handling
    std.debug.print("9. Error Handling\n", .{});
    std.debug.print("-----------------\n", .{});
    std.debug.print("Possible errors:\n", .{});
    std.debug.print("  - ModelError: Model-specific error\n", .{});
    std.debug.print("  - NetworkError: Connection or API error\n", .{});
    std.debug.print("  - InvalidPrompt: Empty or invalid prompt\n", .{});
    std.debug.print("  - ContentFiltered: Content policy violation\n", .{});
    std.debug.print("  - TooManyImages: Requested more images than supported\n", .{});
    std.debug.print("  - OutOfMemory: Memory allocation failed\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Example error handling:\n", .{});
    std.debug.print("  const result = ai.generateImage(allocator, options) catch |err| {{\n", .{});
    std.debug.print("      switch (err) {{\n", .{});
    std.debug.print("          error.InvalidPrompt => std.debug.print(\"Prompt is empty!\\n\", .{{}}),\n", .{});
    std.debug.print("          error.ContentFiltered => std.debug.print(\"Content policy violation\\n\", .{{}}),\n", .{});
    std.debug.print("          else => std.debug.print(\"Error: {{}}\\n\", .{{err}}),\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("      return err;\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // Example 10: Complete Example
    std.debug.print("10. Complete Example\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("Here's a complete example that would work with API keys:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Set up provider (reads OPENAI_API_KEY from environment)\n", .{});
    std.debug.print("  var provider = openai.createOpenAI(allocator);\n", .{});
    std.debug.print("  defer provider.deinit();\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Create model\n", .{});
    std.debug.print("  var model = provider.imageModel(\"dall-e-3\");\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Generate image\n", .{});
    std.debug.print("  const result = try ai.generateImage(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .prompt = \"A peaceful zen garden with a stone path\",\n", .{});
    std.debug.print("      .size = .{{ .preset = .large }},\n", .{});
    std.debug.print("      .quality = .hd,\n", .{});
    std.debug.print("      .style = .natural,\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("  defer result.deinit(allocator);\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // Use the generated image\n", .{});
    std.debug.print("  if (result.getImage()) |image| {{\n", .{});
    std.debug.print("      if (image.url) |url| {{\n", .{});
    std.debug.print("          std.debug.print(\"Generated image: {{s}}\\n\", .{{url}});\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example complete!\n", .{});
}
