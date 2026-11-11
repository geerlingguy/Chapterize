import Foundation

/// A local model served by Ollama (https://ollama.com). Default qwen3:8b
/// (~5 GB at Q4) fits comfortably in 8–12 GB with a 16K context, and handles
/// a ~30 minute transcript in a single pass.
public struct OllamaLLM: ChapterLLM {
    public static let defaultURL = "http://localhost:11434"
    public static let defaultModel = "qwen3:8b"

    public let baseURL: URL
    public let model: String
    public let contextLength: Int

    public init(baseURL: URL, model: String, contextLength: Int = 16384) {
        self.baseURL = baseURL
        self.model = model
        self.contextLength = contextLength
    }

    private static let unreachableCodes: [URLError.Code] = [
        .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet,
    ]

    public var displayName: String { "Ollama · \(model)" }
    // ~1.35 tokens/word + timestamps; leave room for instructions and output.
    public var wordBudget: Int { max(1000, Int(Double(contextLength - 2500) / 1.6)) }

    public func complete(instructions: String, prompt: String) async throws -> String {
        do {
            return try await chat(instructions: instructions, prompt: prompt, sendThink: true)
        } catch LLMError.server(let msg) where msg.lowercased().contains("think") {
            // Older Ollama / models that reject the `think` flag.
            return try await chat(instructions: instructions, prompt: prompt, sendThink: false)
        }
    }

    private func chat(instructions: String, prompt: String, sendThink: Bool) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt],
            ],
            "options": ["temperature": 0.5, "num_ctx": contextLength],
        ]
        if sendThink { body["think"] = false }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 900
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where Self.unreachableCodes.contains(error.code) {
            throw LLMError.ollamaNotRunning(baseURL)
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = json?["error"] as? String ?? "HTTP \(http.statusCode)"
            if http.statusCode == 404 || msg.lowercased().contains("not found") {
                throw LLMError.ollamaModelMissing(model)
            }
            throw LLMError.server(msg)
        }
        guard let message = json?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.server("Unexpected response from Ollama")
        }
        return ChapterText.stripThinking(content)
    }

    /// Models already pulled into Ollama (for the Settings picker).
    public static func installedModels(baseURL: URL) async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["models"] as? [[String: Any]] ?? []
        return models.compactMap { $0["name"] as? String }.sorted()
    }
}
