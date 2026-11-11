import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var state: AppState
    @State private var isTargeted = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 18) {
            dropZone
                .frame(minWidth: 260, idealWidth: state.hasOutput ? 300 : nil,
                       maxWidth: state.hasOutput ? 320 : .infinity)
            if state.hasOutput {
                outputPanel
                    .frame(minWidth: 360, maxWidth: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 360)
        .animation(.spring(duration: 0.35), value: state.hasOutput)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.03))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [11, 8]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.45))

            VStack(spacing: 14) {
                switch state.phase {
                case .processing(let detail):
                    ProgressView()
                        .controlSize(.large)
                    Text("processing srt")
                        .font(.title3.weight(.semibold))
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let name = state.fileName {
                        Text(name).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    HStack {
                        if state.currentURL != nil {
                            Button("Try Again") { state.regenerate() }
                        }
                        Button("Settings…") { _ = NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil) }
                    }
                    .padding(.top, 4)
                    prompt.padding(.top, 8)
                default:
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 52, weight: .regular))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                    prompt
                }
            }
            .padding(28)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.presentOpenPanel() }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            let appState = state
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in appState.open(url: url) }
            }
            return true
        }
        .help("Drop an .srt file, or click to choose one")
    }

    private var prompt: some View {
        Text("drag an SRT file here to generate chapters")
            .font(.title3)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Output

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.fileName ?? "Chapters")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(state.info)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TextEditor(text: $state.output)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25)))

            ForEach(state.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button {
                    state.regenerate()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .disabled(state.isProcessing)
                Spacer()
                Button("Save…") { state.saveOutput() }
                Button {
                    state.copyOutput()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)
                .help("Copy chapters (⇧⌘C)")
            }
        }
    }
}
