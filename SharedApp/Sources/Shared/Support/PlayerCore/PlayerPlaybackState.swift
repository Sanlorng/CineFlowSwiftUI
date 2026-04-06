import Foundation

enum PlayerPlaybackState: Equatable, Sendable {
    case idle
    case preparing
    case buffering
    case playing
    case paused
    case stopped
    case completed
    case error(String?)
}
