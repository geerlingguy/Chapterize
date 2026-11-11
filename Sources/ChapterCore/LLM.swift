import Foundation

/// Anything that can turn (instructions, prompt) into text.
public protocol ChapterLLM: Sendable {
    var displayName: String { get }
    /// Max transcript words per call; longer transcripts get chunked.
    var wordBudget: Int { get }
    func complete(instructions: String, prompt: String) async throws -> String
}

public enum LLMError: LocalizedError {
    case contextTooLarge
    case unavailable(String)
    case ollamaNotRunning(URL)
    case ollamaModelMissing(String)
    case unreachable(URL)
    case server(String)
    case refused(String)
    case noChapters

    public var errorDescription: String? {
        switch self {
        case .contextTooLarge:
            return "The transcript chunk was too large for the model's context window."
        case .unavailable(let why):
            return why
        case .ollamaNotRunning(let url):
            return "Couldn't reach Ollama at \(url.absoluteString). Is it running? (brew install ollama && ollama serve)"
        case .ollamaModelMissing(let model):
            return "Ollama doesn't have \(model) yet. Run: ollama pull \(model)"
        case .unreachable(let url):
            return "Couldn't reach \(url.absoluteString). Is the server running?"
        case .server(let msg):
            return "Model error: \(msg)"
        case .refused(let msg):
            return "The model declined to process this transcript (\(msg)). Try another model in Settings."
        case .noChapters:
            return "The model didn't return any usable chapter lines. Try Regenerate."
        }
    }
}
