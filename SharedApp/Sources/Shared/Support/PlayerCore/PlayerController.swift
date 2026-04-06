import Foundation
import Combine

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var playbackState: PlayerPlaybackState = .idle
    @Published private(set) var timeline = PlayerTimeline()
    @Published private(set) var playbackRate: Double = 1
    @Published private(set) var videoPresentationSize: CGSize?

    @Published private(set) var commandRevision: UInt64 = 0
    @Published private(set) var latestCommand: PlayerCommand?

    var isPlaying: Bool {
        playbackState == .playing
    }

    func togglePlayPause() {
        send(.togglePlayPause)
    }

    func setPaused(_ paused: Bool) {
        send(.setPaused(paused))
    }

    func seekBy(_ delta: TimeInterval) {
        send(.seekBy(delta))
    }

    func seekTo(_ time: TimeInterval) {
        send(.seekTo(time))
    }

    func setPlaybackRate(_ rate: Double) {
        let sanitized = max(rate, 0.25)
        playbackRate = sanitized
        send(.setRate(sanitized))
    }

    func updatePlaybackState(_ state: PlayerPlaybackState) {
        playbackState = state
    }

    func updateTimeline(currentTime: TimeInterval, duration: TimeInterval?) {
        timeline = .init(currentTime: max(currentTime, 0), duration: duration)
    }

    func updateVideoPresentationSize(_ size: CGSize?) {
        guard let size,
              size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            videoPresentationSize = nil
            return
        }
        videoPresentationSize = size
    }

    func reset() {
        playbackState = .idle
        timeline = .init()
        playbackRate = 1
        videoPresentationSize = nil
        latestCommand = nil
    }

    private func send(_ command: PlayerCommand) {
        latestCommand = command
        commandRevision &+= 1
    }
}
