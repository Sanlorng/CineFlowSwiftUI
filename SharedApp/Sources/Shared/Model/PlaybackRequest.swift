import Foundation
import RemoteMediaLibrary

/// Playback input shared by entry points, independent of the player's UI state.
struct PlaybackRequest: Equatable {
    let id: UUID
    let configuration: MediaLibraryConfiguration
    let seriesTitle: String?
    let coverURL: URL?
    let playlist: [PlaybackItem]
    let currentIndex: Int
    let allEpisodeFiles: [Components.Schemas.LibraryBangumiEpisode: [Components.Schemas.LibraryBangumiMatchedFile]]
}

struct PlaybackItem: Equatable, Identifiable {
    let id: UUID
    let episode: Components.Schemas.LibraryBangumiEpisode
    var file: Components.Schemas.LibraryBangumiMatchedFile
    var stream: RemoteMediaLibraryClient.StreamContext

    init(
        id: UUID = UUID(),
        episode: Components.Schemas.LibraryBangumiEpisode,
        file: Components.Schemas.LibraryBangumiMatchedFile,
        stream: RemoteMediaLibraryClient.StreamContext
    ) {
        self.id = id
        self.episode = episode
        self.file = file
        self.stream = stream
    }
}
