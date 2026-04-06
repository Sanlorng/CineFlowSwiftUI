import SwiftUI
import SubtitleRendererCore

#if os(macOS) && arch(arm64)
import AppKit
import QuartzCore

public struct SubtitleRendererOverlay: NSViewRepresentable {
    public let document: SubtitleDocument?
    public let playbackTime: TimeInterval

    public init(document: SubtitleDocument?, playbackTime: TimeInterval) {
        self.document = document
        self.playbackTime = playbackTime
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
            playbackTime: playbackTime
        )
    }

    public static func dismantleNSView(_ view: SubtitleOverlayView, coordinator: Coordinator) {
        coordinator.detach(from: view)
    }

    @MainActor
    public final class Coordinator {
        private var renderer: LibassRenderer?
        private var currentDocument: SubtitleDocument?
        private var currentViewport: SubtitleViewport?

        func attach(to view: SubtitleOverlayView) {
            view.wantsLayer = true
            view.layer?.contentsGravity = .resize
            view.layer?.isOpaque = false
            view.layer?.backgroundColor = NSColor.clear.cgColor
        }

        func detach(from view: SubtitleOverlayView) {
            view.layer?.contents = nil
            renderer = nil
            currentDocument = nil
            currentViewport = nil
        }

        func update(
            view: SubtitleOverlayView,
            document: SubtitleDocument?,
            playbackTime: TimeInterval
        ) {
            guard let document else {
                clear(view: view)
                return
            }

            let viewport = SubtitleViewport(
                size: view.bounds.size,
                scale: view.window?.backingScaleFactor ?? 1
            )

            guard viewport.size.width > 0, viewport.size.height > 0 else {
#if DEBUG
                print("[SubtitleRendererOverlay] Skip rendering because viewport is zero for \(document.fileName ?? "unknown")")
#endif
                clear(view: view)
                return
            }

            do {
                if renderer == nil {
                    renderer = try LibassRenderer(viewport: viewport)
                    currentViewport = viewport
                } else if currentViewport != viewport {
                    try renderer?.updateViewport(viewport)
                    currentViewport = viewport
                }

                if currentDocument != document {
                    try renderer?.updateDocument(document)
                    currentDocument = document
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
                clear(view: view)
            }
        }

        private func clear(view: SubtitleOverlayView) {
            view.layer?.contents = nil
            renderer = nil
            currentDocument = nil
            currentViewport = nil
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

    public init(document: SubtitleDocument?, playbackTime: TimeInterval) {
        self.document = document
        self.playbackTime = playbackTime
    }

    public var body: some View {
        Color.clear
    }
}
#endif
