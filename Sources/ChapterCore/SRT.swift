import Foundation

/// One subtitle cue from an .srt file.
public struct Cue: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum SRTError: LocalizedError {
    case unreadable
    case noCues

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "Couldn't read that file as text."
        case .noCues: return "No subtitle cues found. Is that a valid .srt file?"
        }
    }
}

public enum SRTParser {
    // 00:01:02,345 --> 00:01:04,000 (hours optional, ',' or '.' before millis)
    private static let timingRegex = try! NSRegularExpression(
        pattern: #"(?:(\d+):)?(\d{1,2}):(\d{2})[,.](\d{1,3})\s*-->\s*(?:(\d+):)?(\d{1,2}):(\d{2})[,.](\d{1,3})"#
    )
    private static let tagRegex = try! NSRegularExpression(pattern: #"<[^>]+>|\{[^}]*\}"#)
    private static let spaceRegex = try! NSRegularExpression(pattern: #"\s+"#)

    public static func parse(url: URL) throws -> [Cue] {
        let data = try Data(contentsOf: url)
        guard let string = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw SRTError.unreadable
        }
        return try parse(string: string)
    }

    public static func parse(string: String) throws -> [Cue] {
        var text = string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        let lines = text.components(separatedBy: "\n")
        var cues: [Cue] = []
        var i = 0
        while i < lines.count {
            guard let timing = parseTiming(lines[i]) else {
                i += 1
                continue
            }
            let (start, end) = timing
            i += 1
            var body: [String] = []
            while i < lines.count {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                if line.isEmpty || parseTiming(line) != nil { break }
                body.append(line)
                i += 1
            }
            // Files missing blank lines between cues: drop a trailing index number.
            if i < lines.count, parseTiming(lines[i]) != nil,
               let last = body.last, Int(last) != nil {
                body.removeLast()
            }
            let cleaned = clean(body.joined(separator: " "))
            if !cleaned.isEmpty {
                cues.append(Cue(start: start, end: max(end, start), text: cleaned))
            }
        }

        guard !cues.isEmpty else { throw SRTError.noCues }
        return cues.sorted { $0.start < $1.start }
    }

    static func parseTiming(_ line: String) -> (Double, Double)? {
        let ns = line as NSString
        guard let m = timingRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        func group(_ n: Int) -> String? {
            let r = m.range(at: n)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        func seconds(_ h: Int, _ mi: Int, _ s: Int, _ f: Int) -> Double {
            let hours = Double(group(h) ?? "0") ?? 0
            let mins = Double(group(mi) ?? "0") ?? 0
            let secs = Double(group(s) ?? "0") ?? 0
            let frac = Double("0." + (group(f) ?? "0")) ?? 0
            return hours * 3600 + mins * 60 + secs + frac
        }
        return (seconds(1, 2, 3, 4), seconds(5, 6, 7, 8))
    }

    static func clean(_ s: String) -> String {
        var out = tagRegex.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        out = spaceRegex.stringByReplacingMatches(
            in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
