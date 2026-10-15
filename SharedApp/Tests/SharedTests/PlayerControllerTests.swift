import Testing
@testable import Shared

@MainActor
struct PlayerControllerTests {
    @Test
    func repeatPlaybackSeeksBeforeResumingInOneViewUpdate() {
        let controller = PlayerController()
        controller.seekTo(0)
        controller.setPaused(false)

        #expect(controller.takePendingCommands() == [.seekTo(0), .setPaused(false)])
        #expect(controller.takePendingCommands().isEmpty)
    }

    @Test
    func rapidRelativeSeeksAreNotCoalesced() {
        let controller = PlayerController()
        controller.seekBy(5)
        controller.seekBy(5)
        controller.seekBy(-5)

        #expect(controller.takePendingCommands() == [.seekBy(5), .seekBy(5), .seekBy(-5)])
    }

    @Test
    func newPlaybackContextDiscardsUnconsumedCommands() {
        let controller = PlayerController()
        controller.seekTo(100)
        controller.reset()
        controller.setPaused(false)

        #expect(controller.takePendingCommands() == [.setPaused(false)])
    }
}
