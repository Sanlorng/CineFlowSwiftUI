import Foundation

enum PlayerCommand: Sendable {
    case togglePlayPause
    case setPaused(Bool)
    case setRate(Double)
    case setVolume(Double)
    case seekBy(TimeInterval)
    case seekTo(TimeInterval)
}
