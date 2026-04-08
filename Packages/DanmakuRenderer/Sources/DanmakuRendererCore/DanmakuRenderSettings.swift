import Foundation

public struct DanmakuRenderSettings: Equatable, Sendable {
    public var isVisible: Bool
    public var showsPerformanceHUD: Bool
    public var fontScale: Double
    public var opacity: Double
    public var speed: Double
    public var maximumTrackRatio: Double
    public var trackSpacing: Double

    public init(
        isVisible: Bool = true,
        showsPerformanceHUD: Bool = false,
        fontScale: Double = 1.5,
        opacity: Double = 0.9,
        speed: Double = 1,
        maximumTrackRatio: Double = 0.72,
        trackSpacing: Double = 6
    ) {
        self.isVisible = isVisible
        self.showsPerformanceHUD = showsPerformanceHUD
        self.fontScale = fontScale
        self.opacity = opacity
        self.speed = speed
        self.maximumTrackRatio = maximumTrackRatio
        self.trackSpacing = trackSpacing
    }
}
