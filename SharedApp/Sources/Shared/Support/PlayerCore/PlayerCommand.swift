import Foundation

enum PlayerCommand: Sendable {
    case togglePlayPause
    case setPaused(Bool)
    case seekBy(TimeInterval)
    case seekTo(TimeInterval)
}
