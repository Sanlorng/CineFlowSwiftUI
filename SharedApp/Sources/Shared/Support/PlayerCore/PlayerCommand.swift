import Foundation

enum PlayerCommand: Equatable, Sendable {
    case togglePlayPause
    case setPaused(Bool)
    case setRate(Double)
    case setVolume(Double)
    case seekBy(TimeInterval)
    case seekTo(TimeInterval)
}
