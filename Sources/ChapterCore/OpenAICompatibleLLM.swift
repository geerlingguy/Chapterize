import Foundation

/// Any server speaking the OpenAI chat completions API (vLLM, llama.cpp, LM Studio, MLX, OpenAI…).
public struct OpenAICompatibleLLM: ChapterLLM {
    public static let defaultURL = "http://localhost:8000/v1"

    public let baseURL: URL
    public let model: String
    public let apiKey: String
    public let contextLength: Int

    public init(baseURL: URL, model: String, apiKey: String = "", contextLength: Int = 16384) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.contextLength = contextLength
    }

    public var displayName: String { "\(baseURL.host ?? "server") · \(model)" }
    public var wordBudget: Int { max(1000, Int(Double(contextLength - 2500) / 1.6)) }

    /// Accepts `host:port`, `http://host:port`, or a full `…/v1` URL.
    public static func baseURL(from raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if !s.contains("://") { s = "http://" + s }
        if s.hasSuffix("/chat/completions") { s.removeLast("/chat/completions".count) }
        while s.hasSuffix("/") { s.removeLast() }
        guard var url = URL(string: s), url.host != nil else { return nil }
        if url.path.isEmpty { url.appendPathComponent("v1") }
        return url
    }

    public func complete(instructions: String, prompt: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.5,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt],
            ],
        ]
        var request = Self.request(baseURL.appendingPathComponent("chat/completions"), apiKey: apiKey)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 900
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let json = try await Self.send(request, baseURL: baseURL)
        let choices = json["choices"] as? [[String: Any]]
        guard let message = choices?.first?["message"] as? [String: Any] else {
            throw LLMError.server("Unexpected response from \(baseURL.absoluteString)")
        }
        // Reasoning models may return only `reasoning_content`; an empty reply triggers the format retry.
        return ChapterText.stripThinking(message["content"] as? String ?? "")
    }

    public struct ServerModel: Sendable {
        public let id: String
        public let contextLength: Int?
    }

    /// Models from `GET /models` (for the Settings picker), with context length when the server reports it.
    public static func models(baseURL: URL, apiKey: String) async throws -> [ServerModel] {
        var request = request(baseURL.appendingPathComponent("models"), apiKey: apiKey)
        request.timeoutInterval = 5
        let json = try await send(request, baseURL: baseURL)
        let data = json["data"] as? [[String: Any]] ?? []
        return data.compactMap { m -> ServerModel? in
            guard let id = m["id"] as? String else { return nil }
            // vLLM: max_model_len; LM Studio, OpenRouter, others: context_length.
            let ctx = (m["max_model_len"] ?? m["context_length"] ?? m["max_context_length"]) as? Int
            return ServerModel(id: id, contextLength: ctx)
        }
        .sorted { $0.id < $1.id }
    }

    private static func request(_ url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private static func send(_ request: URLRequest, baseURL: URL) async throws -> [String: Any] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code != .cancelled && error.code != .timedOut {
            throw LLMError.unreachable(baseURL)
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // OpenAI: {"error": {"message"}}, Ollama: {"error": "…"}, vLLM: {"message"}.
            let msg = (json["error"] as? [String: Any])?["message"] as? String
                ?? json["error"] as? String
                ?? json["message"] as? String
                ?? "HTTP \(http.statusCode)"
            let lower = msg.lowercased()
            if lower.contains("context") || lower.contains("too many tokens") || lower.contains("maximum") {
                throw LLMError.contextTooLarge
            }
            throw LLMError.server(msg)
        }
        return json
    }
}
