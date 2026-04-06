import Testing
@testable import SubtitleRendererCore

@Test
func assFactoryPreservesFormatAndFileName() {
    let document = SubtitleDocument.ass("test", fileName: "demo.ass")

    #expect(document.format == .ass)
    #expect(document.text == "test")
    #expect(document.fileName == "demo.ass")
}

@Test
func detectingRecognizesSubripAndWebVTT() {
    let srt = SubtitleDocument.detecting(
        rawText: "1\n00:00:01,000 --> 00:00:02,000\nhello\n",
        fileName: "demo.srt"
    )
    let vtt = SubtitleDocument.detecting(
        rawText: "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nhello\n",
        fileName: "demo.vtt"
    )

    #expect(srt?.format == .srt)
    #expect(vtt?.format == .webvtt)
}
