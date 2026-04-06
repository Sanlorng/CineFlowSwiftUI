import Foundation

enum PlayerBackendKind: String, CaseIterable, Sendable {
    case avFoundation
    case mpv

    static var defaultDistributable: Self {
        .avFoundation
    }

    var displayName: String {
        switch self {
        case .avFoundation:
            return "AVFoundation"
        case .mpv:
            return "mpv"
        }
    }

    var capabilities: PlayerBackendCapabilities {
        switch self {
        case .avFoundation:
            return [.playbackRate, .audioTrackSelection]
        case .mpv:
            return [.playbackRate, .audioTrackSelection, .externalSubtitleInjection, .embeddedSubtitleTracks]
        }
    }
}

struct PlayerBackendCapabilities: OptionSet, Sendable {
    let rawValue: UInt32

    static let playbackRate = Self(rawValue: 1 << 0)
    static let audioTrackSelection = Self(rawValue: 1 << 1)
    static let externalSubtitleInjection = Self(rawValue: 1 << 2)
    static let embeddedSubtitleTracks = Self(rawValue: 1 << 3)
}
