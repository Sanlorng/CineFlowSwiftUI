import SwiftUI

struct PlayerView: View {
    let backend: PlayerBackendKind
    let source: PlayerSource
    let options: PlayerLoadOptions
    @ObservedObject var controller: PlayerController

    private var onStateChangedHandler: ((PlayerPlaybackState) -> Void)?
    private var onFinishHandler: ((Error?) -> Void)?
    private var onPlaybackTimeChangedHandler: ((TimeInterval) -> Void)?
    private var onTracksChangedHandler: (([PlayerTrack]) -> Void)?

    init(
        backend: PlayerBackendKind = .defaultDistributable,
        source: PlayerSource,
        controller: PlayerController,
        options: PlayerLoadOptions
    ) {
        self.backend = backend
        self.source = source
        self.controller = controller
        self.options = options
    }

    var body: some View {
        switch backend {
        case .avFoundation:
            AVFoundationPlayerView(
                source: source,
                controller: controller,
                options: options,
                eventSink: .init(
                    onStateChanged: { state in
                        controller.updatePlaybackState(state)
                        onStateChangedHandler?(state)
                    },
                    onFinish: onFinishHandler,
                    onPlaybackTimeChanged: onPlaybackTimeChangedHandler,
                    onTimelineChanged: { timeline in
                        controller.updateTimeline(currentTime: timeline.currentTime, duration: timeline.duration)
                    },
                    onTracksChanged: onTracksChangedHandler
                )
            )
        case .mpv:
#if os(macOS)
            MPVMacOSPlayerView(
                source: source,
                controller: controller,
                options: options,
                eventSink: .init(
                    onStateChanged: { state in
                        controller.updatePlaybackState(state)
                        onStateChangedHandler?(state)
                    },
                    onFinish: onFinishHandler,
                    onPlaybackTimeChanged: onPlaybackTimeChangedHandler,
                    onTimelineChanged: { timeline in
                        controller.updateTimeline(currentTime: timeline.currentTime, duration: timeline.duration)
                    },
                    onTracksChanged: onTracksChangedHandler
                )
            )
#else
            MPVPlayerView(
                source: source,
                controller: controller,
                options: options,
                eventSink: .init(
                    onStateChanged: { state in
                        controller.updatePlaybackState(state)
                        onStateChangedHandler?(state)
                    },
                    onFinish: onFinishHandler,
                    onPlaybackTimeChanged: onPlaybackTimeChangedHandler,
                    onTimelineChanged: { timeline in
                        controller.updateTimeline(currentTime: timeline.currentTime, duration: timeline.duration)
                    },
                    onTracksChanged: onTracksChangedHandler
                )
            )
#endif
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
