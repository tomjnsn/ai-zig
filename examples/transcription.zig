// Transcription Example
//
// This example demonstrates how to use speech-to-text transcription
// with various providers (Groq Whisper, Deepgram, AssemblyAI).

const std = @import("std");
const ai = @import("ai");
const groq = @import("groq");
const deepgram = @import("deepgram");
const assemblyai = @import("assemblyai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Transcription Example\n", .{});
    std.debug.print("=====================\n\n", .{});

    // Example 1: Groq Whisper transcription
    std.debug.print("1. Groq Whisper Transcription\n", .{});
    std.debug.print("------------------------------\n", .{});
    {
        var provider = groq.createGroq(allocator);
        defer provider.deinit();

        // Create a transcription model
        var model = provider.transcriptionModel("whisper-large-v3-turbo");
        std.debug.print("Provider: {s}\n", .{provider.getProvider()});
        std.debug.print("Model: {s}\n", .{model.getModelId()});
        std.debug.print("\n", .{});

        std.debug.print("Available Groq Whisper models:\n", .{});
        std.debug.print("  - whisper-large-v3-turbo (fastest, 4x faster than v3)\n", .{});
        std.debug.print("  - whisper-large-v3 (most accurate)\n", .{});
        std.debug.print("\n", .{});

        // Demonstrate transcription API
        std.debug.print("Basic transcription call:\n", .{});
        std.debug.print("  const result = try ai.transcribe(allocator, .{{\n", .{});
        std.debug.print("      .model = &model,\n", .{});
        std.debug.print("      .audio = .{{ .url = \"https://example.com/audio.mp3\" }},\n", .{});
        std.debug.print("  }});\n", .{});
        std.debug.print("  defer result.deinit(allocator);\n", .{});
        std.debug.print("\n", .{});
    }

    // Example 2: Audio source options
    std.debug.print("2. Audio Source Options\n", .{});
    std.debug.print("------------------------\n", .{});
    std.debug.print("The transcription API supports multiple audio input formats:\n\n", .{});

    std.debug.print("From URL:\n", .{});
    std.debug.print("  .audio = .{{ .url = \"https://example.com/meeting.wav\" }}\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("From file path:\n", .{});
    std.debug.print("  .audio = .{{ .file = \"/path/to/recording.mp3\" }}\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("From raw audio data:\n", .{});
    std.debug.print("  .audio = .{{ .data = .{{\n", .{});
    std.debug.print("      .data = audio_bytes,\n", .{});
    std.debug.print("      .mime_type = \"audio/wav\",\n", .{});
    std.debug.print("  }} }}\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Supported audio formats:\n", .{});
    std.debug.print("  - MP3, WAV, M4A, FLAC, OGG, WEBM\n", .{});
    std.debug.print("  - Most providers support up to 25MB file size\n", .{});
    std.debug.print("\n", .{});

    // Example 3: Transcription options
    std.debug.print("3. Transcription Options\n", .{});
    std.debug.print("------------------------\n", .{});
    {
        var provider = groq.createGroq(allocator);
        defer provider.deinit();
        var model = provider.transcriptionModel("whisper-large-v3");

        std.debug.print("Basic transcription with options:\n", .{});
        std.debug.print("  const result = try ai.transcribe(allocator, .{{\n", .{});
        std.debug.print("      .model = &model,\n", .{});
        std.debug.print("      .audio = .{{ .url = \"https://example.com/audio.mp3\" }},\n", .{});
        std.debug.print("      .language = \"en\",  // ISO 639-1 code\n", .{});
        std.debug.print("      .prompt = \"Technical discussion about AI\",  // Guide transcription\n", .{});
        std.debug.print("      .temperature = 0.0,  // Lower = more deterministic\n", .{});
        std.debug.print("  }});\n", .{});
        std.debug.print("\n", .{});

        std.debug.print("With timestamps and diarization:\n", .{});
        std.debug.print("  const result = try ai.transcribe(allocator, .{{\n", .{});
        std.debug.print("      .model = &model,\n", .{});
        std.debug.print("      .audio = .{{ .url = \"https://example.com/meeting.mp3\" }},\n", .{});
        std.debug.print("      .timestamps = .word,  // .word or .segment\n", .{});
        std.debug.print("      .diarization = true,  // Identify speakers\n", .{});
        std.debug.print("      .max_speakers = 4,  // Expected number of speakers\n", .{});
        std.debug.print("  }});\n", .{});
        std.debug.print("\n", .{});

        std.debug.print("Supported languages (ISO 639-1 codes):\n", .{});
        std.debug.print("  - en (English), es (Spanish), fr (French), de (German)\n", .{});
        std.debug.print("  - zh (Chinese), ja (Japanese), ko (Korean), ru (Russian)\n", .{});
        std.debug.print("  - it (Italian), pt (Portuguese), nl (Dutch), pl (Polish)\n", .{});
        std.debug.print("  - And many more... (100+ languages supported)\n", .{});
        std.debug.print("\n", .{});
    }

    // Example 4: Working with results
    std.debug.print("4. Working with Transcription Results\n", .{});
    std.debug.print("--------------------------------------\n", .{});
    std.debug.print("The TranscribeResult contains:\n\n", .{});

    std.debug.print("Basic text:\n", .{});
    std.debug.print("  std.debug.print(\"Transcription: {{s}}\\n\", .{{result.text}});\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Segments with timestamps:\n", .{});
    std.debug.print("  if (result.segments) |segments| {{\n", .{});
    std.debug.print("      for (segments) |segment| {{\n", .{});
    std.debug.print("          std.debug.print(\"[{{d:.2}s - {{d:.2}s}] {{s}}\\n\", .{{\n", .{});
    std.debug.print("              segment.start,\n", .{});
    std.debug.print("              segment.end,\n", .{});
    std.debug.print("              segment.text,\n", .{});
    std.debug.print("          }});\n", .{});
    std.debug.print("          \n", .{});
    std.debug.print("          // Speaker information\n", .{});
    std.debug.print("          if (segment.speaker) |speaker| {{\n", .{});
    std.debug.print("              std.debug.print(\"  Speaker: {{s}}\\n\", .{{speaker}});\n", .{});
    std.debug.print("          }}\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Word-level timestamps:\n", .{});
    std.debug.print("  if (result.words) |words| {{\n", .{});
    std.debug.print("      for (words) |word| {{\n", .{});
    std.debug.print("          std.debug.print(\"{{s}} [{{d:.2}s-{{d:.2}s}]\", .{{\n", .{});
    std.debug.print("              word.word,\n", .{});
    std.debug.print("              word.start,\n", .{});
    std.debug.print("              word.end,\n", .{});
    std.debug.print("          }});\n", .{});
    std.debug.print("          \n", .{});
    std.debug.print("          // Confidence score\n", .{});
    std.debug.print("          if (word.confidence) |conf| {{\n", .{});
    std.debug.print("              std.debug.print(\" ({{d:.2}})\", .{{conf}});\n", .{});
    std.debug.print("          }}\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Metadata and usage:\n", .{});
    std.debug.print("  std.debug.print(\"Duration: {{d}}s\\n\", .{{result.duration_seconds}});\n", .{});
    std.debug.print("  std.debug.print(\"Language: {{s}}\\n\", .{{result.language}});\n", .{});
    std.debug.print("  std.debug.print(\"Model: {{s}}\\n\", .{{result.response.model_id}});\n", .{});
    std.debug.print("\n", .{});

    // Example 5: Deepgram transcription
    std.debug.print("5. Deepgram Transcription\n", .{});
    std.debug.print("--------------------------\n", .{});
    {
        var provider = deepgram.createDeepgram(allocator);
        defer provider.deinit();

        // Create a transcription model
        var model = provider.transcriptionModel(deepgram.TranscriptionModels.nova_2);
        std.debug.print("Provider: {s}\n", .{model.getProvider()});
        std.debug.print("Model: {s}\n", .{model.getModelId()});
        std.debug.print("\n", .{});

        std.debug.print("Available Deepgram models:\n", .{});
        std.debug.print("  Nova 2 (best accuracy):\n", .{});
        std.debug.print("    - nova-2 (general purpose)\n", .{});
        std.debug.print("    - nova-2-meeting (optimized for meetings)\n", .{});
        std.debug.print("    - nova-2-phonecall (optimized for phone calls)\n", .{});
        std.debug.print("    - nova-2-medical (medical terminology)\n", .{});
        std.debug.print("    - nova-2-finance (financial terminology)\n", .{});
        std.debug.print("  Enhanced (balanced):\n", .{});
        std.debug.print("    - enhanced (good accuracy, faster)\n", .{});
        std.debug.print("  Base (fastest):\n", .{});
        std.debug.print("    - base (basic transcription)\n", .{});
        std.debug.print("  Whisper:\n", .{});
        std.debug.print("    - whisper (OpenAI Whisper on Deepgram)\n", .{});
        std.debug.print("\n", .{});

        std.debug.print("Deepgram features:\n", .{});
        std.debug.print("  - Smart formatting (punctuation, capitalization)\n", .{});
        std.debug.print("  - Speaker diarization (identify speakers)\n", .{});
        std.debug.print("  - Profanity filtering\n", .{});
        std.debug.print("  - Entity detection (names, dates, numbers)\n", .{});
        std.debug.print("  - Topic detection\n", .{});
        std.debug.print("  - Sentiment analysis\n", .{});
        std.debug.print("  - Multi-channel audio support\n", .{});
        std.debug.print("\n", .{});
    }

    // Example 6: AssemblyAI transcription
    std.debug.print("6. AssemblyAI Transcription\n", .{});
    std.debug.print("----------------------------\n", .{});
    {
        var provider = assemblyai.createAssemblyAI(allocator);
        defer provider.deinit();

        // Create a transcription model
        var model = provider.transcriptionModel(assemblyai.TranscriptionModels.best);
        std.debug.print("Provider: {s}\n", .{model.getProvider()});
        std.debug.print("Model: {s}\n", .{model.getModelId()});
        std.debug.print("\n", .{});

        std.debug.print("Available AssemblyAI models:\n", .{});
        std.debug.print("  - best (highest accuracy, slower)\n", .{});
        std.debug.print("  - nano (fastest, good accuracy)\n", .{});
        std.debug.print("  - conformer-2 (balanced)\n", .{});
        std.debug.print("\n", .{});

        std.debug.print("AssemblyAI features:\n", .{});
        std.debug.print("  - Speaker diarization with labels\n", .{});
        std.debug.print("  - Auto-chapters (segment long audio)\n", .{});
        std.debug.print("  - Auto-highlights (key moments)\n", .{});
        std.debug.print("  - Sentiment analysis\n", .{});
        std.debug.print("  - Entity detection\n", .{});
        std.debug.print("  - Content safety detection\n", .{});
        std.debug.print("  - PII redaction (remove sensitive info)\n", .{});
        std.debug.print("  - Summarization\n", .{});
        std.debug.print("  - Custom vocabulary (word boost)\n", .{});
        std.debug.print("\n", .{});
    }

    // Example 7: Output formats
    std.debug.print("7. Output Formats\n", .{});
    std.debug.print("------------------\n", .{});
    std.debug.print("Transcription supports multiple output formats:\n\n", .{});

    std.debug.print("JSON (default):\n", .{});
    std.debug.print("  .format = .json\n", .{});
    std.debug.print("  Returns structured data with all metadata\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Plain text:\n", .{});
    std.debug.print("  .format = .text\n", .{});
    std.debug.print("  Returns just the transcribed text\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("SRT (SubRip):\n", .{});
    std.debug.print("  .format = .srt\n", .{});
    std.debug.print("  Returns subtitle format with timestamps\n", .{});
    std.debug.print("  Can be parsed with ai.parseSrt()\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("VTT (WebVTT):\n", .{});
    std.debug.print("  .format = .vtt\n", .{});
    std.debug.print("  Returns web video text tracks format\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Verbose JSON:\n", .{});
    std.debug.print("  .format = .verbose_json\n", .{});
    std.debug.print("  Returns detailed JSON with word timestamps\n", .{});
    std.debug.print("\n", .{});

    // Example 8: Use cases
    std.debug.print("8. Common Use Cases\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("  - Meeting transcription: Record and transcribe meetings with speaker labels\n", .{});
    std.debug.print("  - Podcast transcription: Generate text transcripts for searchability and SEO\n", .{});
    std.debug.print("  - Customer support: Transcribe support calls for analysis and training\n", .{});
    std.debug.print("  - Video subtitles: Generate SRT/VTT files for video content\n", .{});
    std.debug.print("  - Voice commands: Convert speech to text for command processing\n", .{});
    std.debug.print("  - Accessibility: Provide text alternatives for audio content\n", .{});
    std.debug.print("  - Content analysis: Extract insights from audio data\n", .{});
    std.debug.print("  - Interview transcription: Convert interviews to searchable text\n", .{});
    std.debug.print("\n", .{});

    // Example 9: Provider comparison
    std.debug.print("9. Provider Comparison\n", .{});
    std.debug.print("----------------------\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("| Provider   | Best For                           | Key Features          |\n", .{});
    std.debug.print("|------------|------------------------------------|-----------------------|\n", .{});
    std.debug.print("| Groq       | Fast inference, OpenAI Whisper     | Ultra-fast, accurate  |\n", .{});
    std.debug.print("| Deepgram   | Real-time, specialized domains     | Smart formatting, NLU |\n", .{});
    std.debug.print("| AssemblyAI | Advanced features, summaries       | Auto-chapters, PII    |\n", .{});
    std.debug.print("| OpenAI     | General purpose, reliable          | Whisper large-v3      |\n", .{});
    std.debug.print("\n", .{});

    // Example 10: Error handling
    std.debug.print("10. Error Handling\n", .{});
    std.debug.print("-------------------\n", .{});
    std.debug.print("Transcription can fail with various errors:\n\n", .{});

    std.debug.print("  const result = ai.transcribe(allocator, .{{\n", .{});
    std.debug.print("      .model = &model,\n", .{});
    std.debug.print("      .audio = .{{ .url = \"https://example.com/audio.mp3\" }},\n", .{});
    std.debug.print("  }}) catch |err| switch (err) {{\n", .{});
    std.debug.print("      error.InvalidAudio => {{\n", .{});
    std.debug.print("          std.debug.print(\"Audio file is invalid or empty\\n\", .{{}});\n", .{});
    std.debug.print("          return err;\n", .{});
    std.debug.print("      }},\n", .{});
    std.debug.print("      error.AudioTooLong => {{\n", .{});
    std.debug.print("          std.debug.print(\"Audio exceeds maximum length\\n\", .{{}});\n", .{});
    std.debug.print("          return err;\n", .{});
    std.debug.print("      }},\n", .{});
    std.debug.print("      error.UnsupportedFormat => {{\n", .{});
    std.debug.print("          std.debug.print(\"Audio format not supported\\n\", .{{}});\n", .{});
    std.debug.print("          return err;\n", .{});
    std.debug.print("      }},\n", .{});
    std.debug.print("      error.NetworkError => {{\n", .{});
    std.debug.print("          std.debug.print(\"Network error, retrying...\\n\", .{{}});\n", .{});
    std.debug.print("          return err;\n", .{});
    std.debug.print("      }},\n", .{});
    std.debug.print("      else => return err,\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Example complete!\n", .{});
}
