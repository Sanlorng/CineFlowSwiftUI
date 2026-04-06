import Foundation
import SubtitleRendererCore

enum EmbeddedSubtitleExtractorError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "当前默认播放器后端未启用内嵌字幕提取。"
        }
    }
}

struct EmbeddedSubtitleExtractor: SubtitleTrackExtracting {
    func availableTracks(for mediaURL: URL, headers: [String: String]) async throws -> [SubtitleTrack] {
        // Re-enable once a redistributable backend can expose raw subtitle streams.
        []
    }

    func loadDocument(for trackID: SubtitleTrack.ID, from mediaURL: URL, headers: [String: String]) async throws -> SubtitleDocument {
        throw EmbeddedSubtitleExtractorError.unavailable
    }
}
