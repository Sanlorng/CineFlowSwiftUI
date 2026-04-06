import Foundation
import FSPlayer
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
typealias PlatformView = UIView
#else
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
typealias PlatformView = NSView
#endif

struct FSVideoPlayer {
    var coordinator: Coordinator
    let url: URL
    let options: FSPlayerOptions
    let externalSubtitle: ExternalSubtitle?
    let allowEmbeddedSubtitles: Bool

    struct ExternalSubtitle: Equatable {
        let fileName: String
        let content: String
    }

    init(
        coordinator: Coordinator,
        url: URL,
        options: FSPlayerOptions,
        externalSubtitle: ExternalSubtitle? = nil,
        allowEmbeddedSubtitles: Bool = true
    ) {
        self.coordinator = coordinator
        self.url = url
        self.options = options
        self.externalSubtitle = externalSubtitle
        self.allowEmbeddedSubtitles = allowEmbeddedSubtitles
    }
}

extension FSVideoPlayer: PlatformViewRepresentable {
    func makeCoordinator() -> Coordinator {
        coordinator
    }

#if canImport(UIKit)
    func makeUIView(context: Context) -> PlatformView {
        context.coordinator.makeView(
            url: url,
            options: options,
            externalSubtitle: externalSubtitle,
            allowEmbeddedSubtitles: allowEmbeddedSubtitles
        )
    }

    func updateUIView(_ view: PlatformView, context: Context) {
        context.coordinator.updateView(
            view: view,
            url: url,
            options: options,
            externalSubtitle: externalSubtitle,
            allowEmbeddedSubtitles: allowEmbeddedSubtitles
        )
    }

    static func dismantleUIView(_ view: PlatformView, coordinator: Coordinator) {
        coordinator.resetPlayer()
    }
#else
    func makeNSView(context: Context) -> PlatformView {
        context.coordinator.makeView(
            url: url,
            options: options,
            externalSubtitle: externalSubtitle,
            allowEmbeddedSubtitles: allowEmbeddedSubtitles
        )
    }

    func updateNSView(_ view: PlatformView, context: Context) {
        context.coordinator.updateView(
            view: view,
            url: url,
            options: options,
            externalSubtitle: externalSubtitle,
            allowEmbeddedSubtitles: allowEmbeddedSubtitles
        )
    }

    static func dismantleNSView(_ view: PlatformView, coordinator: Coordinator) {
        coordinator.resetPlayer()
    }
#endif
}

@MainActor
extension FSVideoPlayer {
    @MainActor
    final class Coordinator: NSObject, ObservableObject {
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

        private(set) var state: State = .idle {
            didSet {
                guard state != oldValue else { return }
                onStateChanged?(self, state)
            }
        }

        private var player: FSPlayer?
        private var currentURL: URL?
        private var currentOptions: FSPlayerOptions?
        private var currentSubtitleCodecName: String?
        private var currentExternalSubtitle: ExternalSubtitle?
        private var externalSubtitleFileURL: URL?
        private var allowEmbeddedSubtitles = true

        func makeView(
            url: URL,
            options: FSPlayerOptions,
            externalSubtitle: ExternalSubtitle?,
            allowEmbeddedSubtitles: Bool
        ) -> PlatformView {
#if canImport(UIKit)
            let container = PlatformView(frame: .zero)
            container.backgroundColor = .clear
#else
            let container = PlatformView(frame: .zero)
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.clear.cgColor
#endif
            self.allowEmbeddedSubtitles = allowEmbeddedSubtitles
            attachPlayer(to: container, url: url, options: options)
            handleExternalSubtitleChange(externalSubtitle)
            return container
        }

        func updateView(
            view: PlatformView,
            url: URL,
            options: FSPlayerOptions,
            externalSubtitle: ExternalSubtitle?,
            allowEmbeddedSubtitles: Bool
        ) {
            let allowChanged = allowEmbeddedSubtitles != self.allowEmbeddedSubtitles
            self.allowEmbeddedSubtitles = allowEmbeddedSubtitles

            if url != currentURL {
                attachPlayer(to: view, url: url, options: options)
                handleExternalSubtitleChange(externalSubtitle)
                return
            }

            if currentOptions != options {
                currentOptions = options
                applySubtitlePreference(using: options)
            }

            if allowChanged, allowEmbeddedSubtitles == false {
                disableEmbeddedSubtitles()
            }

            if externalSubtitle != currentExternalSubtitle {
                handleExternalSubtitleChange(externalSubtitle)
            }
        }

