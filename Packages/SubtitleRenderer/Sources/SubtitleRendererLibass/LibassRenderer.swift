import CLibass
import CoreGraphics
import Foundation
import SubtitleRendererCore

public enum LibassRendererError: Error, Equatable {
    case runtimeUnavailable(String)
    case initializationFailed(String)
    case unsupportedFormat(SubtitleFormat)
    case failedToParseDocument
    case invalidViewport
    case failedToCreateBitmapContext
    case failedToCreateMask
}

public final class LibassRenderer: SubtitleRenderingBackend {
    private static let baseFontSize: Double = 54
    public static var isRuntimeAvailable: Bool {
        (try? LibassRuntime()) != nil
    }

    public private(set) var viewport: SubtitleViewport
    private let runtime: LibassRuntime
    private let library: OpaquePointer
    private let renderer: OpaquePointer
    private var track: UnsafeMutablePointer<ASS_Track>?
    private var lastFrame: SubtitleRenderFrame?
    private var currentDocument: SubtitleDocument?

    public init(
        viewport: SubtitleViewport,
        defaultFontFamily: String? = nil,
        fontSize: Double = 54,
        fontsDirectory: URL? = nil
    ) throws {
        do {
            self.runtime = try LibassRuntime()
        } catch let error as LibassRuntimeError {
            throw LibassRendererError.runtimeUnavailable(String(describing: error))
        }

        guard let libraryPointer = runtime.assLibraryInit() else {
            throw LibassRendererError.initializationFailed("ass_library_init returned nil")
        }
        guard let rendererPointer = runtime.assRendererInit(libraryPointer) else {
            runtime.assLibraryDone(libraryPointer)
            throw LibassRendererError.initializationFailed("ass_renderer_init returned nil")
        }

        library = libraryPointer
        renderer = rendererPointer
        self.viewport = viewport

        runtime.assSetExtractFonts(libraryPointer, 1)
        if let fontsDirectory {
            fontsDirectory.path.withCString { path in
                runtime.assSetFontsDir(libraryPointer, path)
            }
        }

        try applyViewport(viewport)
        try configureFonts(defaultFontFamily: defaultFontFamily)
        applyFontSize(fontSize)
    }

    deinit {
        if let track {
            runtime.assFreeTrack(track)
        }
        runtime.assRendererDone(renderer)
        runtime.assLibraryDone(library)
    }

    public func updateDocument(_ document: SubtitleDocument) throws {
        if let track {
            runtime.assFreeTrack(track)
            self.track = nil
        }

        guard let assText = LibassSubtitleCompiler.compile(document) else {
            throw LibassRendererError.failedToParseDocument
        }

        let utf8 = Array(assText.utf8CString)
        guard let newTrack = utf8.withUnsafeBufferPointer({ buffer -> UnsafeMutablePointer<ASS_Track>? in
            guard let baseAddress = buffer.baseAddress else { return nil }
            let mutable = UnsafeMutablePointer(mutating: baseAddress)
            return runtime.assReadMemory(library, mutable, buffer.count - 1, nil)
        }) else {
            throw LibassRendererError.failedToParseDocument
        }

        track = newTrack
        currentDocument = document
        lastFrame = nil
    }

    public func updateViewport(_ viewport: SubtitleViewport) throws {
        self.viewport = viewport
        try applyViewport(viewport)
        lastFrame = nil
    }

    public func renderFrame(at time: TimeInterval) throws -> SubtitleRenderFrame? {
        guard let track else { return nil }

        var change: Int32 = 0
        let timestamp = Int64((time * 1000).rounded())
        let images = runtime.assRenderFrame(renderer, track, timestamp, &change)

        if change == 0, let lastFrame {
            return lastFrame
        }
        guard let images else {
            lastFrame = nil
            return nil
        }

        let frame = try render(images: images, timestamp: time)
        lastFrame = frame
        return frame
    }

    private func configureFonts(defaultFontFamily: String?) throws {
        let family = (defaultFontFamily?.isEmpty == false ? defaultFontFamily : "sans-serif") ?? "sans-serif"
        family.withCString { familyCString in
            runtime.assSetFonts(
                renderer,
                nil,
                familyCString,
                Int32(ASS_FONTPROVIDER_AUTODETECT.rawValue),
                nil,
                1
            )
        }
    }

