import Testing
@testable import DanmakuRendererCore

struct BilibiliDanmakuParserTests {
    @Test
    func parsesBasicBilibiliXML() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <i>
          <d p="1.25,1,25,16777215,0,0,0,0">第一条弹幕</d>
          <d p="3.5,5,36,16711680,0,0,0,0">第二条弹幕</d>
        </i>
        """

        let document = try BilibiliDanmakuParser.parse(xml: xml)

        #expect(document.comments.count == 2)
        #expect(document.comments[0].mode == .scroll)
        #expect(document.comments[0].text == "第一条弹幕")
        #expect(document.comments[1].mode == .top)
        #expect(document.comments[1].colorRGB == 16_711_680)
    }
}
