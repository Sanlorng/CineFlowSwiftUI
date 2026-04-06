import Foundation

public enum SubtitleFormat: String, CaseIterable, Sendable {
    case ass
}

public struct SubtitleDocument: Equatable {
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
}