    private func applyFontSize(_ fontSize: Double) {
        let normalizedFontSize = max(fontSize, 12)
        let scale = normalizedFontSize / Self.baseFontSize
        runtime.assSetFontScale(renderer, max(scale, 0.25))
    }

    private func applyViewport(_ viewport: SubtitleViewport) throws {
        let pixelWidth = Int((viewport.size.width * viewport.scale).rounded())
        let pixelHeight = Int((viewport.size.height * viewport.scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw LibassRendererError.invalidViewport
        }

        runtime.assSetFrameSize(renderer, Int32(pixelWidth), Int32(pixelHeight))
        runtime.assSetStorageSize(renderer, Int32(pixelWidth), Int32(pixelHeight))
        runtime.assSetUseMargins(renderer, 0)
        runtime.assSetLinePosition(renderer, 0)
        runtime.assSetHinting(renderer, ASS_HINTING_LIGHT)
    }

    private func render(
        images: UnsafeMutablePointer<ASS_Image>,
        timestamp: TimeInterval
    ) throws -> SubtitleRenderFrame {
        let pixelWidth = Int((viewport.size.width * viewport.scale).rounded())
        let pixelHeight = Int((viewport.size.height * viewport.scale).rounded())

        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(.init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw LibassRendererError.failedToCreateBitmapContext
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        var node: UnsafeMutablePointer<ASS_Image>? = images
        while let current = node {
            let image = current.pointee
            if image.w > 0, image.h > 0 {
                try draw(image: image, in: context, canvasHeight: pixelHeight)
            }
            node = image.next
        }

        guard let cgImage = context.makeImage() else {
            throw LibassRendererError.failedToCreateBitmapContext
        }

        return SubtitleRenderFrame(
            image: cgImage,
            viewport: viewport,
            timestamp: timestamp
        )
    }

    private func draw(
        image: ASS_Image,
        in context: CGContext,
        canvasHeight: Int
    ) throws {
        let width = Int(image.w)
        let height = Int(image.h)
        let rect = CGRect(
            x: Int(image.dst_x),
            y: canvasHeight - Int(image.dst_y) - height,
            width: width,
            height: height
        )

        let maskData = copyMaskData(from: image)
        guard let provider = CGDataProvider(data: maskData as CFData),
              let mask = CGImage(
                maskWidth: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                provider: provider,
                decode: nil,
                shouldInterpolate: false
              ) else {
            throw LibassRendererError.failedToCreateMask
        }

        let rgba = rgbaComponents(for: image.color)
        context.saveGState()
        context.clip(to: rect, mask: mask)
        context.setFillColor(
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            alpha: rgba.alpha
        )
        context.fill(rect)
        context.restoreGState()
    }

    private func copyMaskData(from image: ASS_Image) -> Data {
        let width = Int(image.w)
        let height = Int(image.h)
        let stride = Int(image.stride)
        let source = UnsafeBufferPointer(
            start: image.bitmap,
            count: stride * max(height - 1, 0) + width
        )

        var bytes = Data(count: width * height)
        bytes.withUnsafeMutableBytes { rawBuffer in
            guard let destination = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for row in 0..<height {
                let sourceOffset = row * stride
                let destinationOffset = row * width
                guard let sourceBaseAddress = source.baseAddress else { continue }
                for column in 0..<width {
                    let sourceAlpha = sourceBaseAddress[sourceOffset + column]
                    destination[destinationOffset + column] = 255 &- sourceAlpha
                }
            }
        }
        return bytes
    }

    private func rgbaComponents(for color: UInt32) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let red = CGFloat((color >> 24) & 0xFF) / 255
        let green = CGFloat((color >> 16) & 0xFF) / 255
        let blue = CGFloat((color >> 8) & 0xFF) / 255
        let alpha = CGFloat(255 - (color & 0xFF)) / 255
        return (red, green, blue, alpha)
    }
}
