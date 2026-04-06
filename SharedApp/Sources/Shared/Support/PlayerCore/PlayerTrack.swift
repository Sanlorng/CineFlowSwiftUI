import Foundation

struct PlayerTrack: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case video
        case audio
        case subtitle
    }

    let id: String
    let kind: Kind
    var displayName: String
    var language: String?
    var codec: String?
    var streamIndex: Int?
    var isSelected: Bool
    var isExternal: Bool

    init(
        id: String,
        kind: Kind,
        displayName: String,
        language: String? = nil,
        codec: String? = nil,
        streamIndex: Int? = nil,
        isSelected: Bool = false,
        isExternal: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.language = language
        self.codec = codec
        self.streamIndex = streamIndex
        self.isSelected = isSelected
        self.isExternal = isExternal
    }
}
