import ChapterCore
import Foundation

// Quick way to iterate on prompts against a folder of SRTs without the GUI:
//   swift run chapterize-cli ~/Videos/*.srt
//   swift run chapterize-cli --ollama qwen3:8b "IP KVMs.srt"
//   swift run chapterize-cli --openai http://turnstone:8000/v1 my-model *.srt
// If a matching .txt sits next to the .srt, it's printed alongside for comparison.

var args = Array(CommandLine.arguments.dropFirst())
var llm: any ChapterLLM = AppleIntelligenceLLM()

if let i = args.firstIndex(of: "--ollama") {
    args.remove(at: i)
    var model = OllamaLLM.defaultModel
    if i < args.count, !args[i].lowercased().hasSuffix(".srt") {
        model = args.remove(at: i)
    }
    let url = ProcessInfo.processInfo.environment["OLLAMA_HOST"].flatMap { URL(string: $0) }
        ?? URL(string: OllamaLLM.defaultURL)!
    llm = OllamaLLM(baseURL: url, model: model)
} else if let i = args.firstIndex(of: "--openai"), i + 2 < args.count {
    args.remove(at: i)
    let raw = args.remove(at: i)
    guard let url = OpenAICompatibleLLM.baseURL(from: raw) else {
        print("invalid URL: \(raw)")
        exit(1)
    }
    let env = ProcessInfo.processInfo.environment
    llm = OpenAICompatibleLLM(
        baseURL: url, model: args.remove(at: i),
        apiKey: env["OPENAI_API_KEY"] ?? "",
        contextLength: env["CONTEXT_TOKENS"].flatMap(Int.init) ?? 16384)
} else if let why = AppleIntelligenceLLM.unavailableReason {
    FileHandle.standardError.write("Apple Intelligence unavailable: \(why)\nUse --ollama [model] or --openai <url> <model> instead.\n".data(using: .utf8)!)
    exit(1)
}

guard !args.isEmpty else {
    print("usage: chapterize-cli [--ollama [model] | --openai <url> <model>] file.srt [file2.srt ...]")
    exit(1)
}

for path in args {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    print("==> \(url.lastPathComponent)  [\(llm.displayName)]")
    do {
        let started = Date()
        let cues = try SRTParser.parse(url: url)
        let result = try await ChapterGenerator(llm: llm, includeHeader: false).generate(cues: cues) { msg in
            FileHandle.standardError.write("    \(msg)\n".data(using: .utf8)!)
        }
        print(result.text)
        result.warnings.forEach { print("  ! \($0)") }
        print(String(format: "  (%.1fs)", Date().timeIntervalSince(started)))

        let txt = url.deletingPathExtension().appendingPathExtension("txt")
        if let manual = try? String(contentsOf: txt, encoding: .utf8) {
            print("--- your \(txt.lastPathComponent):")
            print(manual)
        }
    } catch {
        print("  error: \(error.localizedDescription)")
    }
}
