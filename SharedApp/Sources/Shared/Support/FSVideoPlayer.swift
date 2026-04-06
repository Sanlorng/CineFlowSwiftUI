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

struct FSVideoPlayer {
    // The default distributable backend stays on Apple's system player APIs.
    var coordinator: Coordinator
    let url: URL
    let options: FSPlayerOptions
    let externalSubtitle: ExternalSubtitle?
    let allowEmbeddedSubtitles: Bool
    let selectedEmbeddedSubtitleStreamIndex: Int?

    struct ExternalSubtitle: Equatable {
        let fileName: String
        let content: String
    }

    init(
        coordinator: Coordinator,
        url: URL,
        options: FSPlayerOptions,
        externalSubtitle: ExternalSubtitle? = nil,
        allowEmbeddedSubtitles: Bool = true,
        selectedEmbeddedSubtitleStreamIndex: Int? = nil
    ) {
        self.coordinator = coordinator
        self.url = url
        self.options = options
        self.externalSubtitle = externalSubtitle
        self.allowEmbeddedSubtitles = allowEmbeddedSubtitles
        self.selectedEmbeddedSubtitleStreamIndex = selectedEmbeddedSubtitleStreamIndex
    }
}

extension FSVideoPlayer: PlatformViewRepresentable {
    func makeCoordinator() -> Coordinator {
        coordinator
    }

#if canImport(UIKit)
    func makeUIView(context: Context) -> PlayerContainerView {
        context.coordinator.makeView(url: url, options: options)
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        context.coordinator.updateView(view: view, url: url, options: options)
    }

    static func dismantleUIView(_ view: PlayerContainerView, coordinator: Coordinator) {
        coordinator.resetPlayer()
    }
#elseif canImport(AppKit)
    func makeNSView(context: Context) -> PlayerContainerView {
        context.coordinator.makeView(url: url, options: options)
    }

    func updateNSView(_ view: PlayerContainerView, context: Context) {
        context.coordinator.updateView(view: view, url: url, options: options)
    }

    static func dismantleNSView(_ view: PlayerContainerView, coordinator: Coordinator) {
        coordinator.resetPlayer()
    }
#endif
}

@MainActor
extension FSVideoPlayer {
    @MainActor
    final class Coordinator: NSObject, ObservableObject, @unchecked Sendable {
        enum State: Equatable {
            case idle
            case preparing
            case buffering
            case playing
            case paused
            case stopped
            case completed
            case error(String?)
        }

        var onStateChanged: ((Coordinator, State) -> Void)?
        var onFinish: ((Coordinator, Error?) -> Void)?
        var onPlaybackTimeChanged: ((Coordinator, TimeInterval) -> Void)?

        private(set) var state: State = .idle {
            didSet {
                guard state != oldValue else { return }
                onStateChanged?(self, state)
            }
        }

        private weak var view: PlayerContainerView?
        private var player: AVPlayer?
        private var playerItem: AVPlayerItem?
        private var currentURL: URL?
        private var currentOptions: FSPlayerOptions?
        private var statusObservation: NSKeyValueObservation?
        private var timeControlObservation: NSKeyValueObservation?
        private var bufferEmptyObservation: NSKeyValueObservation?
        private var likelyToKeepUpObservation: NSKeyValueObservation?
        private var periodicTimeObserver: Any?
        private var notificationTokens: [NSObjectProtocol] = []

        func makeView(url: URL, options: FSPlayerOptions) -> PlayerContainerView {
            let view = PlayerContainerView(frame: .zero)
            self.view = view
            attachPlayer(to: view, url: url, options: options)
            return view
        }

        func updateView(view: PlayerContainerView, url: URL, options: FSPlayerOptions) {
            self.view = view

            if url != currentURL {
                attachPlayer(to: view, url: url, options: options)
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
            currentURL = nil
            currentOptions = nil
            view?.attach(player: nil)
            if state != .idle {
                state = .stopped
            }
        }

        private func attachPlayer(to view: PlayerContainerView, url: URL, options: FSPlayerOptions) {
            clearObservers()

            currentURL = url
            currentOptions = options
            state = .preparing

            let asset = AVURLAsset(url: url)
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

        private func observe(player: AVPlayer, item: AVPlayerItem, options: FSPlayerOptions) {
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
                        self.onFinish?(self, item.error)
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
                    self.onPlaybackTimeChanged?(self, time.seconds.isFinite ? time.seconds : 0)
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
                        self.onFinish?(self, nil)
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
                        self.onFinish?(self, error)
                    }
                }
            )
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

@MainActor
extension FSVideoPlayer {
    func onStateChanged(_ handler: @escaping (Coordinator, Coordinator.State) -> Void) -> FSVideoPlayer {
        coordinator.onStateChanged = handler
        return self
    }

    func onFinish(_ handler: @escaping (Coordinator, Error?) -> Void) -> FSVideoPlayer {
        coordinator.onFinish = handler
        return self
    }

    func onPlaybackTimeChanged(_ handler: @escaping (Coordinator, TimeInterval) -> Void) -> FSVideoPlayer {
        coordinator.onPlaybackTimeChanged = handler
        return self
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
