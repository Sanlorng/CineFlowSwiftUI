enum PlayerPlaybackPolicy {
    enum Completion: Equatable {
        case stop
        case restart
        case play(Int)
    }

    static func completion(mode: PlayerPlaybackMode, currentIndex: Int, itemCount: Int) -> Completion {
        guard (0..<itemCount).contains(currentIndex) else { return .stop }
        if mode == .singleRepeat { return .restart }
        if currentIndex + 1 < itemCount { return .play(currentIndex + 1) }
        guard mode == .listRepeat else { return .stop }
        return itemCount == 1 ? .restart : .play(0)
    }

    static func allowsAutoPlay(
        state: PlayerPresenter.State,
        isDanmakuVisible: Bool,
        isSubtitleRendererReady: Bool,
        playbackState: PlayerPlaybackState
    ) -> Bool {
        guard state.shouldAutoPlayCurrentEntry,
              !blocksStartForDanmaku(
                danmaku: state.danmaku, isDanmakuVisible: isDanmakuVisible, playbackState: playbackState
              ) else { return false }
        let subtitles = state.subtitles
        if subtitles.areSubtitlesSuppressed { return true }
        if subtitles.subtitleError != nil, !subtitles.isLoadingSelectedSubtitle { return true }
        if subtitles.activeSubtitle != nil { return isSubtitleRendererReady }
        if subtitles.context.capabilities.contains(.embeddedSubtitleTracks),
           subtitles.selectedEmbeddedSubtitle?.backendTrackID != nil { return true }
        if subtitles.selectedEmbeddedSubtitleTrackID != nil || subtitles.selectedSubtitle != nil { return false }
        return subtitles.availableEmbeddedSubtitles.isEmpty && !subtitles.isLoadingEmbeddedSubtitles
    }

    static func blocksStartForDanmaku(
        danmaku: PlayerDanmakuPresenter.State,
        isDanmakuVisible: Bool,
        playbackState: PlayerPlaybackState
    ) -> Bool {
        guard isDanmakuVisible, danmaku.isLoading, danmaku.document == nil else { return false }
        switch playbackState {
        case .playing, .buffering:
            return false
        case .preparing, .paused, .stopped, .completed, .idle, .error:
            return true
        }
    }
}
