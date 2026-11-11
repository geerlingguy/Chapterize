import Foundation

public struct Chapter: Sendable, Equatable {
    public var start: Double
    public var title: String

    public init(start: Double, title: String) {
        self.start = start
        self.title = title
    }
}

public enum ChapterText {
    // Accepts "00:00 - Title", "1. [00:00] Title", "- **01:23** – Title", "1:02:03: Title", etc.
    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:[-*•]\s*)?(?:\d+[.)]\s+)?[*_`]*\[?((?:\d{1,2}:)?\d{1,3}:\d{2})\]?[*_`]*\s*(?:[-–—:|]\s*)?(.+?)\s*$"#
    )
    private static let chapterPrefix = try! NSRegularExpression(
        pattern: #"^(?:chapter|part|section)\s*\d+\s*[:.\-–—]\s*"#, options: [.caseInsensitive]
    )

    /// Parse model output into chapters (unsorted, unsnapped).
    public static func parse(_ text: String) -> [Chapter] {
        let stripped = stripThinking(text)
        var chapters: [Chapter] = []
        for raw in stripped.components(separatedBy: .newlines) {
            let ns = raw as NSString
            guard let m = lineRegex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)),
                  let time = Timestamp.parse(ns.substring(with: m.range(at: 1))) else { continue }
            let title = cleanTitle(ns.substring(with: m.range(at: 2)))
            if !title.isEmpty { chapters.append(Chapter(start: time, title: title)) }
        }
        return chapters
    }

    public static func stripThinking(_ text: String) -> String {
        guard let close = text.range(of: "</think>") else { return text }
        return String(text[close.upperBound...])
    }

    static func cleanTitle(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        t = chapterPrefix.stringByReplacingMatches(
            in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
        let wrappers = CharacterSet(charactersIn: "\"'“”‘’*_`")
        t = t.trimmingCharacters(in: wrappers.union(.whitespaces))
        while let last = t.last, ".;,".contains(last) { t.removeLast() }
        // Leading dash left over from "00:00 -- Title"
        while let first = t.first, "-–—:|".contains(first) {
            t.removeFirst()
            t = t.trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    /// Render the final table of contents.
    public static func render(_ chapters: [Chapter], useHours: Bool, includeHeader: Bool) -> String {
        var lines: [String] = []
        if includeHeader { lines += ["Contents:", ""] }
        lines += chapters.map { "\(Timestamp.format($0.start, useHours: useHours)) - \($0.title)" }
        return lines.joined(separator: "\n") + "\n"
    }
}

public enum ChapterRules {
    /// Rough chapter count for a video, based on Jeff's past videos
    /// (~7 for 6 min, ~11 for 12 min, ~15 for 27 min).
    public static func targetCount(duration: Double) -> Int {
        let minutes = max(1, duration / 60)
        return min(30, max(3, Int((3.0 * minutes.squareRoot()).rounded())))
    }

    /// Move each chapter onto the nearest allowed timestamp; drop ones that
    /// land outside [lower, upper] (± slop).
    public static func snap(_ chapters: [Chapter], to allowed: [Double],
                            lower: Double, upper: Double, slop: Double = 15) -> [Chapter] {
        guard !allowed.isEmpty else { return chapters }
        return chapters.compactMap { ch in
            guard ch.start >= lower - slop, ch.start <= upper + slop else { return nil }
            let nearest = allowed.min { abs($0 - ch.start) < abs($1 - ch.start) }!
            return Chapter(start: nearest, title: ch.title)
        }
    }

    /// Enforce YouTube's rules: first chapter at 0:00, sorted, each at least
    /// `minGap` seconds long, none starting in the final seconds of the video.
    public static func normalize(_ chapters: [Chapter], duration: Double, minGap: Double = 10) -> [Chapter] {
        let sorted = chapters.sorted { $0.start < $1.start }
        var out: [Chapter] = []
        for ch in sorted {
            if ch.start > duration - minGap, !out.isEmpty { continue }
            if let prev = out.last, ch.start - prev.start < minGap { continue }
            out.append(ch)
        }
        if !out.isEmpty { out[0].start = 0 }
        // A second chapter that now sits within minGap of 0:00 gets dropped.
        if out.count > 1, out[1].start < minGap { out.remove(at: 1) }
        return out
    }
}
