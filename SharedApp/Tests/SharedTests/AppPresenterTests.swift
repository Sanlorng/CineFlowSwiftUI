import ComposableArchitecture
import Foundation
import Testing
@testable import Shared

@MainActor
struct AppPresenterTests {
    @Test
    func savedLibraryChangesInvalidateHomePlaybackData() async {
        var state = AppPresenter.State()
        let item = HomePresenter.State.QuickStatusItem(
            animeId: 1, title: "Old library item", imageURL: nil, secondaryText: "", rating: nil
        )
        state.home.unwatchedItems = [item]
        state.home.continueWatchingItems = [item]
        state.home.path.append(.bangumiDetail(.init(summary: item.detailSummary)))
        let store = TestStore(initialState: state) { AppPresenter() } withDependencies: {
            $0.uuid = .incrementing
            $0.remoteLibraryConfigurationOperation.fetchDefault = { nil }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.library(.delegate(.configurationChanged)))
        await store.receive(\.home.remoteLibraryChanged)
        #expect(store.state.home.path.isEmpty)
        #expect(store.state.home.unwatchedItems.isEmpty)
        #expect(store.state.home.continueWatchingItems.isEmpty)
        await store.receive(\.home.remoteHighlightsResponse)
        #expect(store.state.home.remoteHighlightsRequestID == nil)
        #expect(store.state.home.quickStatusErrorMessage == nil)
        await store.finish()
    }

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

        let oldPlayer = await store.send(.player(.subtitles(.load)))
        let request = PlaybackTestFixtures.request(fileIDs: ["replacement"])
        await store.send(.library(.delegate(.startPlayback(request))))
        await oldPlayer.finish()
        #expect(store.state.player?.id == request.id)
        #expect(store.state.player?.currentFileID == "replacement")
        await store.finish()
    }
}
