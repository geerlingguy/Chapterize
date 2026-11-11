import Foundation

public struct GenerationResult: Sendable {
    public let chapters: [Chapter]
    public let text: String
    public let duration: Double
    public let modelName: String
    public let warnings: [String]
}

/// SRT cues -> sentence-aligned segments -> chunked model calls -> draft
/// chapters snapped to real timestamps -> (optional) polish pass -> YouTube rules.
public struct ChapterGenerator: Sendable {
    public let llm: any ChapterLLM
    public let styleExamples: String
    public let includeHeader: Bool

    public init(llm: any ChapterLLM, styleExamples: String = Prompts.defaultStyleExamples, includeHeader: Bool = true) {
        self.llm = llm
        self.styleExamples = styleExamples.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Prompts.defaultStyleExamples : styleExamples
        self.includeHeader = includeHeader
    }

    public func generate(cues: [Cue], progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> GenerationResult {
        let duration = cues.map(\.end).max() ?? 0
        let useHours = duration >= 3600
        let timeFormat = useHours ? "HH:MM:SS" : "MM:SS"
        let videoLength = Timestamp.format(duration, useHours: useHours)
        let target = ChapterRules.targetCount(duration: duration)
        let instructions = Prompts.instructions(styleExamples: styleExamples, timeFormat: timeFormat)

        let segments = Transcript.segments(from: cues)
        var pending = Transcript.chunks(segments, wordBudget: llm.wordBudget)
        var drafts: [Chapter] = []
        var warnings: [String] = []
        var done = 0
        var splits = 0

        while !pending.isEmpty {
            try Task.checkCancellation()
            let chunk = pending.removeFirst()
            let total = done + 1 + pending.count
            progress(total > 1 ? "\(llm.displayName): reading part \(done + 1) of \(total)…" : "\(llm.displayName): reading transcript…")

            let share = (chunk.end - chunk.start) / max(duration, 1)
            let prompt = Prompts.chunkPrompt(
                transcript: Transcript.promptText(for: chunk, useHours: useHours),
                part: done + 1, of: total,
                chunkStart: Timestamp.format(chunk.start, useHours: useHours),
                chunkEnd: Timestamp.format(chunk.end, useHours: useHours),
                videoLength: videoLength,
                chapterCount: max(1, Int((Double(target) * share).rounded())),
                timeFormat: timeFormat)

            let reply: String
            do {
                reply = try await completeWithRetry(instructions: instructions, prompt: prompt)
            } catch LLMError.contextTooLarge where splits < 6 && chunk.segments.count > 1 {
                splits += 1
                pending.insert(contentsOf: Transcript.halve(chunk), at: 0)
                continue
            } catch LLMError.refused(let why) where total > 1 {
                // Don't lose the whole video over one touchy section.
                warnings.append("Skipped \(Timestamp.format(chunk.start, useHours: useHours))–\(Timestamp.format(chunk.end, useHours: useHours)): model declined (\(why)).")
                done += 1
                continue
            }

            let allowed = chunk.segments.map(\.start)
            var found = ChapterRules.snap(ChapterText.parse(reply), to: allowed,
                                          lower: chunk.start, upper: chunk.end)
            if done == 0, !found.isEmpty, !found.contains(where: { $0.start == 0 }) {
                found.sort { $0.start < $1.start }
                found[0].start = 0
            }
            drafts += found
            done += 1
        }

        var chapters = ChapterRules.normalize(drafts, duration: duration)
        guard !chapters.isEmpty else { throw LLMError.noChapters }

        // Multiple chunks were titled in isolation: one more pass to dedupe and
        // even out the titles. Only timestamps from the drafts are allowed.
        if done > 1 {
            progress("\(llm.displayName): polishing chapter titles…")
            let draftText = ChapterText.render(chapters, useHours: useHours, includeHeader: false)
            let prompt = Prompts.polishPrompt(
                drafts: draftText,
                minCount: max(3, target - 2), maxCount: target + 2,
                videoLength: videoLength, timeFormat: timeFormat)
            if let reply = try? await completeWithRetry(instructions: instructions, prompt: prompt) {
                let polished = ChapterRules.normalize(
                    ChapterRules.snap(ChapterText.parse(reply), to: chapters.map(\.start),
                                      lower: 0, upper: duration, slop: 5),
                    duration: duration)
                if polished.count >= min(3, chapters.count) { chapters = polished }
            } else {
                warnings.append("Polish pass failed; showing the per-section drafts.")
            }
        }

        if chapters.count < 3 {
            warnings.append("YouTube needs at least 3 chapters (and the first at 00:00) to show them.")
        }

        return GenerationResult(
            chapters: chapters,
            text: ChapterText.render(chapters, useHours: useHours, includeHeader: includeHeader),
            duration: duration,
            modelName: llm.displayName,
            warnings: warnings)
    }

    /// One retry with a format nudge if the reply had no parseable lines.
    private func completeWithRetry(instructions: String, prompt: String) async throws -> String {
        let first = try await llm.complete(instructions: instructions, prompt: prompt)
        if !ChapterText.parse(first).isEmpty { return first }
        try Task.checkCancellation()
        return try await llm.complete(instructions: instructions, prompt: prompt + Prompts.retryNudge)
    }
}
