import SwiftUI

struct PlayerView: View {
    let backend: PlayerBackendKind
    let source: PlayerSource
    let options: PlayerLoadOptions

    private var onStateChangedHandler: ((PlayerPlaybackState) -> Void)?
    private var onFinishHandler: ((Error?) -> Void)?
    private var onPlaybackTimeChangedHandler: ((TimeInterval) -> Void)?

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
                    onPlaybackTimeChanged: onPlaybackTimeChangedHandler
                )
            )
        case .mpv:
            MPVPlayerView(
                source: source,
                options: options,
                eventSink: .init(
                    onStateChanged: onStateChangedHandler,
                    onFinish: onFinishHandler,
                    onPlaybackTimeChanged: onPlaybackTimeChangedHandler
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
}
