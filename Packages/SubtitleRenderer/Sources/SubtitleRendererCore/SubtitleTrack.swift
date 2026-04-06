import Foundation

public struct SubtitleTrack: Equatable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case external
        case embedded
    }

    public let id: String
    public var displayName: String
    public var language: String?
    public var formatHint: SubtitleFormat?
    public var kind: Kind

    public init(
        id: String,
        displayName: String,
        language: String? = nil,
        formatHint: SubtitleFormat? = nil,
        kind: Kind
    ) {
        self.id = id
        self.displayName = displayName
        self.language = language
        self.formatHint = formatHint
        self.kind = kind
    }
}
