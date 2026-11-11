import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device ~3B Foundation Model (macOS 26+, Apple Intelligence enabled).
/// Already on the Mac, uses no extra RAM budget of its own to speak of, but has a
/// 4,096-token context window, so transcripts are processed in ~1,300-word chunks.
public struct AppleIntelligenceLLM: ChapterLLM {
    public init() {}

    public var displayName: String { "Apple Intelligence" }
    public var wordBudget: Int { 1300 }

    /// nil when the model is ready to use; otherwise a human-readable reason.
    public static var unavailableReason: String? {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This Mac doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is turned off. Turn it on in System Settings › Apple Intelligence & Siri, or switch to Ollama in Settings."
            case .modelNotReady:
                return "The Apple Intelligence model is still downloading. Try again in a bit."
            @unknown default:
                return "Apple Intelligence is unavailable on this Mac."
            }
        }
        #else
        return "This build was compiled without the FoundationModels framework."
        #endif
    }

    public static var isAvailable: Bool { unavailableReason == nil }

    public func complete(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if let why = Self.unavailableReason { throw LLMError.unavailable(why) }
        // Permissive guardrails: we're transforming user-supplied text (a transcript),
        // and tech videos say plenty of things like "FBI", "exploit", "spies"...
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.5))
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                throw LLMError.contextTooLarge
            case .guardrailViolation:
                throw LLMError.refused("guardrail")
            default:
                throw LLMError.server(error.localizedDescription)
            }
        }
        #else
        throw LLMError.unavailable(Self.unavailableReason ?? "Unavailable")
        #endif
    }
}
