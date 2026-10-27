import AVFoundation
import Foundation
import Testing
@testable import Shared

struct MediaPreviewTests {
    @Test func chapterOrderingAndBoundaries() {
        let chapters = PlayerChapter.normalized([
            .init(id: 2, title: "Ending", time: 90),
            .init(id: 1, title: "Opening", time: 0),
            .init(id: 3, title: "Invalid", time: .nan)
        ])
        #expect(chapters.map(\.id) == [1, 2])
        #expect(PlayerChapter.current(in: chapters, at: 89)?.id == 1)
        #expect(PlayerChapter.current(in: chapters, at: 90)?.id == 2)
        #expect(PlayerChapter.current(in: [], at: 0) == nil)
    }

    @Test func generatesThumbnailFromRealVideo() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 48
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                         kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), 128, CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        for index in 0..<30 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(input.isReadyForMoreMediaData)
            #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
        let frame = await MediaPreviewProvider.frame(source: .init(url: url), time: 1)
        let image = try #require(frame)
        #expect(image.image.width > 0 && image.image.width <= 320)
        #expect(image.image.height > 0 && image.image.height <= 180)
        #expect(abs(image.time - 1) < 0.2)
        #expect(await MediaPreviewProvider.chapters(source: .init(url: url)).isEmpty)
    }

    @Test func readsEmbeddedMatroskaChapters() async throws {
        func element(_ id: [UInt8], _ data: [UInt8]) -> [UInt8] {
            let length: [UInt8] = data.count < 127 ? [UInt8(data.count) | 0x80] : [0x40 | UInt8(data.count >> 8), UInt8(data.count & 255)]
            return id + length + data
        }
        func uint(_ id: [UInt8], _ n: UInt64) -> [UInt8] {
            element(id, (0..<8).reversed().map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) })
        }
        func chapter(_ time: UInt64, _ title: String, _ id: UInt64) -> [UInt8] {
            element([0xB6], uint([0x73, 0xC4], id) + uint([0x91], time) + element([0x80], element([0x85], Array(title.utf8))))
        }
        let header = element([0x1A,0x45,0xDF,0xA3], element([0x42,0x82], Array("matroska".utf8)) + element([0x42,0x87], [4]) + element([0x42,0x85], [2]))
        let info = element([0x15,0x49,0xA9,0x66], uint([0x2A,0xD7,0xB1], 1_000_000))
        let tracks = element([0x16,0x54,0xAE,0x6B], element([0xAE], element([0xD7],[1]) + element([0x73,0xC5],[1]) + element([0x83],[1]) + element([0x86],Array("V_VP8".utf8)) + element([0xE0],element([0xB0],[64]) + element([0xBA],[48]))))
        let chapters = element([0x10,0x43,0xA7,0x70], element([0x45,0xB9], chapter(0,"Opening",1) + chapter(90_000_000_000,"Ending",2)))
        let cluster = element([0x1F,0x43,0xB6,0x75], element([0xE7],[0]) + element([0xA3],[0x81,0,0,0x80,0]))
        let data = Data(header + [0x18,0x53,0x80,0x67,0xFF] + info + tracks + chapters + cluster)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chapters-\(UUID()).mkv")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let result = await MediaPreviewProvider.chapters(source: .init(url: url))
        #expect(result.map(\.title) == ["Opening", "Ending"])
        #expect(result.map(\.time) == [0, 90])
    }
}
