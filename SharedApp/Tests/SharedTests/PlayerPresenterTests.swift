import ComposableArchitecture
import Foundation
import Testing
@testable import Shared

@MainActor
struct PlayerPresenterTests {
    @Test
    func changingEpisodesCancelsAttachmentsAndStoppingCancelsTheNewSession() async {
        let clock = TestClock()
        let store = TestStore(initialState: PlayerPresenter.State(request: PlaybackTestFixtures.request())) {
            PlayerPresenter()
        } withDependencies: {
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

        let first = await store.send(.onAppear)
        let oldRequestID = store.state.subtitleListRequest!.id
        let second = await store.send(.playNext)
        await first.finish()
        #expect(store.state.currentFileID == "second")
        #expect(store.state.isLoadingSubtitles)

        await store.send(.subtitleListResponse(oldRequestID, .success([])))
        #expect(store.state.isLoadingSubtitles)
        #expect(store.state.subtitleListRequest?.id != oldRequestID)

        await store.send(.stop)
        await second.finish()
        #expect(!store.state.isLoadingSubtitles)
        #expect(!store.state.isLoadingDanmaku)
        #expect(store.state.subtitleListRequest == nil)
        #expect(store.state.danmakuRequest == nil)
        await store.finish()
    }
}
