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
    let controller: PlayerController
    let options: PlayerLoadOptions
    let eventSink: PlayerBackendEventSink
}

extension AVFoundationPlayerView: PlatformViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(eventSink: eventSink)
    }

#if canImport(UIKit)
    func makeUIView(context: Context) -> PlayerContainerView {
        context.coordinator.makeView(source: source, controller: controller, options: options)
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        context.coordinator.updateView(view: view, source: source, controller: controller, options: options)
    }

    static func dismantleUIView(_ view: PlayerContainerView, coordinator: Coordinator) {
        coordinator.reset()
    }
#elseif canImport(AppKit)
    func makeNSView(context: Context) -> PlayerContainerView {
        context.coordinator.makeView(source: source, controller: controller, options: options)
    }

    func updateNSView(_ view: PlayerContainerView, context: Context) {
        context.coordinator.updateView(view: view, source: source, controller: controller, options: options)
    }

    static func dismantleNSView(_ view: PlayerContainerView, coordinator: Coordinator) {
        coordinator.reset()
    }
#endif
}

extension AVFoundationPlayerView {
    @MainActor
    final class Coordinator: NSObject, ObservableObject, @unchecked Sendable {
        let capabilities = PlayerBackendKind.avFoundation.capabilities
        private let eventSink: PlayerBackendEventSink

        private var state: PlayerPlaybackState = .idle {
            didSet {
                guard state != oldValue else { return }
                eventSink.onStateChanged?(state)
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
        private var lastHandledCommandRevision: UInt64 = 0
        private var currentPlaybackRate: Double = 1

        init(eventSink: PlayerBackendEventSink) {
            self.eventSink = eventSink
        }

        func makeView(source: PlayerSource, controller: PlayerController, options: PlayerLoadOptions) -> PlayerContainerView {
            let view = PlayerContainerView(frame: .zero)
            self.view = view
            attachPlayer(to: view, source: source, options: options)
            handleCommandIfNeeded(from: controller)
            return view
        }

        func updateView(view: PlayerContainerView, source: PlayerSource, controller: PlayerController, options: PlayerLoadOptions) {
            self.view = view

            if source != currentSource {
                attachPlayer(to: view, source: source, options: options)
                handleCommandIfNeeded(from: controller)
                return
            }

            if currentOptions != options {
                currentOptions = options

                if options.allowAutoPlay, state != .completed {
                    player?.play()
                }
            }
            handleCommandIfNeeded(from: controller)
        }

        func reset() {
            clearObservers()
            player?.pause()
            player = nil
            playerItem = nil
            currentSource = nil
            currentOptions = nil
            currentPlaybackRate = 1
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
                playAtCurrentRate()
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
                        self.eventSink.onFinish?(item.error)
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
                let currentTime = time.seconds.isFinite ? time.seconds : 0
                let durationSeconds = item.duration.seconds
                let duration = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : nil
                MainActor.assumeIsolated {
                    self.eventSink.onPlaybackTimeChanged?(currentTime)
                    self.eventSink.onTimelineChanged?(.init(currentTime: currentTime, duration: duration))
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
                        self.eventSink.onFinish?(nil)
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
                        self.eventSink.onFinish?(error)
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
            let currentTime = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
            let durationSeconds = item.duration.seconds
            let duration = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : nil
            eventSink.onTimelineChanged?(.init(currentTime: currentTime, duration: duration))
        }

        private func handleCommandIfNeeded(from controller: PlayerController) {
            guard controller.commandRevision != lastHandledCommandRevision,
                  let command = controller.latestCommand else {
                return
            }
            lastHandledCommandRevision = controller.commandRevision

            switch command {
            case .togglePlayPause:
                if state == .playing {
                    player?.pause()
                } else {
                    playAtCurrentRate()
                }
            case let .setPaused(paused):
                if paused {
                    player?.pause()
                } else {
                    playAtCurrentRate()
                }
            case let .setRate(rate):
                currentPlaybackRate = rate
                if state == .playing {
                    player?.rate = Float(rate)
                }
            case let .seekBy(delta):
                guard let player else { return }
                let current = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
                let target = max(current + delta, 0)
                player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
            case let .seekTo(time):
                player?.seek(to: CMTime(seconds: max(time, 0), preferredTimescale: 600))
            }
        }

        private func playAtCurrentRate() {
            guard let player else { return }
            player.play()
            if currentPlaybackRate != 1 {
                player.rate = Float(currentPlaybackRate)
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

extension AVFoundationPlayerView.Coordinator: PlayerBackendRenderer {
    static var backend: PlayerBackendKind { .avFoundation }
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
