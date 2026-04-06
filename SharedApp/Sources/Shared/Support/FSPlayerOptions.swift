import Foundation
import FSPlayer

struct FSPlayerOptions: Equatable {
    enum SubtitleLayout: Int, CaseIterable, Hashable {
        case standard
        case bilingual
    }

    var headers: [String: String]
    var enableHardwareDecoding: Bool
    var allowAutoPlay: Bool
    var subtitleLayout: SubtitleLayout
    var forceOverrideEmbeddedStyling: Bool

    init(
        headers: [String: String] = [:],
        enableHardwareDecoding: Bool = true,
        allowAutoPlay: Bool = true,
        subtitleLayout: SubtitleLayout = .standard,
        forceOverrideEmbeddedStyling: Bool = false
    ) {
        self.headers = headers
        self.enableHardwareDecoding = enableHardwareDecoding
        self.allowAutoPlay = allowAutoPlay
        self.subtitleLayout = subtitleLayout
        self.forceOverrideEmbeddedStyling = forceOverrideEmbeddedStyling
    }

    func makeOptions() -> FSOptions {
        let options = FSOptions.byDefault()
        options.showHudView = false
#if os(macOS)
        options.metalRenderer = true
#endif
        if !headers.isEmpty {
            let headerLines = headers
                .map { "\($0): \($1)" }
                .joined(separator: "\r\n")
            options.setFormatOptionValue("\(headerLines)\r\n", forKey: "headers")
        }
        if enableHardwareDecoding {
            options.setPlayerOptionIntValue(1, forKey: "videotoolbox")
        } else {
            options.setPlayerOptionIntValue(0, forKey: "videotoolbox")
        }
        options.setFormatOptionIntValue(1, forKey: "reconnect")
        options.setFormatOptionIntValue(1, forKey: "reconnect_streamed")
        return options
    }

    func makeSubtitlePreference(
        for subtitleFileName: String?,
        codecName: String? = nil,
        isEmbedded: Bool = false
    ) -> FSSubtitlePreference {
        var preference = fs_subtitle_default_preference()
        preference.ForceOverride = 0
        return preference
    }
}
