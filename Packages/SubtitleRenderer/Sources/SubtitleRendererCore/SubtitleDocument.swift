import Foundation

public enum SubtitleFormat: String, CaseIterable, Sendable {
    case ass
    case srt
    case webvtt
}

public struct SubtitleDocument: Equatable, Sendable {
    public var format: SubtitleFormat
    public var text: String
    public var fileName: String?

    public init(format: SubtitleFormat, text: String, fileName: String? = nil) {
        self.format = format
        self.text = text
        self.fileName = fileName
    }

    public static func ass(_ text: String, fileName: String? = nil) -> Self {
        Self(format: .ass, text: text, fileName: fileName)
    }

    public static func srt(_ text: String, fileName: String? = nil) -> Self {
        Self(format: .srt, text: text, fileName: fileName)
    }

    public static func webvtt(_ text: String, fileName: String? = nil) -> Self {
        Self(format: .webvtt, text: text, fileName: fileName)
    }

    public static func detecting(rawText: String, fileName: String? = nil) -> Self? {
        guard let format = SubtitleFormat.detect(fileName: fileName, rawText: rawText) else {
            return nil
        }
        return Self(format: format, text: rawText, fileName: fileName)
    }
}

public extension SubtitleFormat {
    static func detect(fileName: String?, rawText: String) -> SubtitleFormat? {
        let ext = (fileName as NSString?)?.pathExtension.lowercased()
        switch ext {
        case "ass", "ssa":
            return .ass
        case "srt":
            return .srt
        case "vtt":
            return .webvtt
        default:
            break
        }

        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("WEBVTT") {
            return .webvtt
        }
        if rawText.contains("[Script Info]") || rawText.contains("\nDialogue:") {
            return .ass
        }
        if rawText.contains("-->") {
            return .srt
        }
        return nil
    }
}
