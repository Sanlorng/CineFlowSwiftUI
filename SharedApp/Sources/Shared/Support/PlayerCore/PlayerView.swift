import SwiftUI

struct PlayerView: View {
    let backend: PlayerBackendKind
    let source: PlayerSource
    let options: PlayerLoadOptions
    let controller: PlayerController

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
        ResumablePlayerSurface(
            backend: backend, source: source, options: options, controller: controller,
            onStateChanged: onStateChangedHandler, onFinish: onFinishHandler,
            onPlaybackTimeChanged: onPlaybackTimeChangedHandler,
            onTracksChanged: onTracksChangedHandler
        )
        .id(source.url)
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

/// Recreated when the source changes; the outgoing session flushes its own progress.
private struct ResumablePlayerSurface: View {
    let backend: PlayerBackendKind
    let source: PlayerSource
    let options: PlayerLoadOptions
    let controller: PlayerController
    let onStateChanged: ((PlayerPlaybackState) -> Void)?
    let onFinish: ((Error?) -> Void)?
    let onPlaybackTimeChanged: ((TimeInterval) -> Void)?
    let onTracksChanged: (([PlayerTrack]) -> Void)?
    @StateObject private var progress: PlaybackProgressSession

    init(backend: PlayerBackendKind, source: PlayerSource, options: PlayerLoadOptions,
         controller: PlayerController,
         onStateChanged: ((PlayerPlaybackState) -> Void)?, onFinish: ((Error?) -> Void)?,
         onPlaybackTimeChanged: ((TimeInterval) -> Void)?, onTracksChanged: (([PlayerTrack]) -> Void)?) {
        self.backend = backend
        self.source = source
        self.options = options
        self.controller = controller
        self.onStateChanged = onStateChanged
        self.onFinish = onFinish
        self.onPlaybackTimeChanged = onPlaybackTimeChanged
        self.onTracksChanged = onTracksChanged
        _progress = StateObject(wrappedValue: PlaybackProgressSession(url: source.url))
    }

    private var eventSink: PlayerBackendEventSink {
        .init(
            onStateChanged: { state in
                controller.updatePlaybackState(state)
                if state == .paused { progress.flush() }
                onStateChanged?(state)
            },
            onFinish: { error in
                if error == nil { progress.finish() } else { progress.flush() }
                onFinish?(error)
            },
            onPlaybackTimeChanged: onPlaybackTimeChanged,
            onTimelineChanged: { timeline in
                controller.updateTimeline(currentTime: timeline.currentTime, duration: timeline.duration)
                if let position = progress.update(timeline) { controller.seekTo(position) }
            },
            onTracksChanged: onTracksChanged,
            onVideoPresentationSizeChanged: { controller.updateVideoPresentationSize($0) }
        )
    }

    var body: some View {
        surface.onDisappear { progress.flush() }
    }
    @ViewBuilder
    private var surface: some View {
        switch backend {
        case .avFoundation:
            AVFoundationPlayerView(
                source: source,
                controller: controller,
                options: options,
                eventSink: eventSink
            )
        case .mpv:
#if os(macOS)
            MPVMacOSPlayerView(
                source: source,
                controller: controller,
                options: options,
                eventSink: eventSink
            )
#else
            MPVPlayerView(
                source: source,
                controller: controller,
                options: options,
                eventSink: eventSink
            )
#endif
        }
    }
}
