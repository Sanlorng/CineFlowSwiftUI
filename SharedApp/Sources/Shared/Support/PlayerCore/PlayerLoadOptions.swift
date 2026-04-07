import Foundation

struct PlayerLoadOptions: Equatable, Sendable {
    var headers: [String: String]
    var enableHardwareDecoding: Bool
    var allowAutoPlay: Bool
    var playbackTimeNotificationInterval: TimeInterval
    var selectedAudioTrackID: String?
    var selectedEmbeddedSubtitleTrackID: String?
    var subtitleTimeOffset: TimeInterval
    var subtitleFontSize: Double
    var subtitleFontFamily: String?

    init(
        headers: [String: String] = [:],
        enableHardwareDecoding: Bool = true,
        allowAutoPlay: Bool = true,
        playbackTimeNotificationInterval: TimeInterval = 1 / 30,
        selectedAudioTrackID: String? = nil,
        selectedEmbeddedSubtitleTrackID: String? = nil,
        subtitleTimeOffset: TimeInterval = 0,
        subtitleFontSize: Double = 54,
        subtitleFontFamily: String? = nil
    ) {
        self.headers = headers
        self.enableHardwareDecoding = enableHardwareDecoding
        self.allowAutoPlay = allowAutoPlay
        self.playbackTimeNotificationInterval = playbackTimeNotificationInterval
        self.selectedAudioTrackID = selectedAudioTrackID
        self.selectedEmbeddedSubtitleTrackID = selectedEmbeddedSubtitleTrackID
        self.subtitleTimeOffset = subtitleTimeOffset
        self.subtitleFontSize = subtitleFontSize
        self.subtitleFontFamily = subtitleFontFamily
    }
}