        func resetPlayer() {
            removeObservers()
            if let playerView = player?.view as? PlatformView {
                playerView.removeFromSuperview()
            }
            cleanupExternalSubtitleFile()
            player?.shutdown()
            player = nil
            currentURL = nil
            currentOptions = nil
            currentSubtitleCodecName = nil
            currentExternalSubtitle = nil
            externalSubtitleFileURL = nil
            allowEmbeddedSubtitles = true
            if state != .idle {
                state = .stopped
            }
        }

        private func configurePlayer(_ player: FSPlayer, options: FSPlayerOptions) {
            player.shouldAutoplay = options.allowAutoPlay
        }

        private func applySubtitlePreference(using options: FSPlayerOptions) {
            guard let player else { return }
            let preference = options.makeSubtitlePreference(
                for: nil,
                codecName: currentSubtitleCodecName,
                isEmbedded: true
            )
            player.subtitlePreference = preference
#if DEBUG
            let appliedPreference = player.subtitlePreference
            print("[FSVideoPlayer] Applied subtitle preference forceOverride=\(appliedPreference.ForceOverride)")
#endif
            player.view.setNeedsRefreshCurrentPic()
        }

        private func handleExternalSubtitleChange(_ subtitle: ExternalSubtitle?) {
            guard player != nil else {
                currentExternalSubtitle = subtitle
                return
            }
            if currentExternalSubtitle == subtitle {
                return
            }
            currentExternalSubtitle = subtitle
            if let subtitle {
                activateExternalSubtitle(subtitle)
            } else {
                deactivateExternalSubtitle()
            }
        }

