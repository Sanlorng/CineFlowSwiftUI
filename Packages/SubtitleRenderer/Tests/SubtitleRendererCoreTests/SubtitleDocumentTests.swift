import Testing
@testable import SubtitleRendererCore

@Test
func assFactoryPreservesFormatAndFileName() {
    let document = SubtitleDocument.ass("test", fileName: "demo.ass")

    #expect(document.format == .ass)
    #expect(document.text == "test")
    #expect(document.fileName == "demo.ass")
}
