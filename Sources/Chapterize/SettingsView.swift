import ChapterCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.providerKey) private var provider = "auto"
    @AppStorage(AppSettings.ollamaURLKey) private var ollamaURL = OllamaLLM.defaultURL
    @AppStorage(AppSettings.ollamaModelKey) private var ollamaModel = OllamaLLM.defaultModel
    @AppStorage(AppSettings.openaiURLKey) private var openaiURL = OpenAICompatibleLLM.defaultURL
    @AppStorage(AppSettings.openaiModelKey) private var openaiModel = ""
    @AppStorage(AppSettings.openaiKeyKey) private var openaiKey = ""
    @AppStorage(AppSettings.openaiContextKey) private var openaiContext = 16384
    @AppStorage(AppSettings.styleKey) private var style = Prompts.defaultStyleExamples
    @AppStorage(AppSettings.headerKey) private var includeHeader = true

    @State private var models: [String] = []
    @State private var detectedContext: [String: Int] = [:]
    @State private var status = "Checking…"

    var body: some View {
        Form {
            Section("Model") {
                Picker("Generate with", selection: $provider) {
                    Text("Automatic").tag("auto")
                    Text("Apple Intelligence (on-device)").tag("apple")
                    Text("Ollama").tag("ollama")
                    Text("OpenAI-compatible server").tag("openai")
                }
                Text(appleStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if provider == "openai" {
                Section("OpenAI-compatible server") {
                    TextField("Base URL", text: $openaiURL, prompt: Text(OpenAICompatibleLLM.defaultURL))
                    SecureField("API key", text: $openaiKey, prompt: Text("optional"))
                    modelRow(TextField("Model", text: $openaiModel)) { openaiModel = $0 }
                    TextField("Context (tokens)", value: $openaiContext, format: .number.grouping(.never))
                    statusText
                }
            } else {
                Section("Ollama") {
                    TextField("Server", text: $ollamaURL)
                    modelRow(TextField("Model", text: $ollamaModel)) { ollamaModel = $0 }
                    statusText
                }
            }

            Section("Output") {
                Toggle("Start with a \"Contents:\" line", isOn: $includeHeader)
            }

            Section {
                TextEditor(text: $style)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 150)
                HStack {
                    Text("A few of your own chapter titles, so the model picks up your voice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { style = Prompts.defaultStyleExamples }
                }
            } header: {
                Text("Title style examples")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 700)
        .task(id: provider) { await refresh() }
        .onChange(of: openaiModel) { applyDetectedContext() }
    }

    private func modelRow(_ field: some View, select: @escaping (String) -> Void) -> some View {
        HStack {
            field
            if !models.isEmpty {
                Menu("Models") {
                    ForEach(models, id: \.self) { name in Button(name) { select(name) } }
                }
                .fixedSize()
            }
            Button("Refresh") { Task { await refresh() } }
        }
    }

    private var statusText: some View {
        Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    private var appleStatus: String {
        if let why = AppleIntelligenceLLM.unavailableReason { return "Apple Intelligence: \(why)" }
        return "Apple Intelligence is ready. Automatic uses it first, and falls back to Ollama if it's unavailable."
    }

    private func refresh() async {
        if provider == "openai" { await refreshOpenAI() } else { await refreshOllama() }
    }

    private func refreshOpenAI() async {
        guard let url = OpenAICompatibleLLM.baseURL(from: openaiURL) else {
            status = "Invalid base URL."
            return
        }
        do {
            let list = try await OpenAICompatibleLLM.models(baseURL: url, apiKey: openaiKey)
            models = list.map(\.id)
            detectedContext = Dictionary(list.compactMap { m in m.contextLength.map { (m.id, $0) } },
                                         uniquingKeysWith: { first, _ in first })
            if openaiModel.isEmpty, let first = models.first { openaiModel = first }
            applyDetectedContext()
            let ctx = detectedContext[openaiModel].map { " · \($0.formatted())-token context" } ?? ""
            status = models.isEmpty
                ? "Connected, but the server listed no models. Type the model name."
                : "Connected to \(url.absoluteString) · \(models.count) model\(models.count == 1 ? "" : "s")\(ctx)"
        } catch {
            models = []
            detectedContext = [:]
            status = "Couldn't list models at \(url.absoluteString)/models: \(error.localizedDescription)"
        }
    }

    private func applyDetectedContext() {
        if let ctx = detectedContext[openaiModel] { openaiContext = ctx }
    }

    private func refreshOllama() async {
        let raw = ollamaURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: raw.contains("://") ? raw : "http://\(raw)") else {
            status = "Invalid server URL."
            return
        }
        do {
            models = try await OllamaLLM.installedModels(baseURL: url)
            if models.isEmpty {
                status = "Ollama is running but has no models. Try: ollama pull \(OllamaLLM.defaultModel)"
            } else if !models.contains(ollamaModel) && !models.contains(ollamaModel + ":latest") {
                status = "\(ollamaModel) isn't pulled yet. Run: ollama pull \(ollamaModel)"
            } else {
                status = "Connected · \(models.count) model\(models.count == 1 ? "" : "s") installed"
            }
        } catch {
            models = []
            status = "Ollama not reachable. Install with `brew install ollama`, then `ollama serve` and `ollama pull \(OllamaLLM.defaultModel)`."
        }
    }
}
