import AVFoundation
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias PlatformViewRepresentable = UIViewRepresentable
#elseif canImport(AppKit)
import AppKit
import AVKit
private typealias PlatformViewRepresentable = NSViewRepresentable
#endif

struct AVFoundationPlayerView {
    let source: PlayerSource
    let options: PlayerLoadOptions
    let onStateChanged: ((PlayerPlaybackState) -> Void)?
    let onFinish: ((Error?) -> Void)?
    let onPlaybackTimeChanged: ((TimeInterval) -> Void)?
}

extension AVFoundationPlayerView: PlatformViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(
            onStateChanged: onStateChanged,
            onFinish: onFinish,
            onPlaybackTimeChanged: onPlaybackTimeChanged
        )
    }

#if canImport(UIKit)
    func makeUIView(context: Context) -> PlayerContainerView {
        context.coordinator.makeView(source: source, options: options)
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        context.coordinator.updateView(view: view, source: source, options: options)
    }

    static func dismantleUIView(_ view: PlayerContainerView, coordinator: Coordinator) {
        coordinator.resetPlayer()
    }
#elseif canImport(AppKit)
    func makeNSView(context: Context) -> PlayerContainerView {
        context.coordinator.makeView(source: source, options: options)
    }

    func updateNSView(_ view: PlayerContainerView, context: Context) {
        context.coordinator.updateView(view: view, source: source, options: options)
    }

    static func dismantleNSView(_ view: PlayerContainerView, coordinator: Coordinator) {
        coordinator.resetPlayer()
    }
#endif
}

extension AVFoundationPlayerView {
    @MainActor
    final class Coordinator: NSObject, ObservableObject, @unchecked Sendable {
        private var onStateChanged: ((PlayerPlaybackState) -> Void)?
        private var onFinish: ((Error?) -> Void)?
        private var onPlaybackTimeChanged: ((TimeInterval) -> Void)?

        private var state: PlayerPlaybackState = .idle {
            didSet {
                guard state != oldValue else { return }
                onStateChanged?(state)
            }
        }

        private weak var view: PlayerContainerView?
        private var player: AVPlayer?
        private var playerItem: AVPlayerItem?
        private var currentSource: PlayerSource?
        private var currentOptions: PlayerLoadOptions?
        private var statusObservation: NSKeyValueObservation?
        private var timeControlObservation: NSKeyValueObservation?
        private var bufferEmptyObservation: NSKeyValueObservation?
        private var likelyToKeepUpObservation: NSKeyValueObservation?
        private var periodicTimeObserver: Any?
        private var notificationTokens: [NSObjectProtocol] = []

        init(
            onStateChanged: ((PlayerPlaybackState) -> Void)?,
            onFinish: ((Error?) -> Void)?,
            onPlaybackTimeChanged: ((TimeInterval) -> Void)?
        ) {
            self.onStateChanged = onStateChanged
            self.onFinish = onFinish
            self.onPlaybackTimeChanged = onPlaybackTimeChanged
        }

        func makeView(source: PlayerSource, options: PlayerLoadOptions) -> PlayerContainerView {
            let view = PlayerContainerView(frame: .zero)
            self.view = view
            attachPlayer(to: view, source: source, options: options)
            return view
        }

        func updateView(view: PlayerContainerView, source: PlayerSource, options: PlayerLoadOptions) {
            self.view = view

            if source != currentSource {
                attachPlayer(to: view, source: source, options: options)
                return
            }

            guard currentOptions != options else { return }
            currentOptions = options

            if options.allowAutoPlay, state != .completed {
                player?.play()
            }
        }

        func resetPlayer() {
            clearObservers()
            player?.pause()
            player = nil
            playerItem = nil
            currentSource = nil
            currentOptions = nil
            view?.attach(player: nil)
            if state != .idle {
                state = .stopped
            }
        }

        private func attachPlayer(to view: PlayerContainerView, source: PlayerSource, options: PlayerLoadOptions) {
            clearObservers()

            currentSource = source
            currentOptions = options
            state = .preparing

            let asset = makeAsset(for: source)
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = true

            self.player = player
            self.playerItem = item
            view.attach(player: player)
            observe(player: player, item: item, options: options)

            if options.allowAutoPlay {
                player.play()
            }
        }

        private func observe(player: AVPlayer, item: AVPlayerItem, options: PlayerLoadOptions) {
            timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                Task { @MainActor in
                    self?.updateState(for: player, item: item)
                }
            }

            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if item.status == .failed {
                        let message = item.error?.localizedDescription ?? "播放失败。"
                        self.state = .error(message)
                        self.onFinish?(item.error)
                        return
                    }
                    self.updateState(for: player, item: item)
                }
            }

            bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if item.isPlaybackBufferEmpty {
                        self.state = .buffering
                    }
                }
            }

            likelyToKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if item.isPlaybackLikelyToKeepUp {
                        self.updateState(for: player, item: item)
                    }
                }
            }

            let interval = CMTime(seconds: max(options.playbackTimeNotificationInterval, 1 / 30), preferredTimescale: 600)
            periodicTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.onPlaybackTimeChanged?(time.seconds.isFinite ? time.seconds : 0)
                }
            }

            notificationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    MainActor.assumeIsolated {
                        self.state = .completed
                        self.onFinish?(nil)
                    }
                }
            )

            notificationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemFailedToPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] notification in
                    guard let self else { return }
                    let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    MainActor.assumeIsolated {
                        self.state = .error(error?.localizedDescription ?? "播放失败。")
                        self.onFinish?(error)
                    }
                }
            )
        }

        private func makeAsset(for source: PlayerSource) -> AVURLAsset {
            guard !source.headers.isEmpty else {
                return AVURLAsset(url: source.url)
            }

            // Query-based auth remains the primary supported path for the current backend.
            return AVURLAsset(url: source.url)
        }

        private func updateState(for player: AVPlayer, item: AVPlayerItem) {
            if item.status == .failed {
                state = .error(item.error?.localizedDescription ?? "播放失败。")
                return
            }

            switch player.timeControlStatus {
            case .paused:
                state = player.currentTime() == .zero && item.status != .readyToPlay ? .preparing : .paused
            case .waitingToPlayAtSpecifiedRate:
                state = .buffering
            case .playing:
                state = .playing
            @unknown default:
                state = .buffering
            }
        }

        private func clearObservers() {
            if let periodicTimeObserver, let player {
                player.removeTimeObserver(periodicTimeObserver)
            }
            periodicTimeObserver = nil
            statusObservation = nil
            timeControlObservation = nil
            bufferEmptyObservation = nil
            likelyToKeepUpObservation = nil
            for token in notificationTokens {
                NotificationCenter.default.removeObserver(token)
            }
            notificationTokens.removeAll()
        }
    }
}

#if canImport(UIKit)
@MainActor
final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    func attach(player: AVPlayer?) {
        playerLayer.player = player
        backgroundColor = .black
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
#elseif canImport(AppKit)
@MainActor
final class PlayerContainerView: AVPlayerView {
    func attach(player: AVPlayer?) {
        self.player = player
        controlsStyle = .none
    }
}
#endif
