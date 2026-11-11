import Foundation

/// A few cues merged into a sentence-aligned chunk of speech (~5–15s).
/// Segment start times are the only timestamps the model gets to pick from.
public struct Segment: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let text: String
    public var wordCount: Int { text.split(separator: " ").count }
}

/// A window of segments small enough to fit in one model call.
public struct TranscriptChunk: Sendable {
    public let segments: [Segment]
    public var start: Double { segments.first?.start ?? 0 }
    public var end: Double { segments.last?.end ?? 0 }
    public var wordCount: Int { segments.reduce(0) { $0 + $1.wordCount } }
}

public enum Transcript {
    /// Merge cues into segments that start at sentence boundaries. 5–15s keeps
    /// chapter starts within a few seconds of where the topic actually turns,
    /// without spending too many tokens on timestamps.
    public static func segments(from cues: [Cue], minDuration: Double = 5, maxDuration: Double = 15) -> [Segment] {
        var result: [Segment] = []
        var curStart: Double?
        var curEnd: Double = 0
        var curText: [String] = []

        func flush() {
            if let s = curStart, !curText.isEmpty {
                result.append(Segment(start: s, end: curEnd, text: curText.joined(separator: " ")))
            }
            curStart = nil
            curText = []
        }

        for cue in cues {
            if let s = curStart {
                let elapsed = cue.start - s
                let gap = cue.start - curEnd
                let sentenceDone = endsSentence(curText.last ?? "")
                if elapsed >= maxDuration || gap > 3 || (elapsed >= minDuration && sentenceDone) {
                    flush()
                }
            }
            if curStart == nil { curStart = cue.start }
            curEnd = max(curEnd, cue.end)
            curText.append(cue.text)
        }
        flush()
        return result
    }

    /// Split segments into chunks of at most `wordBudget` words, keeping
    /// chunks roughly equal in size.
    public static func chunks(_ segments: [Segment], wordBudget: Int) -> [TranscriptChunk] {
        let total = segments.reduce(0) { $0 + $1.wordCount }
        guard total > wordBudget, segments.count > 1 else {
            return [TranscriptChunk(segments: segments)]
        }
        let count = Int((Double(total) / Double(wordBudget)).rounded(.up))
        let target = Double(total) / Double(count)

        var chunks: [TranscriptChunk] = []
        var current: [Segment] = []
        var words = 0
        for seg in segments {
            if !current.isEmpty, Double(words + seg.wordCount) > target * 1.08,
               chunks.count < count - 1 {
                chunks.append(TranscriptChunk(segments: current))
                current = []
                words = 0
            }
            current.append(seg)
            words += seg.wordCount
        }
        if !current.isEmpty { chunks.append(TranscriptChunk(segments: current)) }
        return chunks
    }

    /// Split one chunk in half (used when a model's context window overflows).
    public static func halve(_ chunk: TranscriptChunk) -> [TranscriptChunk] {
        guard chunk.segments.count > 1 else { return [chunk] }
        let mid = chunk.segments.count / 2
        return [
            TranscriptChunk(segments: Array(chunk.segments[..<mid])),
            TranscriptChunk(segments: Array(chunk.segments[mid...])),
        ]
    }

    static func endsSentence(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: " \"'”’)]"))
        guard let last = trimmed.last else { return false }
        return ".?!…".contains(last)
    }

    /// Render a chunk as `[MM:SS] text` lines for the prompt.
    public static func promptText(for chunk: TranscriptChunk, useHours: Bool) -> String {
        chunk.segments
            .map { "[\(Timestamp.format($0.start, useHours: useHours))] \($0.text)" }
            .joined(separator: "\n")
    }
}

public enum Timestamp {
    public static func format(_ seconds: Double, useHours: Bool) -> String {
        let t = max(0, Int(seconds.rounded(.down)))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return useHours
            ? String(format: "%02ld:%02ld:%02ld", h, m, s)
            : String(format: "%02ld:%02ld", h * 60 + m, s)
    }

    /// Parse `SS`, `MM:SS`, or `H:MM:SS`.
    public static func parse(_ s: String) -> Double? {
        let parts = s.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        return Double(parts.reduce(0) { $0 * 60 + $1! })
    }
}
