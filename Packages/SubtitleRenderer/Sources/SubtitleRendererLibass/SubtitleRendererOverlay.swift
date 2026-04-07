import SwiftUI
import SubtitleRendererCore

#if os(macOS) && arch(arm64)
import AppKit
import QuartzCore

public struct SubtitleRendererOverlay: NSViewRepresentable {
    public let document: SubtitleDocument?
    public let playbackTime: TimeInterval
    public let defaultFontFamily: String?
    public let fontScale: Double
    public let onReadinessChanged: (@MainActor (Bool) -> Void)?

    public init(
        document: SubtitleDocument?,
        playbackTime: TimeInterval,
        defaultFontFamily: String? = nil,
        fontScale: Double = 1,
        onReadinessChanged: (@MainActor (Bool) -> Void)? = nil
    ) {
        self.document = document
        self.playbackTime = playbackTime
        self.defaultFontFamily = defaultFontFamily
        self.fontScale = fontScale
        self.onReadinessChanged = onReadinessChanged
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> SubtitleOverlayView {
        let view = SubtitleOverlayView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    public func updateNSView(_ view: SubtitleOverlayView, context: Context) {
        context.coordinator.update(
            view: view,
            document: document,
            playbackTime: playbackTime,
            defaultFontFamily: defaultFontFamily,
            fontScale: fontScale,
            onReadinessChanged: onReadinessChanged
        )
    }

    public static func dismantleNSView(_ view: SubtitleOverlayView, coordinator: Coordinator) {
        coordinator.detach(from: view)
    }

    @MainActor
    public final class Coordinator {
        private struct RenderStyle: Equatable {
            let defaultFontFamily: String?
            let fontScale: Double
        }

        private var renderer: LibassRenderer?
        private var currentDocument: SubtitleDocument?
        private var currentViewport: SubtitleViewport?
        private var currentRenderStyle: RenderStyle?
        private var isReady = false

        func attach(to view: SubtitleOverlayView) {
            view.wantsLayer = true
            view.layer?.contentsGravity = .resize
            view.layer?.isOpaque = false
            view.layer?.backgroundColor = NSColor.clear.cgColor
        }

        func detach(from view: SubtitleOverlayView) {
            view.layer?.contents = nil
            updateReadiness(false, onReadinessChanged: nil)
            renderer = nil
            currentDocument = nil
            currentViewport = nil
            currentRenderStyle = nil
        }

        func update(
            view: SubtitleOverlayView,
            document: SubtitleDocument?,
            playbackTime: TimeInterval,
            defaultFontFamily: String?,
            fontScale: Double,
            onReadinessChanged: (@MainActor (Bool) -> Void)?
        ) {
            guard let document else {
                clear(view: view, onReadinessChanged: onReadinessChanged)
                return
            }

            let renderStyle = RenderStyle(
                defaultFontFamily: defaultFontFamily?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                fontScale: max(fontScale, 0.25)
            )

            let viewport = SubtitleViewport(
                size: view.bounds.size,
                scale: view.window?.backingScaleFactor ?? 1
            )

            guard viewport.size.width > 0, viewport.size.height > 0 else {
#if DEBUG
                print("[SubtitleRendererOverlay] Skip rendering because viewport is zero for \(document.fileName ?? "unknown")")
#endif
                clear(view: view, onReadinessChanged: onReadinessChanged)
                return
            }

            do {
                if renderer == nil || currentRenderStyle != renderStyle {
                    renderer = try LibassRenderer(
                        viewport: viewport,
                        defaultFontFamily: renderStyle.defaultFontFamily,
                        fontScale: renderStyle.fontScale
                    )
                    currentViewport = viewport
                    currentRenderStyle = renderStyle
                    currentDocument = nil
                } else if currentViewport != viewport {
                    try renderer?.updateViewport(viewport)
                    currentViewport = viewport
                }

                if currentDocument != document {
                    try renderer?.updateDocument(document)
                    currentDocument = document
                    updateReadiness(true, onReadinessChanged: onReadinessChanged)
#if DEBUG
                    print("[SubtitleRendererOverlay] Loaded subtitle document \(document.fileName ?? "unknown") format=\(document.format.rawValue)")
#endif
                }

                let frame = try renderer?.renderFrame(at: playbackTime)
                view.layer?.contents = frame?.image
                view.layer?.contentsScale = viewport.scale
#if DEBUG
                if frame == nil {
                    print("[SubtitleRendererOverlay] No frame at time \(playbackTime) for \(document.fileName ?? "unknown")")
                }
#endif
            } catch {
#if DEBUG
                print("[SubtitleRendererOverlay] Failed to render subtitle frame:", error)
#endif
                clear(view: view, onReadinessChanged: onReadinessChanged)
            }
        }

        private func clear(
            view: SubtitleOverlayView,
            onReadinessChanged: (@MainActor (Bool) -> Void)?
        ) {
            view.layer?.contents = nil
            updateReadiness(false, onReadinessChanged: onReadinessChanged)
            renderer = nil
            currentDocument = nil
            currentViewport = nil
            currentRenderStyle = nil
        }

        private func updateReadiness(
            _ ready: Bool,
            onReadinessChanged: (@MainActor (Bool) -> Void)?
        ) {
            guard isReady != ready else { return }
            isReady = ready
            onReadinessChanged?(ready)
        }
    }
}

public final class SubtitleOverlayView: NSView {
    public override var isFlipped: Bool { true }
}
#else
public struct SubtitleRendererOverlay: View {
    public let document: SubtitleDocument?
    public let playbackTime: TimeInterval
    public let defaultFontFamily: String?
    public let fontScale: Double
    public let onReadinessChanged: (@MainActor (Bool) -> Void)?

    public init(
        document: SubtitleDocument?,
        playbackTime: TimeInterval,
        defaultFontFamily: String? = nil,
        fontScale: Double = 1,
        onReadinessChanged: (@MainActor (Bool) -> Void)? = nil
    ) {
        self.document = document
        self.playbackTime = playbackTime
        self.defaultFontFamily = defaultFontFamily
        self.fontScale = fontScale
        self.onReadinessChanged = onReadinessChanged
    }

    public var body: some View {
        Color.clear
    }
}
#endif

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
