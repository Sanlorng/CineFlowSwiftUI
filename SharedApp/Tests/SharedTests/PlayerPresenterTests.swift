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

        let first = await store.send(.subtitles(.load))
        let firstDanmaku = await store.send(.danmaku(.load))
        let oldRequestID = store.state.subtitles.subtitleListRequest!.id
        let oldDanmakuID = store.state.danmaku.requestID!
        await store.send(.playNext)
        await store.receive(.subtitles(.stop))
        await store.receive(.danmaku(.stop))
        await store.receive(.subtitles(.load))
        await store.receive(.danmaku(.load))
        await first.finish()
        await firstDanmaku.finish()
        #expect(store.state.currentFileID == "second")
        #expect(store.state.subtitles.isLoadingSubtitles)

        await store.send(.subtitles(.subtitleListResponse(oldRequestID, .success([]))))
        #expect(store.state.subtitles.isLoadingSubtitles)
        #expect(store.state.subtitles.subtitleListRequest?.id != oldRequestID)
        await store.send(.danmaku(.response(oldDanmakuID, .failure(CancellationError()))))
        #expect(store.state.danmaku.isLoading)
        #expect(store.state.danmaku.error == nil)

        await store.send(.stop)
        await store.receive(.subtitles(.stop))
        await store.receive(.danmaku(.stop))
        #expect(!store.state.subtitles.isLoadingSubtitles)
        #expect(!store.state.danmaku.isLoading)
        #expect(store.state.subtitles.subtitleListRequest == nil)
        #expect(store.state.danmaku.requestID == nil)
        await store.finish()
    }
}
