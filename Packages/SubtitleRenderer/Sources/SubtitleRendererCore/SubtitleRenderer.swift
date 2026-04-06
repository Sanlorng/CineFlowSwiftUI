import Foundation

public protocol SubtitleRenderingBackend: AnyObject {
    var viewport: SubtitleViewport { get }

    func updateDocument(_ document: SubtitleDocument) throws
    func updateViewport(_ viewport: SubtitleViewport) throws
    func renderFrame(at time: TimeInterval) throws -> SubtitleRenderFrame?
}
