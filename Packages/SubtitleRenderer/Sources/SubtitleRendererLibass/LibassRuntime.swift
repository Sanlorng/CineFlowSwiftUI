import CLibass
import Darwin
import Foundation

enum LibassRuntimeError: Error, Equatable {
    case unsupportedPlatform
    case resourceBundleNotFound(String)
    case runtimeNotFound(String)
    case failedToLoadRuntime(String)
    case missingSymbol(String)
}

final class LibassRuntime {
    typealias AssLibraryInit = @convention(c) () -> OpaquePointer?
    typealias AssLibraryDone = @convention(c) (OpaquePointer?) -> Void
    typealias AssSetExtractFonts = @convention(c) (OpaquePointer?, Int32) -> Void
    typealias AssSetFontsDir = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Void
    typealias AssRendererInit = @convention(c) (OpaquePointer?) -> OpaquePointer?
    typealias AssRendererDone = @convention(c) (OpaquePointer?) -> Void
    typealias AssSetFrameSize = @convention(c) (OpaquePointer?, Int32, Int32) -> Void
    typealias AssSetStorageSize = @convention(c) (OpaquePointer?, Int32, Int32) -> Void
    typealias AssSetUseMargins = @convention(c) (OpaquePointer?, Int32) -> Void
    typealias AssSetLinePosition = @convention(c) (OpaquePointer?, Double) -> Void
    typealias AssSetHinting = @convention(c) (OpaquePointer?, ASS_Hinting) -> Void
    typealias AssSetFonts = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        Int32,
        UnsafePointer<CChar>?,
        Int32
    ) -> Void
    typealias AssReadMemory = @convention(c) (
        OpaquePointer?,
        UnsafeMutablePointer<CChar>?,
        Int,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<ASS_Track>?
    typealias AssFreeTrack = @convention(c) (UnsafeMutablePointer<ASS_Track>?) -> Void
    typealias AssRenderFrame = @convention(c) (
        OpaquePointer?,
        UnsafeMutablePointer<ASS_Track>?,
        Int64,
        UnsafeMutablePointer<Int32>?
    ) -> UnsafeMutablePointer<ASS_Image>?

    let assLibraryInit: AssLibraryInit
    let assLibraryDone: AssLibraryDone
    let assSetExtractFonts: AssSetExtractFonts
    let assSetFontsDir: AssSetFontsDir
    let assRendererInit: AssRendererInit
    let assRendererDone: AssRendererDone
    let assSetFrameSize: AssSetFrameSize
    let assSetStorageSize: AssSetStorageSize
    let assSetUseMargins: AssSetUseMargins
    let assSetLinePosition: AssSetLinePosition
    let assSetHinting: AssSetHinting
    let assSetFonts: AssSetFonts
    let assReadMemory: AssReadMemory
    let assFreeTrack: AssFreeTrack
    let assRenderFrame: AssRenderFrame

    private let handle: UnsafeMutableRawPointer

    init() throws {
#if os(macOS) && arch(arm64)
        let bundleName = "SubtitleRenderer_SubtitleRendererLibass.bundle"
        let bundleCandidates: [URL?] = [
            Bundle.module.bundleURL,
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources").appendingPathComponent(bundleName),
        ]

        let bundleURL = bundleCandidates
            .compactMap { $0 }
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })

        guard let bundleURL,
              let bundle = Bundle(url: bundleURL),
              let resourceURL = bundle.resourceURL else {
            throw LibassRuntimeError.resourceBundleNotFound(bundleName)
        }

        let runtimeURL = resourceURL.appendingPathComponent("Runtime/macos-arm64/libass.9.dylib")
        guard FileManager.default.fileExists(atPath: runtimeURL.path) else {
            throw LibassRuntimeError.runtimeNotFound("Runtime/macos-arm64/libass.9.dylib")
        }

        guard let handle = dlopen(runtimeURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let message = dlerror().map { String(cString: $0) } ?? "unknown error"
            throw LibassRuntimeError.failedToLoadRuntime(message)
        }
        self.handle = handle

        func loadSymbol<T>(_ symbol: String, as type: T.Type) throws -> T {
            guard let rawSymbol = dlsym(handle, symbol) else {
                throw LibassRuntimeError.missingSymbol(symbol)
            }
            return unsafeBitCast(rawSymbol, to: T.self)
        }

        assLibraryInit = try loadSymbol("ass_library_init", as: AssLibraryInit.self)
        assLibraryDone = try loadSymbol("ass_library_done", as: AssLibraryDone.self)
        assSetExtractFonts = try loadSymbol("ass_set_extract_fonts", as: AssSetExtractFonts.self)
        assSetFontsDir = try loadSymbol("ass_set_fonts_dir", as: AssSetFontsDir.self)
        assRendererInit = try loadSymbol("ass_renderer_init", as: AssRendererInit.self)
        assRendererDone = try loadSymbol("ass_renderer_done", as: AssRendererDone.self)
        assSetFrameSize = try loadSymbol("ass_set_frame_size", as: AssSetFrameSize.self)
        assSetStorageSize = try loadSymbol("ass_set_storage_size", as: AssSetStorageSize.self)
        assSetUseMargins = try loadSymbol("ass_set_use_margins", as: AssSetUseMargins.self)
        assSetLinePosition = try loadSymbol("ass_set_line_position", as: AssSetLinePosition.self)
        assSetHinting = try loadSymbol("ass_set_hinting", as: AssSetHinting.self)
        assSetFonts = try loadSymbol("ass_set_fonts", as: AssSetFonts.self)
        assReadMemory = try loadSymbol("ass_read_memory", as: AssReadMemory.self)
        assFreeTrack = try loadSymbol("ass_free_track", as: AssFreeTrack.self)
        assRenderFrame = try loadSymbol("ass_render_frame", as: AssRenderFrame.self)
#else
        throw LibassRuntimeError.unsupportedPlatform
#endif
    }

    deinit {
        dlclose(handle)
    }
}
