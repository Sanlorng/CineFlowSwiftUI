import SwiftUI

struct PlayerView: View {
    let backend: PlayerBackendKind
    let source: PlayerSource
    let options: PlayerLoadOptions

    private var onStateChangedHandler: ((PlayerPlaybackState) -> Void)?
    private var onFinishHandler: ((Error?) -> Void)?
    private var onPlaybackTimeChangedHandler: ((TimeInterval) -> Void)?
    private var onTracksChangedHandler: (([PlayerTrack]) -> Void)?

    init(
        backend: PlayerBackendKind = .defaultDistributable,
        source: PlayerSource,
        options: PlayerLoadOptions
    ) {
        self.backend = backend
        self.source = source
        self.options = options
    }

    var body: some View {
        switch backend {
        case .avFoundation:
            AVFoundationPlayerView(
                source: source,
                options: options,
                eventSink: .init(
                    onStateChanged: onStateChangedHandler,
                    onFinish: onFinishHandler,
                    onPlaybackTimeChanged: onPlaybackTimeChangedHandler,
                    onTracksChanged: onTracksChangedHandler
                )
            )
        case .mpv:
            MPVPlayerView(
                source: source,
                options: options,
                eventSink: .init(
                    onStateChanged: onStateChangedHandler,
                    onFinish: onFinishHandler,
                    onPlaybackTimeChanged: onPlaybackTimeChangedHandler,
                    onTracksChanged: onTracksChangedHandler
                )
            )
        }
    }
}

extension PlayerView {
    func onStateChanged(_ handler: @escaping (PlayerPlaybackState) -> Void) -> PlayerView {
        var copy = self
        copy.onStateChangedHandler = handler
        return copy
    }

    func onFinish(_ handler: @escaping (Error?) -> Void) -> PlayerView {
        var copy = self
        copy.onFinishHandler = handler
        return copy
    }

    func onPlaybackTimeChanged(_ handler: @escaping (TimeInterval) -> Void) -> PlayerView {
        var copy = self
        copy.onPlaybackTimeChangedHandler = handler
        return copy
    }

    func onTracksChanged(_ handler: @escaping ([PlayerTrack]) -> Void) -> PlayerView {
        var copy = self
        copy.onTracksChangedHandler = handler
        return copy
    }
}
