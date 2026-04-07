import Foundation
import SubtitleRendererCore

struct SubtitleTrack: Equatable, Identifiable, Sendable {
    enum Kind: String, Equatable {
        case external
        case embedded
    }

    let id: String
    var displayName: String
    var language: String?
    var formatHint: SubtitleFormat?
    var kind: Kind
    var backendTrackID: String?

    init(
        id: String,
        displayName: String,
        language: String? = nil,
        formatHint: SubtitleFormat? = nil,
        kind: Kind,
        backendTrackID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.language = language
        self.formatHint = formatHint
        self.kind = kind
        self.backendTrackID = backendTrackID
    }
}

protocol SubtitleTrackExtracting {
    func availableTracks(for mediaURL: URL, headers: [String: String]) async throws -> [SubtitleTrack]
    func loadDocument(for trackID: SubtitleTrack.ID, from mediaURL: URL, headers: [String: String]) async throws -> SubtitleDocument
}
