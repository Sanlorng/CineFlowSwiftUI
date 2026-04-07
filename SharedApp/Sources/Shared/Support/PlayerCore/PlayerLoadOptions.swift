import Foundation

struct PlayerLoadOptions: Equatable, Sendable {
    var headers: [String: String]
    var enableHardwareDecoding: Bool
    var allowAutoPlay: Bool
    var playbackTimeNotificationInterval: TimeInterval
    var selectedAudioTrackID: String?
    var selectedEmbeddedSubtitleTrackID: String?

    init(
        headers: [String: String] = [:],
        enableHardwareDecoding: Bool = true,
        allowAutoPlay: Bool = true,
        playbackTimeNotificationInterval: TimeInterval = 1 / 30,
        selectedAudioTrackID: String? = nil,
        selectedEmbeddedSubtitleTrackID: String? = nil
    ) {
        self.headers = headers
        self.enableHardwareDecoding = enableHardwareDecoding
        self.allowAutoPlay = allowAutoPlay
        self.playbackTimeNotificationInterval = playbackTimeNotificationInterval
        self.selectedAudioTrackID = selectedAudioTrackID
        self.selectedEmbeddedSubtitleTrackID = selectedEmbeddedSubtitleTrackID
    }
}
