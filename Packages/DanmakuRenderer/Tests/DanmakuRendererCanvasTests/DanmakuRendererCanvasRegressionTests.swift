import Foundation
import Testing
@testable import DanmakuRendererCanvas

struct DanmakuRendererCanvasRegressionTests {
    @Test
    func overlayDoesNotReintroduceLegacyDrawableOwnershipAPIs() throws {
        let source = try String(contentsOf: overlaySourceURL(), encoding: .utf8)

        // CAMetalDisplayLink owns drawable delivery and display timing.
        #expect(source.contains("nextDrawable(") == false)
        #expect(source.contains("present(drawable, atTime:") == false)
    }

    private func overlaySourceURL() -> URL {
        let testFileURL = URL(fileURLWithPath: #filePath)
        return testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
            .appendingPathComponent("DanmakuRendererCanvas")
            .appendingPathComponent("DanmakuRendererOverlay.swift")
    }
}
