import Testing
@testable import DanmakuRendererCore

struct DanmakuDocumentTests {
    @Test
    func timeQueriesUseSortedTimeline() {
        let document = DanmakuDocument(
            comments: [
                .init(id: 0, appearTime: 1.9, mode: .scroll, fontSize: 25, colorRGB: 0xFFFFFF, text: "4", rawParameter: ""),
                .init(id: 1, appearTime: 0.2, mode: .scroll, fontSize: 25, colorRGB: 0xFFFFFF, text: "1", rawParameter: ""),
                .init(id: 2, appearTime: 1.1, mode: .top, fontSize: 25, colorRGB: 0xFFFFFF, text: "3", rawParameter: ""),
                .init(id: 3, appearTime: 0.75, mode: .bottom, fontSize: 25, colorRGB: 0xFFFFFF, text: "2", rawParameter: "")
            ]
        )

        #expect(document.comments.map(\.text) == ["1", "2", "3", "4"])
        #expect(document.lowerBound(for: 0.75) == 1)
        #expect(document.upperBound(for: 0.75) == 2)
        #expect(document.comments(in: 0.5...1.4).map(\.text) == ["2", "3"])
        #expect(document.comments(in: 2.5...4).isEmpty)
    }

    @Test
    func advancedLifetimeAccountsForMotionDelay() {
        let payload = DanmakuAdvancedPayload(
            rawJSON: "{}",
            text: "move",
            startX: 0,
            startY: 0,
            endX: 1,
            endY: 1,
            lifetime: 2,
            translationDuration: 4,
            translationDelay: 1
        )

        let comment = DanmakuComment(
            id: 0,
            appearTime: 0,
            mode: .advanced,
            fontSize: 32,
            colorRGB: 0xFFFFFF,
            text: "move",
            rawParameter: "",
            advancedPayload: payload
        )

        #expect(comment.visibilityWindow == 5)
    }
}
