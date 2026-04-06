import CoreGraphics
import Testing
@testable import SubtitleRendererCore
@testable import SubtitleRendererLibass

@Test
func libassRendererProducesVisiblePixelsForSimpleASS() throws {
    let renderer = try LibassRenderer(
        viewport: SubtitleViewport(size: CGSize(width: 640, height: 360))
    )

    try renderer.updateDocument(.ass(LibassRendererFixture.ass))
    let renderedFrame = try renderer.renderFrame(at: 0.5)
    let frame = try #require(renderedFrame)

    #expect(frame.image.width == 640)
    #expect(frame.image.height == 360)
    #expect(alphaSum(of: frame.image) > 0)
}

@Test
func libassRendererProducesVisiblePixelsForSimpleSRT() throws {
    let renderer = try LibassRenderer(
        viewport: SubtitleViewport(size: CGSize(width: 640, height: 360))
    )

    try renderer.updateDocument(.srt(LibassRendererFixture.srt, fileName: "demo.srt"))
    let renderedFrame = try renderer.renderFrame(at: 1.2)
    let frame = try #require(renderedFrame)

    #expect(alphaSum(of: frame.image) > 0)
}

private func alphaSum(of image: CGImage) -> Int {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)

    guard let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.union(.init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)).rawValue
    ) else {
        return 0
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + Int(bytes[$1]) }
}

private enum LibassRendererFixture {
    static let ass = """
    [Script Info]
    ScriptType: v4.00+
    PlayResX: 640
    PlayResY: 360

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
    Style: Default,Arial,40,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,20,20,20,1

    [Events]
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,Hello from libass
    """

    static let srt = """
    1
    00:00:01,000 --> 00:00:02,000
    Hello from SubRip
    """
}
