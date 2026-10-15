import Foundation
import RemoteMediaLibrary
@testable import Shared

enum PlaybackTestFixtures {
    static let configuration = MediaLibraryConfiguration(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        name: "Test library",
        url: "https://media.example.com",
        apiToken: nil,
        isDefault: true,
        createdAt: Date(timeIntervalSince1970: 0)
    )

    static func request(fileIDs: [String] = ["first", "second"]) -> PlaybackRequest {
        let playlist = fileIDs.enumerated().map { index, fileID in
            let file = Components.Schemas.LibraryBangumiMatchedFile(id: fileID, name: "\(fileID).mkv")
            let episode = Components.Schemas.LibraryBangumiEpisode(episodeId: index, localMatchedFiles: [file])
            return PlaybackItem(
                episode: episode,
                file: file,
                stream: .init(url: URL(string: "https://media.example.com/\(fileID)")!, headers: [:])
            )
        }
        return PlaybackRequest(
            id: UUID(), configuration: configuration, seriesTitle: "Test series", coverURL: nil,
            playlist: playlist, currentIndex: 0,
            allEpisodeFiles: Dictionary(uniqueKeysWithValues: playlist.map { ($0.episode, [$0.file]) })
        )
    }
}
