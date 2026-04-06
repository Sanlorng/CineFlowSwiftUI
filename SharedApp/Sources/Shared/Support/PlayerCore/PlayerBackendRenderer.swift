import Foundation
import SwiftUI

struct PlayerBackendEventSink {
    var onStateChanged: ((PlayerPlaybackState) -> Void)?
    var onFinish: ((Error?) -> Void)?
    var onPlaybackTimeChanged: ((TimeInterval) -> Void)?
    var onTimelineChanged: ((PlayerTimeline) -> Void)?
    var onTracksChanged: (([PlayerTrack]) -> Void)?

    init(
        onStateChanged: ((PlayerPlaybackState) -> Void)? = nil,
        onFinish: ((Error?) -> Void)? = nil,
        onPlaybackTimeChanged: ((TimeInterval) -> Void)? = nil,
        onTimelineChanged: ((PlayerTimeline) -> Void)? = nil,
        onTracksChanged: (([PlayerTrack]) -> Void)? = nil
    ) {
        self.onStateChanged = onStateChanged
        self.onFinish = onFinish
        self.onPlaybackTimeChanged = onPlaybackTimeChanged
        self.onTimelineChanged = onTimelineChanged
        self.onTracksChanged = onTracksChanged
    }
}

@MainActor
protocol PlayerBackendRenderer: AnyObject, ObservableObject {
    associatedtype SurfaceView

    static var backend: PlayerBackendKind { get }
    var capabilities: PlayerBackendCapabilities { get }

    init(eventSink: PlayerBackendEventSink)

    func makeView(source: PlayerSource, controller: PlayerController, options: PlayerLoadOptions) -> SurfaceView
    func updateView(view: SurfaceView, source: PlayerSource, controller: PlayerController, options: PlayerLoadOptions)
    func reset()
}
