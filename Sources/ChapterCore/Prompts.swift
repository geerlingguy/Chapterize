import Foundation

public enum Prompts {
    /// Example titles shown to the model as a style guide. Editable in Settings.
    public static let defaultStyleExamples = """
    TOASTY!
    You probably won't buy it
    Don't climb energized towers, even once
    I was bamboozled. Don't be me
    x86 still reigns
    Timing Lab - PTP, NTP, PPS
    Adding 2 more RISC-V cores (via expansion module)
    Is it worth the upgrade?
    Installing a dGPU (RTX A2000)
    Massive LLMs
    NTP timing and why it doesn't matter
    Chromium runs, but it's not for that
    DFU mode recovery (yes it's required)
    Pi 4 walkthrough (ft solder voids)
    Charging was more confusing than I expected
    Black Mesa (the curse of the blinking cursor)
    Argon ONE UP - a Pi CM5 laptop
    Three mini NASes
    WiFi 7 Hype Train
    Recapping the Power Supply
    Discovering the dumb
    Technical difficulties (are learning opportunities)
    HPL and llama.cpp cluster performance
    Spouse Approval Factor
    Only one screw left over!
    Pi-hole runs pretty well, actually
    Controlling your own destiny. And dishwasher.
    Why recompile Linux?
    GE Adora and planned obsolescence
    Remote control power (and safeguards)
    """

    /// Turn "00:00 - Title" lines (or bare titles) into a "- Title" list, so the
    /// model copies the voice, not the example timestamps.
    static func styleTitles(_ examples: String) -> String {
        examples.components(separatedBy: .newlines)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let ch = ChapterText.parse(trimmed).first { return ch.title }
                return ChapterText.cleanTitle(trimmed)
            }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("contents") }
            .map { "- \($0)" }
            .joined(separator: "\n")
    }

    public static func instructions(styleExamples: String, timeFormat: String = "MM:SS") -> String {
        """
        You write YouTube chapter markers (a table of contents) for a tech YouTuber who covers \
        homelabs, Raspberry Pi, networking, retro computers, timekeeping, and other hardware.

        Chapter title style:
        - Short: usually 2 to 6 words. Sentence case. No trailing punctuation, emoji, or quotes.
        - Use the specific product names, specs, and tech jargon spoken in the video.
        - Say what that section is actually about. Never use generic labels like "Introduction", \
        "Intro", "Overview", "Conclusion", "Wrap-up", or "Final thoughts".
        - A bit of dry wit is welcome for one or two titles per video, but never forced.
        - The 00:00 chapter names the video's topic or hook.

        Example titles from past videos (style only, not content):
        \(styleTitles(styleExamples))

        Reply with only chapter lines, one per line, in exactly this format:
        \(timeFormat) - Title
        """
    }

    public static func chunkPrompt(transcript: String, part: Int, of parts: Int,
                                   chunkStart: String, chunkEnd: String, videoLength: String,
                                   chapterCount: Int, timeFormat: String = "MM:SS") -> String {
        let zero = timeFormat == "MM:SS" ? "00:00" : "00:00:00"
        let scope: String
        let firstRule: String
        if parts == 1 {
            scope = "Here is the full transcript of a \(videoLength) video."
            firstRule = "The first chapter must be \(zero)."
        } else if part == 1 {
            scope = "Here is part 1 of \(parts) of the transcript of a \(videoLength) video, covering \(chunkStart) to \(chunkEnd)."
            firstRule = "The first chapter must be \(zero)."
        } else {
            scope = "Here is part \(part) of \(parts) of the transcript of a \(videoLength) video, covering \(chunkStart) to \(chunkEnd). An earlier section may still be continuing when this part begins."
            firstRule = "Only put a chapter at \(chunkStart) if a new topic clearly starts there."
        }
        let countRule = chapterCount <= 1
            ? "Write 1 or 2 chapters for this part."
            : "Write about \(chapterCount) chapters for this part (a couple more or fewer is fine if that fits the topics better)."

        return """
        \(scope) Each line starts with the [timestamp] where that bit of speech begins.

        <transcript>
        \(transcript)
        </transcript>

        \(countRule) Start a new chapter wherever the topic shifts. \
        Only use timestamps that appear at the start of a transcript line. \(firstRule)

        Reply with only the chapter lines, like:
        \(timeFormat) - Title
        """
    }

    public static func polishPrompt(drafts: String, minCount: Int, maxCount: Int, videoLength: String,
                                    timeFormat: String = "MM:SS") -> String {
        """
        These draft chapters were written separately for different parts of one \(videoLength) video, \
        so some may overlap or repeat.

        <drafts>
        \(drafts)
        </drafts>

        Produce the final chapter list with \(minCount) to \(maxCount) chapters:
        - Merge or drop chapters that repeat a topic or are very short. When merging, keep the earlier timestamp.
        - Keep timestamps exactly as written in the drafts. Never invent new ones.
        - Keep the 0:00 chapter first.
        - Tighten the titles so they read as one consistent set, in the style described.

        Reply with only the chapter lines, like:
        \(timeFormat) - Title
        """
    }

    public static let retryNudge = "\n\nImportant: reply with nothing but lines like `03:12 - Title`."
}
