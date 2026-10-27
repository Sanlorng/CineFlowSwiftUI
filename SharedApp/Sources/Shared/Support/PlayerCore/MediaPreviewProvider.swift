import Foundation
import CoreGraphics
#if canImport(SubtitleFFmpegBridge)
import SubtitleFFmpegBridge
#endif

struct PlayerChapter: Equatable, Identifiable, Sendable {
    let id: Int
    let title: String
    let time: TimeInterval

    static func normalized(_ chapters: [Self]) -> [Self] {
        chapters.filter { $0.time.isFinite && $0.time >= 0 }
            .sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
    }

    static func current(in chapters: [Self], at time: TimeInterval) -> Self? {
        chapters.last { $0.time <= time }
    }
}

struct MediaPreviewImage: @unchecked Sendable {
    let image: CGImage
    let time: TimeInterval
}

#if canImport(SubtitleFFmpegBridge)
/// The C cancellation flag is atomic; the worker retains this owner until I/O ends.
private final class PreviewRequest: @unchecked Sendable {
    let pointer = media_preview_request_create()
    func cancel() { media_preview_request_cancel(pointer) }
    deinit { media_preview_request_free(pointer) }
}

private actor MediaPreviewWorker {
    static let shared = MediaPreviewWorker()

    private func input<T>(_ source: PlayerSource, body: (UnsafePointer<CChar>, UnsafePointer<CChar>, Int32) -> T) -> T {
        let headers = source.headers.sorted { $0.key < $1.key }
            .filter { !$0.key.contains("\r") && !$0.key.contains("\n") && !$0.value.contains("\r") && !$0.value.contains("\n") }
            .map { "\($0.key): \($0.value)\r\n" }.joined()
        let url = source.url.isFileURL ? source.url.path : source.url.absoluteString
        return url.withCString { url in
            headers.withCString { headers in
                body(url, headers, MediaNetworkPolicy.shouldBypassProxy(for: source.url) ? 1 : 0)
            }
        }
    }

    func chapters(source: PlayerSource, request: PreviewRequest) -> [PlayerChapter] {
        input(source) { url, headers, bypass in
            var items: UnsafeMutablePointer<MediaPreviewChapter>?
            var count: Int32 = 0
            defer { media_preview_chapters_free(items, count) }
            guard media_preview_chapters(request.pointer, url, headers, bypass, &items, &count) == 0,
                  let items else { return [] }
            return PlayerChapter.normalized((0..<Int(count)).map { index in
                let item = items[index]
                let title = item.title.map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
                return .init(id: index, title: title ?? "章节 \(index + 1)", time: item.time)
            })
        }
    }

    func frame(source: PlayerSource, time: TimeInterval, request: PreviewRequest) -> MediaPreviewImage? {
        input(source) { url, headers, bypass in
            var frame = MediaPreviewFrame()
            defer { media_preview_frame_free(&frame) }
            guard media_preview_frame(request.pointer, url, headers, bypass, time, &frame) == 0,
                  let pixels = frame.pixels, frame.width > 0, frame.height > 0 else { return nil }
            let data = Data(bytes: pixels, count: Int(frame.width * frame.height * 4))
            guard let provider = CGDataProvider(data: data as CFData),
                  let image = CGImage(width: Int(frame.width), height: Int(frame.height),
                                      bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Int(frame.width * 4),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            else { return nil }
            return .init(image: image, time: frame.time)
        }
    }
}
#endif

enum MediaPreviewProvider {
    static func chapters(source: PlayerSource) async -> [PlayerChapter] {
#if canImport(SubtitleFFmpegBridge)
        let request = PreviewRequest()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return [] }
            return await MediaPreviewWorker.shared.chapters(source: source, request: request)
        } onCancel: { request.cancel() }
#else
        return []
#endif
    }

    static func frame(source: PlayerSource, time: TimeInterval) async -> MediaPreviewImage? {
#if canImport(SubtitleFFmpegBridge)
        let request = PreviewRequest()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return nil }
            return await MediaPreviewWorker.shared.frame(source: source, time: time, request: request)
        } onCancel: { request.cancel() }
#else
        return nil
#endif
    }
}