        private func activateExternalSubtitle(_ subtitle: ExternalSubtitle) {
            guard let player else { return }
            do {
                cleanupExternalSubtitleFile()
                let fileURL = try writeExternalSubtitle(content: subtitle.content, fileName: subtitle.fileName)
                if player.loadThenActiveSubtitle(fileURL) {
                    externalSubtitleFileURL = fileURL
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            } catch {
#if DEBUG
                print("[FSVideoPlayer] Failed to load external subtitle:", error)
#endif
            }
        }

        private func deactivateExternalSubtitle() {
            guard let player else { return }
            if let fileURL = externalSubtitleFileURL {
                player.closeCurrentStream("timedtext")
                try? FileManager.default.removeItem(at: fileURL)
                externalSubtitleFileURL = nil
            }
        }

        private func disableEmbeddedSubtitles() {
            guard let player else { return }
            if externalSubtitleFileURL == nil {
                player.closeCurrentStream("timedtext")
            }
        }

        private func writeExternalSubtitle(content: String, fileName: String) throws -> URL {
            let directory = try subtitleCacheDirectory()
            let ext = (fileName as NSString).pathExtension
            let targetExtension = ext.isEmpty ? "ass" : ext
            let fileURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(targetExtension)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }

        private func subtitleCacheDirectory() throws -> URL {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("FSPlayerExternalSubtitles", isDirectory: true)
            if !FileManager.default.fileExists(atPath: base.path) {
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            }
            return base
        }

        private func cleanupExternalSubtitleFile() {
            if let fileURL = externalSubtitleFileURL {
                try? FileManager.default.removeItem(at: fileURL)
                externalSubtitleFileURL = nil
            }
        }

        private func attachPlayer(
            to container: PlatformView,
            url: URL,
            options: FSPlayerOptions
        ) {
            resetPlayer()
            currentURL = url
            currentOptions = options

            let fsOptions = options.makeOptions()
            let newPlayer = FSPlayer(contentURL: url, with: fsOptions)

            configurePlayer(newPlayer, options: options)
            attachObservers(to: newPlayer)
            player = newPlayer
            applySubtitlePreference(using: options)
            state = .preparing
            if allowEmbeddedSubtitles == false {
                disableEmbeddedSubtitles()
            }

            container.subviews.forEach { $0.removeFromSuperview() }
            if let playerView = newPlayer.view as? PlatformView {
                playerView.frame = container.bounds
#if canImport(UIKit)
                playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
#else
                playerView.autoresizingMask = [.width, .height]
#endif
                container.addSubview(playerView)
            }
            newPlayer.prepareToPlay()
        }

        private func attachObservers(to player: FSPlayer) {
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(handlePreparedNotification), name: .FSPlayerIsPreparedToPlay, object: player)
            center.addObserver(self, selector: #selector(handleLoadStateNotification), name: .FSPlayerLoadStateDidChange, object: player)
            center.addObserver(self, selector: #selector(handlePlaybackStateNotification), name: .FSPlayerPlaybackStateDidChange, object: player)
            center.addObserver(self, selector: #selector(handleDidFinishNotification(_:)), name: .FSPlayerDidFinish, object: player)
            center.addObserver(self, selector: #selector(handleDecoderFatalNotification(_:)), name: .FSPlayerVideoDecoderFatal, object: player)
            center.addObserver(self, selector: #selector(handleNoCodecNotification(_:)), name: .FSPlayerNoCodecFound, object: player)
            center.addObserver(self, selector: #selector(handleSelectedStreamChanged(_:)), name: .FSPlayerSelectedStreamDidChange, object: player)
        }

        private func removeObservers() {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func handlePreparedNotification(_: Notification) {
            state = .playing
            updateActiveSubtitleCodecIfNeeded()
        }

        @objc private func handleLoadStateNotification(_: Notification) {
            handleLoadStateChange()
        }

        @objc private func handlePlaybackStateNotification(_: Notification) {
            handlePlaybackStateChange()
        }

        @objc private func handleDidFinishNotification(_ notification: Notification) {
            handleFinish(notification: notification)
        }

        @objc private func handleDecoderFatalNotification(_ notification: Notification) {
            handleError(notification: notification, message: "视频解码失败。")
        }

        @objc private func handleNoCodecNotification(_ notification: Notification) {
            handleError(notification: notification, message: "缺少可用的解码器。")
        }

        @objc private func handleSelectedStreamChanged(_: Notification) {
            updateActiveSubtitleCodecIfNeeded()
        }

        private func handleLoadStateChange() {
            guard let player else { return }
            let loadState = player.loadState
            if loadState.contains(.stalled) {
                state = .buffering
            } else if loadState.contains(.playthroughOK) || loadState.contains(.playable) {
                if state != .playing {
                    state = .playing
                }
            }
        }

        private func handlePlaybackStateChange() {
            guard let player else { return }
            switch player.playbackState {
            case .playing:
                state = .playing
            case .paused:
                state = .paused
            case .stopped:
                state = .stopped
            case .interrupted:
                state = .buffering
            case .seekingBackward, .seekingForward:
                state = .buffering
            @unknown default:
                break
            }
        }

        private func handleFinish(notification: Notification) {
            let reasonValue = (notification.userInfo?[FSPlayerDidFinishReasonUserInfoKey] as? NSNumber)?.intValue ?? FSFinishReason.playbackEnded.rawValue
            let reason = FSFinishReason(rawValue: reasonValue) ?? .playbackEnded
            switch reason {
            case .playbackEnded:
                state = .completed
                onFinish?(self, nil)
            case .playbackError:
                let error = notification.userInfo?[NSUnderlyingErrorKey] as? Error
                    ?? notification.userInfo?["error"] as? Error
                    ?? notification.userInfo?[FSPlayerDidSeekCompleteErrorKey] as? Error
                state = .error(error?.localizedDescription ?? "播放失败。")
                onFinish?(self, error)
            case .userExited:
                state = .stopped
                onFinish?(self, nil)
            @unknown default:
                state = .stopped
                onFinish?(self, nil)
            }
        }

        private func handleError(notification: Notification, message: String) {
            let error = notification.userInfo?[NSUnderlyingErrorKey] as? Error
            state = .error(error?.localizedDescription ?? message)
            onFinish?(self, error)
        }

        private func updateActiveSubtitleCodecIfNeeded() {
            let codec = fetchActiveSubtitleCodecName()
            guard codec != currentSubtitleCodecName else { return }
            currentSubtitleCodecName = codec
            if let options = currentOptions {
                applySubtitlePreference(using: options)
            }
        }

        private func fetchActiveSubtitleCodecName() -> String? {
            guard let player else { return nil }
            if let subtitleMeta = player.monitor.subtitleMeta as? [String: Any],
               let codec = extractCodecName(from: subtitleMeta) {
                return codec
            }
            if let mediaMeta = player.monitor.mediaMeta as? [String: Any],
               let streams = mediaMeta["streams"] {
                let list: [[String: Any]]
                if let array = streams as? [[String: Any]] {
                    list = array
                } else if let array = streams as? [Any] {
                    list = array.compactMap { $0 as? [String: Any] }
                } else {
                    list = []
                }
                for stream in list {
                    guard let type = (stream["type"] as? String)?.lowercased(), type == "timedtext" else {
                        continue
                    }
                    if let selected = stream["selected"] as? Bool, selected,
                       let codec = extractCodecName(from: stream) {
                        return codec
                    }
                    if let selected = stream["selected"] as? NSNumber, selected.boolValue,
                       let codec = extractCodecName(from: stream) {
                        return codec
                    }
                }
            }
            return nil
        }

        private func extractCodecName(from dictionary: [String: Any]) -> String? {
            if let codec = dictionary["codec_name"] as? String, !codec.isEmpty {
                return codec
            }
            if let codec = dictionary["codec"] as? String, !codec.isEmpty {
                return codec
            }
            if let format = dictionary["format"] as? String, !format.isEmpty {
                return format
            }
            return nil
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
}
