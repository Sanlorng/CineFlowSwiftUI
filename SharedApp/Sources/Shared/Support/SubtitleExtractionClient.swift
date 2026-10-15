import Dependencies
import Foundation
import SubtitleRendererCore

struct SubtitleExtractionClient: Sendable {
    var availableTracks: @Sendable (URL, [String: String]) async throws -> [SubtitleTrack]
    var loadWindow: @Sendable (SubtitleTrack.ID, URL, [String: String], ClosedRange<TimeInterval>) async throws -> SubtitleDocument
}

extension SubtitleExtractionClient: DependencyKey {
    static let liveValue = Self(
        availableTracks: { url, headers in
            try Task.checkCancellation()
            let tracks = try await EmbeddedSubtitleExtractor().availableTracks(for: url, headers: headers)
            try Task.checkCancellation()
            return tracks
        },
        loadWindow: { trackID, url, headers, window in
            try Task.checkCancellation()
            let document = try await EmbeddedSubtitleExtractor().loadDocument(for: trackID, from: url, headers: headers, window: window)
            try Task.checkCancellation()
            return document
        }
    )
    static let testValue = Self(
        availableTracks: { _, _ in throw APIError.unexpectedResponse("Unimplemented subtitle track extraction") },
        loadWindow: { _, _, _, _ in throw APIError.unexpectedResponse("Unimplemented subtitle window extraction") }
    )
}

extension DependencyValues {
    var subtitleExtractionClient: SubtitleExtractionClient {
        get { self[SubtitleExtractionClient.self] }
        set { self[SubtitleExtractionClient.self] = newValue }
    }
}
