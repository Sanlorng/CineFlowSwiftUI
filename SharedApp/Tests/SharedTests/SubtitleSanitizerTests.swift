import Testing
@testable import Shared

struct SubtitleSanitizerTests {
    @Test
    func prepareForFSPlayerMergesTypicalJPSCAss() {
        let input = """
        [Script Info]
        ScriptType: v4.00+

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,36,&H14FFFFFF,&H000000FF,&H14211711,&H00000000,0,0,0,0,100,100,0,0,1,2.8,0,2,10,10,20,1
        Style: Dial_JP,Arial,36,&H14FFFFFF,&H000000FF,&H14211711,&H00000000,0,0,0,0,100,100,0,0,1,2.5,0,2,10,10,10,1
        Style: Dial_CH,Arial,40,&H14FFFFFF,&H000000FF,&H14211711,&H00000000,0,0,0,0,100,100,0,0,1,2.8,0,2,10,10,60,1
        Style: Screen,Arial,32,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,2,10,10,10,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:02.00,Dial_JP,,0,0,0,,こんにちは
        Dialogue: 0,0:00:01.00,0:00:02.00,Dial_CH,,0,0,0,,你好
        Dialogue: 0,0:00:03.00,0:00:04.00,Screen,,0,0,0,,标牌
        """

        let output = SubtitleSanitizer.prepareForFSPlayer(
            rawText: input,
            fileName: "sample.JPSC.ass"
        )

        #expect(output.contains("{\\rDial_JP}こんにちは\\N{\\rDial_CH}你好"))
        #expect(output.contains("Dialogue: 0,0:00:03.00,0:00:04.00,Screen,,0,0,0,,标牌"))
        #expect(output.split(separator: "\n").filter { $0.hasPrefix("Dialogue:") }.count == 2)
    }

    @Test
    func prepareForFSPlayerKeepsNonAssUntouched() {
        let input = """
        1
        00:00:01,000 --> 00:00:02,000
        Hello
        """

        let output = SubtitleSanitizer.prepareForFSPlayer(
            rawText: input,
            fileName: "sample.srt"
        )

        #expect(output == input)
    }
}
