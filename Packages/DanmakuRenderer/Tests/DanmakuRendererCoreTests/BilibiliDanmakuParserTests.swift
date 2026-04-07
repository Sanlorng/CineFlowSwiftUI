import CoreGraphics
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

    @Test
    func parsesAdvancedDanmakuPayload() throws {
        let xml = """
        <i>
          <d p="8.5,7,32,16777215,0,0,0,0">[0.1,0.25,"0.4-1",6,"高级弹幕",15,0,0.8,0.75,3,0.5,true,"Hiragino Sans GB","ease-in-out","M0.1,0.25L0.4,0.6L0.8,0.75"]</d>
        </i>
        """

        let document = try BilibiliDanmakuParser.parse(xml: xml)
        let comment = try #require(document.comments.first)
        let payload = try #require(comment.advancedPayload)

        #expect(comment.mode == .advanced)
        #expect(comment.text == "高级弹幕")
        #expect(payload.text == "高级弹幕")
        #expect(payload.motionCurve == .easeInOut)
        #expect(payload.translationDuration == 3)
        #expect(payload.translationDelay == 0.5)
        #expect(payload.rotationZ == 15)
        #expect(payload.fontFamily == "Hiragino Sans GB")
        #expect(payload.usesStroke == true)
        #expect(payload.path?.count == 3)
        #expect(payload.path?.last == CGPoint(x: 0.8, y: 0.75))
        #expect(comment.visibilityWindow == 6)
    }
}
