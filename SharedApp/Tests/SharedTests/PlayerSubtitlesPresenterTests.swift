import ComposableArchitecture
import Testing
@testable import Shared

@MainActor
struct PlayerSubtitlesPresenterTests {
    @Test
    func initialLoadPreservesEarlyBackendTracksAndRepeatedLoadsPreserveSelection() async {
        let request = PlaybackTestFixtures.request()
        let context = PlaybackAttachmentContext(
            id: request.id, configuration: request.configuration, item: request.playlist.first,
            capabilities: [.embeddedSubtitleTracks]
        )
        let clock = TestClock()
        let store = TestStore(initialState: PlayerSubtitlesPresenter.State(context: context)) {
            PlayerSubtitlesPresenter()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.remoteMediaLibraryClient.fetchSubtitleInfo = { _, _, _ in
                try await clock.sleep(for: .seconds(60))
                return []
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.playerTracksChanged([
            PlayerTrack(id: "3", kind: .subtitle, displayName: "Chinese", streamIndex: 2)
        ]))
        await store.receive(.automaticallySelectEmbeddedSubtitle("2"))
        let load = await store.send(.load)
        await store.receive(.automaticallySelectEmbeddedSubtitle("2"))
        #expect(store.state.availableEmbeddedSubtitles.map(\.id) == ["2"])
        #expect(!store.state.isLoadingEmbeddedSubtitles)

        await store.send(.setSubtitlesSuppressed(true))
        let requestID = store.state.subtitleListRequest?.id
        await store.send(.load)
        #expect(store.state.areSubtitlesSuppressed)
        #expect(store.state.subtitleListRequest?.id == requestID)
        await store.send(.stop)
        await load.finish()
        await store.finish()
    }

    @Test
    func stoppingCancelsFallbackExtractionAndIgnoresItsLateResponse() async {
        let request = PlaybackTestFixtures.request()
        let context = PlaybackAttachmentContext(
            id: request.id, configuration: request.configuration, item: request.playlist.first,
            capabilities: []
        )
        let clock = TestClock()
        let store = TestStore(initialState: PlayerSubtitlesPresenter.State(context: context)) {
            PlayerSubtitlesPresenter()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.remoteMediaLibraryClient.fetchSubtitleInfo = { _, _, _ in
                try await clock.sleep(for: .seconds(60))
                return []
            }
            $0.subtitleExtractionClient.availableTracks = { _, _ in
                try await clock.sleep(for: .seconds(60))
                return []
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        let load = await store.send(.load)
        let requestID = store.state.embeddedSubtitleTracksRequest!.id
        await store.send(.stop)
        await load.finish()
        await store.send(.embeddedSubtitleTracksResponse(requestID, .success([])))
        #expect(!store.state.isLoadingEmbeddedSubtitles)
        #expect(store.state.embeddedSubtitleTracksRequest == nil)
        await store.finish()
    }
}
