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
            UnsupportedPlayerBackendView(
                backend: backend,
                onStateChanged: onStateChangedHandler
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

private struct UnsupportedPlayerBackendView: View {
    let backend: PlayerBackendKind
    let onStateChanged: ((PlayerPlaybackState) -> Void)?

    var body: some View {
        Rectangle()
            .fill(Color.black)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "play.slash")
                        .font(.system(size: 28, weight: .medium))
                    Text("\(backend.displayName) 后端尚未接入当前构建")
                        .font(.callout)
                }
                .foregroundStyle(.white.opacity(0.88))
            }
            .onAppear {
                onStateChanged?(.error("\(backend.displayName) 后端尚未接入当前构建。"))
            }
    }
}
