// Text-to-Speech Example
//
// This example demonstrates how to generate speech from text using
// the Zig AI SDK with OpenAI TTS and ElevenLabs providers.

const std = @import("std");
const ai = @import("ai");
const openai = @import("openai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Text-to-Speech Example\n", .{});
    std.debug.print("======================\n\n", .{});

    // Example 1: OpenAI TTS Provider Setup
    std.debug.print("1. OpenAI TTS Provider\n", .{});
    std.debug.print("-----------------------\n", .{});

    var openai_provider = openai.createOpenAI(allocator);
    defer openai_provider.deinit();

    std.debug.print("Provider: {s}\n", .{openai_provider.getProvider()});
    std.debug.print("\n", .{});
    std.debug.print("Available OpenAI TTS models:\n", .{});
    std.debug.print("  - tts-1           (Standard quality, faster)\n", .{});
    std.debug.print("  - tts-1-hd        (High definition, higher quality)\n", .{});
    std.debug.print("  - gpt-4o-mini-tts (Latest GPT-4o mini TTS)\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Available voices:\n", .{});
    std.debug.print("  - alloy   (Neutral, balanced)\n", .{});
    std.debug.print("  - ash     (Warm, friendly)\n", .{});
    std.debug.print("  - ballad  (Calm, soothing)\n", .{});
    std.debug.print("  - coral   (Warm, expressive)\n", .{});
    std.debug.print("  - echo    (Clear, professional)\n", .{});
    std.debug.print("  - fable   (British, storytelling)\n", .{});
    std.debug.print("  - onyx    (Deep, authoritative)\n", .{});
    std.debug.print("  - nova    (Bright, energetic)\n", .{});
    std.debug.print("  - sage    (Mature, wise)\n", .{});
    std.debug.print("  - shimmer (Gentle, soft)\n", .{});
    std.debug.print("  - verse   (Melodic, expressive)\n", .{});
    std.debug.print("\n", .{});

    // Example 2: Audio Format Options
    std.debug.print("2. Audio Format Options\n", .{});
    std.debug.print("------------------------\n", .{});

    std.debug.print("Supported output formats:\n", .{});
    std.debug.print("  - mp3  (default, widely compatible)\n", .{});
    std.debug.print("  - opus (high quality, low bandwidth)\n", .{});
    std.debug.print("  - aac  (good quality, mobile-friendly)\n", .{});
    std.debug.print("  - flac (lossless, highest quality)\n", .{});
    std.debug.print("  - wav  (uncompressed, standard)\n", .{});
    std.debug.print("  - pcm  (raw audio, lowest level)\n", .{});
    std.debug.print("  - ogg  (open format, good compression)\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("MIME types:\n", .{});
    std.debug.print("  - mp3  -> audio/mpeg\n", .{});
    std.debug.print("  - wav  -> audio/wav\n", .{});
    std.debug.print("  - ogg  -> audio/ogg\n", .{});
    std.debug.print("  - flac -> audio/flac\n", .{});
    std.debug.print("\n", .{});

    // Example 4: Generate Speech API
    std.debug.print("4. Generate Speech API\n", .{});
    std.debug.print("-----------------------\n", .{});

    std.debug.print("Basic speech generation:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var tts_model = openai_provider.speechModel(\"tts-1\");\n", .{});
    std.debug.print("  const result = try ai.generateSpeech(allocator, .{{\n", .{});
    std.debug.print("      .model = &tts_model,\n", .{});
    std.debug.print("      .text = \"Hello, world! This is text-to-speech.\",\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("  defer result.deinit(allocator);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Access the audio data\n", .{});
    std.debug.print("  const audio_data = result.audio.data;\n", .{});
    std.debug.print("  const audio_format = result.audio.format;\n", .{});
    std.debug.print("  const mime_type = result.audio.getMimeType();\n", .{});
    std.debug.print("\n", .{});

    // Example 5: Speech with Voice Settings
    std.debug.print("5. Speech with Voice Settings\n", .{});
    std.debug.print("------------------------------\n", .{});

    std.debug.print("Customize voice and format:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var tts_model = openai_provider.speechModel(\"tts-1-hd\");\n", .{});
    std.debug.print("  const result = try ai.generateSpeech(allocator, .{{\n", .{});
    std.debug.print("      .model = &tts_model,\n", .{});
    std.debug.print("      .text = \"Welcome to Zig AI SDK!\",\n", .{});
    std.debug.print("      .voice = \"nova\",\n", .{});
    std.debug.print("      .format = .mp3,\n", .{});
    std.debug.print("      .voice_settings = .{{\n", .{});
    std.debug.print("          .speed = 1.2,  // 20% faster\n", .{});
    std.debug.print("          .volume = 0.9, // 90% volume\n", .{});
    std.debug.print("      }},\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("  defer result.deinit(allocator);\n", .{});
    std.debug.print("\n", .{});

    // Example 6: Stream Speech API
    std.debug.print("7. Stream Speech API\n", .{});
    std.debug.print("---------------------\n", .{});

    std.debug.print("Stream audio as it's generated (for real-time playback):\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const callbacks = ai.SpeechStreamCallbacks{{\n", .{});
    std.debug.print("      .on_chunk = onAudioChunk,\n", .{});
    std.debug.print("      .on_error = onStreamError,\n", .{});
    std.debug.print("      .on_complete = onStreamComplete,\n", .{});
    std.debug.print("      .context = null,\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  var tts_model = openai_provider.speechModel(\"tts-1\");\n", .{});
    std.debug.print("  try ai.streamSpeech(allocator, .{{\n", .{});
    std.debug.print("      .model = &tts_model,\n", .{});
    std.debug.print("      .text = \"This will stream audio chunks.\",\n", .{});
    std.debug.print("      .voice = \"alloy\",\n", .{});
    std.debug.print("      .callbacks = callbacks,\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("\n", .{});

    // Example 8: Callback Functions
    std.debug.print("8. Callback Functions\n", .{});
    std.debug.print("----------------------\n", .{});

    std.debug.print("Implement callbacks for streaming:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  fn onAudioChunk(data: []const u8, ctx: ?*anyopaque) void {{\n", .{});
    std.debug.print("      _ = ctx;\n", .{});
    std.debug.print("      // Process audio chunk (e.g., play or save)\n", .{});
    std.debug.print("      std.debug.print(\"Received {{d}} bytes\\n\", .{{data.len}});\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  fn onStreamError(err: anyerror, ctx: ?*anyopaque) void {{\n", .{});
    std.debug.print("      _ = ctx;\n", .{});
    std.debug.print("      std.debug.print(\"Error: {{s}}\\n\", .{{@errorName(err)}});\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  fn onStreamComplete(ctx: ?*anyopaque) void {{\n", .{});
    std.debug.print("      _ = ctx;\n", .{});
    std.debug.print("      std.debug.print(\"Stream complete!\\n\", .{{}});\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // Example 9: Usage Information
    std.debug.print("9. Usage Information\n", .{});
    std.debug.print("---------------------\n", .{});

    std.debug.print("Track usage and metadata:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const result = try ai.generateSpeech(allocator, options);\n", .{});
    std.debug.print("  defer result.deinit(allocator);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Usage statistics\n", .{});
    std.debug.print("  if (result.usage.characters) |chars| {{\n", .{});
    std.debug.print("      std.debug.print(\"Characters: {{d}}\\n\", .{{chars}});\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("  if (result.usage.duration_seconds) |duration| {{\n", .{});
    std.debug.print("      std.debug.print(\"Duration: {{d:.2}}s\\n\", .{{duration}});\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Response metadata\n", .{});
    std.debug.print("  std.debug.print(\"Model: {{s}}\\n\", .{{result.response.model_id}});\n", .{});
    std.debug.print("  if (result.response.id) |id| {{\n", .{});
    std.debug.print("      std.debug.print(\"Request ID: {{s}}\\n\", .{{id}});\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // Example 10: Saving Audio to File
    std.debug.print("10. Saving Audio to File\n", .{});
    std.debug.print("-------------------------\n", .{});

    std.debug.print("Save generated audio:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const result = try ai.generateSpeech(allocator, .{{\n", .{});
    std.debug.print("      .model = &tts_model,\n", .{});
    std.debug.print("      .text = \"Save this as audio.\",\n", .{});
    std.debug.print("      .format = .mp3,\n", .{});
    std.debug.print("  }});\n", .{});
    std.debug.print("  defer result.deinit(allocator);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Write to file\n", .{});
    std.debug.print("  const file = try std.fs.cwd().createFile(\"output.mp3\", .{{}});\n", .{});
    std.debug.print("  defer file.close();\n", .{});
    std.debug.print("  try file.writeAll(result.audio.data);\n", .{});
    std.debug.print("\n", .{});

    // Example 11: Error Handling
    std.debug.print("11. Error Handling\n", .{});
    std.debug.print("-------------------\n", .{});

    std.debug.print("Handle common errors:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  const result = ai.generateSpeech(allocator, options) catch |err| {{\n", .{});
    std.debug.print("      switch (err) {{\n", .{});
    std.debug.print("          error.InvalidText => {{\n", .{});
    std.debug.print("              // Text is empty or invalid\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("          error.InvalidVoice => {{\n", .{});
    std.debug.print("              // Voice ID not supported\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("          error.TextTooLong => {{\n", .{});
    std.debug.print("              // Text exceeds provider limits\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("          error.NetworkError => {{\n", .{});
    std.debug.print("              // Connection or API error\n", .{});
    std.debug.print("          }},\n", .{});
    std.debug.print("          else => return err,\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // Example 12: Advanced Use Cases
    std.debug.print("12. Advanced Use Cases\n", .{});
    std.debug.print("-----------------------\n", .{});

    std.debug.print("Common applications:\n", .{});
    std.debug.print("  - Audiobook generation\n", .{});
    std.debug.print("  - Voice assistants and chatbots\n", .{});
    std.debug.print("  - Accessibility features (screen readers)\n", .{});
    std.debug.print("  - Content localization with multiple voices\n", .{});
    std.debug.print("  - Interactive voice response (IVR) systems\n", .{});
    std.debug.print("  - Educational content narration\n", .{});
    std.debug.print("  - Podcast and video voiceovers\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Best practices:\n", .{});
    std.debug.print("  - Use streaming for real-time applications\n", .{});
    std.debug.print("  - Choose appropriate format for your use case\n", .{});
    std.debug.print("  - Test different voices to find the right fit\n", .{});
    std.debug.print("  - Handle long texts by splitting into chunks\n", .{});
    std.debug.print("  - Cache generated audio when possible\n", .{});
    std.debug.print("  - Monitor usage and costs\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example complete!\n", .{});
}
