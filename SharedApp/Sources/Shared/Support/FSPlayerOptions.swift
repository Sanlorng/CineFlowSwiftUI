import Foundation

struct FSPlayerOptions: Equatable {
    var headers: [String: String]
    var enableHardwareDecoding: Bool
    var allowAutoPlay: Bool
    var playbackTimeNotificationInterval: TimeInterval

    init(
        headers: [String: String] = [:],
        enableHardwareDecoding: Bool = true,
        allowAutoPlay: Bool = true,
        playbackTimeNotificationInterval: TimeInterval = 1 / 30
    ) {
        self.headers = headers
        self.enableHardwareDecoding = enableHardwareDecoding
        self.allowAutoPlay = allowAutoPlay
        self.playbackTimeNotificationInterval = playbackTimeNotificationInterval
    }
}
