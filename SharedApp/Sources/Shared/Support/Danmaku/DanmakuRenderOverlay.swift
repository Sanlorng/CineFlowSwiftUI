import SwiftUI

#if canImport(DanmakuRender) && os(macOS)
import AppKit
import DanmakuRender

struct DanmakuRenderOverlay: NSViewRepresentable {
    let payload: DanmakuPayload?
    let playbackTime: TimeInterval

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DanmakuCanvasHostView {
        let view = DanmakuCanvasHostView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: DanmakuCanvasHostView, context: Context) {
        context.coordinator.update(view: view, payload: payload, playbackTime: playbackTime)
    }

    static func dismantleNSView(_ view: DanmakuCanvasHostView, coordinator: Coordinator) {
        coordinator.detach(from: view)
    }

    @MainActor
    final class Coordinator {
        private let engine = DanmakuEngine()
        private var currentPayload: DanmakuPayload?
        private var nextCommentIndex = 0
        private var lastPlaybackTime: TimeInterval = 0

        func attach(to view: DanmakuCanvasHostView) {
            engine.speed = 0
            engine.start()
            view.attach(canvas: engine.canvas)
        }

        func detach(from view: DanmakuCanvasHostView) {
            engine.stop()
            currentPayload = nil
            nextCommentIndex = 0
            lastPlaybackTime = 0
        }

        func update(
            view: DanmakuCanvasHostView,
            payload: DanmakuPayload?,
            playbackTime: TimeInterval
        ) {
            let clampedTime = max(playbackTime, 0)
            view.layoutSubtreeIfNeeded()

            if currentPayload != payload {
                replacePayload(payload, at: clampedTime)
                return
            }

            guard let payload else {
                engine.stop()
                lastPlaybackTime = clampedTime
                return
            }

            if clampedTime + 0.1 < lastPlaybackTime || clampedTime - lastPlaybackTime > 5 {
                replacePayload(payload, at: clampedTime)
                return
            }

            engine.time = clampedTime
            enqueueComments(
                payload.comments,
                from: lastPlaybackTime,
                through: clampedTime
            )
            lastPlaybackTime = clampedTime
        }

        private func replacePayload(_ payload: DanmakuPayload?, at playbackTime: TimeInterval) {
            engine.stop()
            currentPayload = payload
            nextCommentIndex = 0
            lastPlaybackTime = playbackTime

            guard let payload else { return }

            engine.time = playbackTime
            let lowerBound = max(playbackTime - 12, 0)
            while nextCommentIndex < payload.comments.count,
                  payload.comments[nextCommentIndex].appearTime < lowerBound {
                nextCommentIndex += 1
            }
            enqueueComments(
                payload.comments,
                from: lowerBound,
                through: playbackTime
            )
        }

        private func enqueueComments(
            _ comments: [DanmakuPayload.Comment],
            from lowerBound: TimeInterval,
            through upperBound: TimeInterval
        ) {
            while nextCommentIndex < comments.count {
                let comment = comments[nextCommentIndex]
                if comment.appearTime > upperBound {
                    break
                }
                if comment.appearTime >= lowerBound,
                   let danmaku = makeDanmaku(from: comment) {
                    engine.send(danmaku)
                }
                nextCommentIndex += 1
            }
        }

        private func makeDanmaku(from comment: DanmakuPayload.Comment) -> BaseDanmaku? {
            let color = nsColor(from: comment.colorRGB)
            let fontSize = max(14, min(comment.fontSize * 0.72, 26))
            let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)

            let danmaku: BaseDanmaku
            switch comment.mode {
            case .scroll, .scrollAlt, .scrollBottom:
                danmaku = ScrollDanmaku(
                    text: comment.text,
                    textColor: color,
                    font: font,
                    effectStyle: .stroke,
                    direction: .toLeft
                )
            case .reverseScroll:
                danmaku = ScrollDanmaku(
                    text: comment.text,
                    textColor: color,
                    font: font,
                    effectStyle: .stroke,
                    direction: .toRight
                )
            case .top:
                danmaku = FloatDanmaku(
                    text: comment.text,
                    textColor: color,
                    font: font,
                    effectStyle: .stroke,
                    position: .atTop,
                    lifeTime: comment.visibilityWindow
                )
            case .bottom:
                danmaku = FloatDanmaku(
                    text: comment.text,
                    textColor: color,
                    font: font,
                    effectStyle: .stroke,
                    position: .atBottom,
                    lifeTime: comment.visibilityWindow
                )
            }

            danmaku.appearTime = comment.appearTime
            return danmaku
        }

        private func nsColor(from rgb: UInt32) -> NSColor {
            let red = CGFloat((rgb >> 16) & 0xFF) / 255
            let green = CGFloat((rgb >> 8) & 0xFF) / 255
            let blue = CGFloat(rgb & 0xFF) / 255
            return NSColor(red: red, green: green, blue: blue, alpha: 1)
        }
    }
}

final class DanmakuCanvasHostView: NSView {
    private weak var danmakuCanvas: NSView?

    override var isFlipped: Bool { true }

    func attach(canvas: NSView) {
        guard danmakuCanvas !== canvas else { return }
        danmakuCanvas?.removeFromSuperview()
        danmakuCanvas = canvas
        addSubview(canvas)
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        danmakuCanvas?.frame = bounds
    }
}
#else
struct DanmakuRenderOverlay: View {
    let payload: DanmakuPayload?
    let playbackTime: TimeInterval

    var body: some View {
        Color.clear
    }
}
#endif
