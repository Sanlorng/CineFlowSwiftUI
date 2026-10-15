import Foundation

struct PlaybackAttachmentContext: Equatable {
    let id: UUID
    let configuration: MediaLibraryConfiguration
    let item: PlaybackItem?
    var capabilities = PlayerBackendKind.defaultDistributable.capabilities
}
