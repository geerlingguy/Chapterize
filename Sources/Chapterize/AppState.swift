import AppKit
import ChapterCore
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case processing(String)
        case done
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var output = ""
    @Published var fileName: String?
    @Published var info = ""
    @Published var warnings: [String] = []

    private(set) var currentURL: URL?
    private var task: Task<Void, Never>?

    var isProcessing: Bool {
        if case .processing = phase { return true }
        return false
    }

    var hasOutput: Bool { !output.isEmpty }

    static let srtType = UTType(filenameExtension: "srt") ?? .plainText

    func open(url: URL) {
        task?.cancel()
        currentURL = url
        fileName = url.lastPathComponent
        output = ""
        info = ""
        warnings = []
        phase = .processing("Reading subtitles…")
        NSDocumentController.shared.noteNewRecentDocumentURL(url)

        let onProgress: @Sendable (String) -> Void = { [self] message in
            Task { @MainActor in self.showProgress(message) }
        }

        task = Task { [weak self] in
            do {
                let cues = try SRTParser.parse(url: url)
                let llm = try AppSettings.makeLLM()
                let generator = ChapterGenerator(
                    llm: llm, styleExamples: AppSettings.style, includeHeader: AppSettings.includeHeader)
                let started = Date()
                let result = try await generator.generate(cues: cues, progress: onProgress)
                try Task.checkCancellation()
                guard let self else { return }
                self.output = result.text
                self.warnings = result.warnings
                let secs = Int(Date().timeIntervalSince(started).rounded())
                self.info = "\(result.chapters.count) chapters · \(result.modelName) · \(secs)s"
                self.phase = .done
            } catch is CancellationError {
                // A newer file replaced this one.
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func showProgress(_ message: String) {
        if isProcessing { phase = .processing(message) }
    }

    func regenerate() {
        if let url = currentURL { open(url: url) }
    }

    func presentOpenPanel() {
        guard !isProcessing else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.srtType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an SRT subtitles file"
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func copyOutput() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(output, forType: .string)
    }

    func saveOutput() {
        guard hasOutput else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        if let url = currentURL {
            panel.directoryURL = url.deletingLastPathComponent()
            panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + ".txt"
        } else {
            panel.nameFieldStringValue = "Chapters.txt"
        }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try output.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
