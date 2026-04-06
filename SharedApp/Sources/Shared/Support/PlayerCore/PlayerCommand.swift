import Foundation

enum PlayerCommand: Sendable {
    case togglePlayPause
    case setPaused(Bool)
    case setRate(Double)
    case seekBy(TimeInterval)
    case seekTo(TimeInterval)
}
