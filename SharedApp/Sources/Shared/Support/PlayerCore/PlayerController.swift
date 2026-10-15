import Foundation
import Combine

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var playbackState: PlayerPlaybackState = .idle
    @Published private(set) var timeline = PlayerTimeline()
    @Published private(set) var playbackRate: Double = 1
    @Published private(set) var volume: Double = 1
    @Published private(set) var videoPresentationSize: CGSize?

    @Published private(set) var commandRevision: UInt64 = 0
    private var pendingCommands: [PlayerCommand] = []

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

    func setVolume(_ volume: Double) {
        let sanitized = min(max(volume, 0), 1)
        self.volume = sanitized
        send(.setVolume(sanitized))
    }

    func adjustVolume(by delta: Double) {
        setVolume(volume + delta)
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
        pendingCommands.removeAll()
    }

    /// A view update may coalesce several commands. Consume the complete batch in order.
    func takePendingCommands() -> [PlayerCommand] {
        let commands = pendingCommands
        pendingCommands.removeAll(keepingCapacity: true)
        return commands
    }

    private func send(_ command: PlayerCommand) {
        pendingCommands.append(command)
        commandRevision &+= 1
    }
}
