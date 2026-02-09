const std = @import("std");

// This example demonstrates correct lifetime management for vtable-based
// interfaces (LanguageModelV3, EmbeddingModelV3, HttpClient, etc.).

// ============================================================
// CORRECT: The model outlives the interface
// ============================================================
//
//   var provider = createAnthropic(allocator);
//   defer provider.deinit();
//
//   var model = provider.messages("claude-sonnet-4-5");
//   // model.asLanguageModel() borrows a pointer to model's vtable + impl.
//   // The returned LanguageModelV3 is valid as long as `model` is alive.
//   const iface = model.asLanguageModel();
//   _ = iface;  // safe to use here
//
// ============================================================
// INCORRECT: Dangling pointer - model goes out of scope
// ============================================================
//
//   fn getModel(provider: *AnthropicProvider) LanguageModelV3 {
//       var model = provider.messages("claude-sonnet-4-5");
//       return model.asLanguageModel();
//       // BUG: `model` is stack-allocated and destroyed when this
//       // function returns. The returned LanguageModelV3.impl now
//       // points to freed stack memory.
//   }
//
// ============================================================
// CORRECT: Keep the concrete model alive alongside the interface
// ============================================================
//
//   const ModelHandle = struct {
//       model: AnthropicMessagesLanguageModel,
//
//       pub fn asLanguageModel(self: *ModelHandle) LanguageModelV3 {
//           return self.model.asLanguageModel();
//       }
//   };
//
//   var handle = ModelHandle{ .model = provider.messages("claude-sonnet-4-5") };
//   const iface = handle.asLanguageModel();
//   // iface is valid as long as handle is alive
//   _ = iface;
//
// ============================================================
// Key Rules
// ============================================================
//
// 1. The concrete implementation (model, http client, etc.) MUST outlive
//    the type-erased interface (LanguageModelV3, HttpClient, etc.).
//
// 2. The vtable pointer should reference a file-level `const` with static
//    lifetime. All implementations in this SDK follow this pattern.
//
// 3. Never return a type-erased interface from a function where the
//    concrete implementation is a local variable.
//
// 4. When storing interfaces in structs, also store (or reference) the
//    concrete implementation to keep it alive.

pub fn main() void {
    // This file is documentation only. See the comments above for
    // lifetime management patterns.
}
