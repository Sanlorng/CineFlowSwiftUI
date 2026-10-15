import Testing
@testable import Shared

struct PlayerPlaybackPolicyTests {
    @Test
    func completionHandlesPlaylistBoundaries() {
        #expect(PlayerPlaybackPolicy.completion(mode: .sequential, currentIndex: 0, itemCount: 2) == .play(1))
        #expect(PlayerPlaybackPolicy.completion(mode: .sequential, currentIndex: 1, itemCount: 2) == .stop)
        #expect(PlayerPlaybackPolicy.completion(mode: .listRepeat, currentIndex: 1, itemCount: 2) == .play(0))
        #expect(PlayerPlaybackPolicy.completion(mode: .listRepeat, currentIndex: 0, itemCount: 1) == .restart)
        #expect(PlayerPlaybackPolicy.completion(mode: .singleRepeat, currentIndex: 1, itemCount: 2) == .restart)
        #expect(PlayerPlaybackPolicy.completion(mode: .singleRepeat, currentIndex: 0, itemCount: 0) == .stop)
    }

    @Test
    func loadingAttachmentsDelaysAutoplayWithoutInterruptingPlayback() {
        var state = PlayerPresenter.State(request: PlaybackTestFixtures.request())
        state.danmaku.isLoading = true
        #expect(!PlayerPlaybackPolicy.allowsAutoPlay(
            state: state, isDanmakuVisible: true, isSubtitleRendererReady: false, playbackState: .preparing
        ))
        #expect(PlayerPlaybackPolicy.allowsAutoPlay(
            state: state, isDanmakuVisible: true, isSubtitleRendererReady: false, playbackState: .playing
        ))
        state.subtitles.isLoadingEmbeddedSubtitles = true
        #expect(!PlayerPlaybackPolicy.allowsAutoPlay(
            state: state, isDanmakuVisible: false, isSubtitleRendererReady: false, playbackState: .preparing
        ))
        state.subtitles.areSubtitlesSuppressed = true
        #expect(PlayerPlaybackPolicy.allowsAutoPlay(
            state: state, isDanmakuVisible: false, isSubtitleRendererReady: false, playbackState: .preparing
        ))
        state.shouldAutoPlayCurrentEntry = false
        #expect(!PlayerPlaybackPolicy.allowsAutoPlay(
            state: state, isDanmakuVisible: false, isSubtitleRendererReady: true, playbackState: .preparing
        ))
    }
}
