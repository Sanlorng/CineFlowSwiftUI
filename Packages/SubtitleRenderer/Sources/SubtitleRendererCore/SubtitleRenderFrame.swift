import CoreGraphics
import Foundation

public struct SubtitleViewport: Equatable {
    public var size: CGSize
    public var scale: CGFloat

    public init(size: CGSize, scale: CGFloat = 1) {
        self.size = size
        self.scale = scale
    }
}

public struct SubtitleRenderFrame {
    public var image: CGImage
    public var viewport: SubtitleViewport
    public var timestamp: TimeInterval

    public init(
        image: CGImage,
        viewport: SubtitleViewport,
        timestamp: TimeInterval
    ) {
        self.image = image
        self.viewport = viewport
        self.timestamp = timestamp
    }
}
