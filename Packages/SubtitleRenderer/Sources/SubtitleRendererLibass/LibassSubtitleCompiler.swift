import Foundation
import SubtitleRendererCore

enum LibassSubtitleCompiler {
    struct Cue {
        let startMilliseconds: Int
        let endMilliseconds: Int
        let text: String
    }

    static func compile(_ document: SubtitleDocument) -> String? {
        switch document.format {
        case .ass:
            return document.text
        case .srt:
            guard let cues = parseSRT(document.text) else { return nil }
            return makeASSDocument(from: cues)
        case .webvtt:
            guard let cues = parseWebVTT(document.text) else { return nil }
            return makeASSDocument(from: cues)
        }
    }

    private static func parseSRT(_ text: String) -> [Cue]? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")

        var cues: [Cue] = []
        for rawBlock in blocks {
            let lines = rawBlock
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            guard !lines.isEmpty else { continue }

            let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) ?? 0
            guard timingIndex < lines.count,
                  let timing = parseTimingLine(lines[timingIndex]) else {
                continue
            }

            let textLines = Array(lines[(timingIndex + 1)...])
            guard !textLines.isEmpty else { continue }

            let text = textLines
                .map(stripWebVTTMarkup)
                .joined(separator: "\\N")
            cues.append(.init(startMilliseconds: timing.start, endMilliseconds: timing.end, text: escapeASSText(text)))
        }

        return cues.isEmpty ? nil : cues
    }

    private static func parseWebVTT(_ text: String) -> [Cue]? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")

        var cues: [Cue] = []
        for rawBlock in blocks {
            let lines = rawBlock
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            guard !lines.isEmpty else { continue }
            if lines[0].hasPrefix("WEBVTT") || lines[0].hasPrefix("NOTE") {
                continue
            }

            let timingIndex = lines.firstIndex(where: { $0.contains("-->") })
            guard let timingIndex,
                  let timing = parseTimingLine(lines[timingIndex]) else {
                continue
            }

            let textLines = Array(lines[(timingIndex + 1)...])
            guard !textLines.isEmpty else { continue }

            let text = textLines
                .map(stripWebVTTMarkup)
                .joined(separator: "\\N")
            cues.append(.init(startMilliseconds: timing.start, endMilliseconds: timing.end, text: escapeASSText(text)))
        }

        return cues.isEmpty ? nil : cues
    }

    private static func parseTimingLine(_ line: String) -> (start: Int, end: Int)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }

        let start = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let end = parts[1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .first ?? ""

        guard let startMilliseconds = parseTimestamp(start),
              let endMilliseconds = parseTimestamp(end),
              endMilliseconds > startMilliseconds else {
            return nil
        }
        return (startMilliseconds, endMilliseconds)
    }

    private static func parseTimestamp(_ value: String) -> Int? {
        let sanitized = value.replacingOccurrences(of: ",", with: ".")
        let parts = sanitized.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }

        let hours: Int
        let minutes: Int
        let secondsPart: Substring
        if parts.count == 3 {
            hours = Int(parts[0]) ?? 0
            minutes = Int(parts[1]) ?? 0
            secondsPart = parts[2]
        } else {
            hours = 0
            minutes = Int(parts[0]) ?? 0
            secondsPart = parts[1]
        }

        let secondsComponents = secondsPart.split(separator: ".", omittingEmptySubsequences: false)
        guard let seconds = Int(secondsComponents[0]) else { return nil }
        let millisecondsString = secondsComponents.count > 1 ? String(secondsComponents[1]).padding(toLength: 3, withPad: "0", startingAt: 0) : "000"
        let milliseconds = Int(millisecondsString.prefix(3)) ?? 0

        return (((hours * 60) + minutes) * 60 + seconds) * 1000 + milliseconds
    }

    private static func makeASSDocument(from cues: [Cue]) -> String {
        let header = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: 1920
        PlayResY: 1080
        ScaledBorderAndShadow: yes

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,54,&H00FFFFFF,&H000000FF,&H64000000,&H64000000,0,0,0,0,100,100,0,0,1,2.2,0.8,2,80,80,54,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        """

        let events = cues.map { cue in
            "Dialogue: 0,\(formatASSTime(cue.startMilliseconds)),\(formatASSTime(cue.endMilliseconds)),Default,,0,0,0,,\(cue.text)"
        }

        return ([header] + events).joined(separator: "\n")
    }

    private static func formatASSTime(_ milliseconds: Int) -> String {
        let totalCentiseconds = milliseconds / 10
        let centiseconds = totalCentiseconds % 100
        let totalSeconds = totalCentiseconds / 100
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60
        return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
    }

    private static func escapeASSText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "{", with: "｛")
            .replacingOccurrences(of: "}", with: "｝")
    }

    private static func stripWebVTTMarkup(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
