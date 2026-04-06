import Foundation

struct PlayerTimeline: Equatable, Sendable {
    var currentTime: TimeInterval
    var duration: TimeInterval?

    init(currentTime: TimeInterval = 0, duration: TimeInterval? = nil) {
        self.currentTime = currentTime
        self.duration = duration
    }
}
