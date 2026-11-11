import ChapterCore
import Foundation

enum AppSettings {
    static let providerKey = "provider"         // "auto" | "apple" | "ollama" | "openai"
    static let ollamaURLKey = "ollamaURL"
    static let ollamaModelKey = "ollamaModel"
    static let openaiURLKey = "openaiURL"
    static let openaiModelKey = "openaiModel"
    static let openaiKeyKey = "openaiAPIKey"
    static let openaiContextKey = "openaiContext"
    static let styleKey = "styleExamples"
    static let headerKey = "includeHeader"

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            providerKey: "auto",
            ollamaURLKey: OllamaLLM.defaultURL,
            ollamaModelKey: OllamaLLM.defaultModel,
            openaiURLKey: OpenAICompatibleLLM.defaultURL,
            openaiModelKey: "",
            openaiKeyKey: "",
            openaiContextKey: 16384,
            styleKey: Prompts.defaultStyleExamples,
            headerKey: true,
        ])
    }

    static var style: String { defaults.string(forKey: styleKey) ?? Prompts.defaultStyleExamples }
    static var includeHeader: Bool { defaults.bool(forKey: headerKey) }

    static func makeLLM() throws -> any ChapterLLM {
        let provider = defaults.string(forKey: providerKey) ?? "auto"
        switch provider {
        case "apple":
            if let why = AppleIntelligenceLLM.unavailableReason { throw LLMError.unavailable(why) }
            return AppleIntelligenceLLM()
        case "ollama":
            return try ollama()
        case "openai":
            return try openAI()
        default:
            if AppleIntelligenceLLM.isAvailable { return AppleIntelligenceLLM() }
            return try ollama()
        }
    }

    private static func ollama() throws -> OllamaLLM {
        let raw = (defaults.string(forKey: ollamaURLKey) ?? OllamaLLM.defaultURL)
            .trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: raw.contains("://") ? raw : "http://\(raw)") else {
            throw LLMError.unavailable("Invalid Ollama URL: \(raw)")
        }
        let model = (defaults.string(forKey: ollamaModelKey) ?? "").trimmingCharacters(in: .whitespaces)
        return OllamaLLM(baseURL: url, model: model.isEmpty ? OllamaLLM.defaultModel : model)
    }

    private static func openAI() throws -> OpenAICompatibleLLM {
        let raw = defaults.string(forKey: openaiURLKey) ?? ""
        guard let url = OpenAICompatibleLLM.baseURL(from: raw) else {
            throw LLMError.unavailable("Invalid server URL: \(raw)")
        }
        let model = (defaults.string(forKey: openaiModelKey) ?? "").trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else {
            throw LLMError.unavailable("Pick a model for the OpenAI-compatible server in Settings.")
        }
        return OpenAICompatibleLLM(
            baseURL: url, model: model,
            apiKey: (defaults.string(forKey: openaiKeyKey) ?? "").trimmingCharacters(in: .whitespaces),
            contextLength: max(4096, defaults.integer(forKey: openaiContextKey)))
    }
}
