import Foundation
import RemoteMediaLibrary
import Testing
@testable import Shared

struct PlaylistBuilderTests {
    @Test
    func preservesEpisodeOrderAndSelectedFileWhileMatchingOtherEpisodes() throws {
        let otherRelease = Components.Schemas.LibraryBangumiMatchedFile(id: "other", name: "Different release.mkv")
        let matchingRelease = Components.Schemas.LibraryBangumiMatchedFile(id: "matching", name: "Group - 01.mkv")
        let selectedFile = Components.Schemas.LibraryBangumiMatchedFile(id: "selected", name: "Group - 02.mkv")
        let first = Components.Schemas.LibraryBangumiEpisode(episodeId: 1, localMatchedFiles: [otherRelease, matchingRelease])
        let missing = Components.Schemas.LibraryBangumiEpisode(episodeId: 99)
        let selected = Components.Schemas.LibraryBangumiEpisode(episodeId: 2, localMatchedFiles: [otherRelease, selectedFile])

        let request = try build(episodes: [first, missing, selected], selected: selected, file: selectedFile)

        #expect(request.playlist.map(\.file.id) == ["matching", "selected"])
        #expect(request.playlist.map(\.episode.episodeId) == [1, 2])
        #expect(request.currentIndex == 1)
        #expect(request.allEpisodeFiles[selected] == [otherRelease, selectedFile])
        #expect(request.playlist[1].stream.url.lastPathComponent == "selected")
    }

    @Test
    func rejectsAnEmptyPlayableLibrary() {
        #expect(throws: PlaybackPreparationError.self) {
            try build(episodes: [], selected: .init(), file: .init())
        }
    }

    @Test
    func rejectsFilesWithoutAStreamIdentifier() {
        let file = Components.Schemas.LibraryBangumiMatchedFile(name: "missing-id.mkv")
        let episode = Components.Schemas.LibraryBangumiEpisode(episodeId: 1, localMatchedFiles: [file])
        #expect(throws: PlaybackPreparationError.self) {
            try build(episodes: [episode], selected: episode, file: file)
        }
    }

    private func build(
        episodes: [Components.Schemas.LibraryBangumiEpisode],
        selected: Components.Schemas.LibraryBangumiEpisode,
        file: Components.Schemas.LibraryBangumiMatchedFile
    ) throws -> PlaybackRequest {
        try PlaylistBuilder.build(
            detail: .init(episodes: episodes),
            baseURL: URL(string: PlaybackTestFixtures.configuration.url)!,
            token: nil,
            configuration: PlaybackTestFixtures.configuration,
            seriesTitle: "Series",
            coverURL: nil,
            selectedEpisode: selected,
            selectedFile: file,
            makeStream: { baseURL, _, fileID in
                .init(url: baseURL.appendingPathComponent(fileID), headers: [:])
            }
        )
    }
}
