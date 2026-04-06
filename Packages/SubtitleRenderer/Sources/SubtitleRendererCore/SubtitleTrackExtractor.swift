import Foundation

public protocol SubtitleTrackExtracting {
    func availableTracks(for mediaURL: URL) async throws -> [SubtitleTrack]
    func loadDocument(for trackID: SubtitleTrack.ID, from mediaURL: URL) async throws -> SubtitleDocument
}
