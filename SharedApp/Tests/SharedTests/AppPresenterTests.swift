import ComposableArchitecture
import Testing
@testable import Shared

@MainActor
struct AppPresenterTests {
    @Test
    func bothEntryPointsRoutePlaybackThroughTheRoot() async {
        let store = TestStore(initialState: AppPresenter.State()) { AppPresenter() }
        let homeRequest = PlaybackTestFixtures.request()
        let libraryRequest = PlaybackTestFixtures.request(fileIDs: ["third"])

        await store.send(.home(.delegate(.startPlayback(homeRequest)))) {
            $0.player = .init(request: homeRequest)
            $0.selectedTab = .Player
        }
        await store.send(.selectTab(.Library)) { $0.selectedTab = .Library }
        await store.send(.library(.delegate(.startPlayback(libraryRequest)))) {
            $0.player = .init(request: libraryRequest)
            $0.selectedTab = .Player
        }
        await store.send(.stopPlayback) {
            $0.player = nil
            $0.selectedTab = .Home
        }
    }

    @Test
    func replacingPlaybackCancelsEffectsOwnedByTheOldPlayer() async {
        let clock = TestClock()
        var state = AppPresenter.State()
        state.player = .init(request: PlaybackTestFixtures.request())
        let store = TestStore(initialState: state) { AppPresenter() } withDependencies: {
            $0.uuid = .incrementing
            $0.remoteMediaLibraryClient.fetchSubtitleInfo = { _, _, _ in
                try await clock.sleep(for: .seconds(60))
                return []
            }
            $0.remoteMediaLibraryClient.fetchDanmakuXML = { _, _, _ in
                try await clock.sleep(for: .seconds(60))
                return "<i></i>"
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        let oldPlayer = await store.send(.player(.onAppear))
        let request = PlaybackTestFixtures.request(fileIDs: ["replacement"])
        await store.send(.library(.delegate(.startPlayback(request))))
        await oldPlayer.finish()
        #expect(store.state.player?.id == request.id)
        #expect(store.state.player?.currentFileID == "replacement")
        await store.finish()
    }
}
