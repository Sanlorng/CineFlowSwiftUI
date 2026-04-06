import SwiftUI
import Combine

#if canImport(DanmakuRender) && os(macOS)
import AppKit
import DanmakuRender

struct DanmakuRenderOverlay: NSViewRepresentable {
    let loadedDanmaku: PlayerPresenter.State.LoadedDanmaku?
    let controller: PlayerController

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DanmakuCanvasHostView {
        let view = DanmakuCanvasHostView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: DanmakuCanvasHostView, context: Context) {
        context.coordinator.update(
            view: view,
            loadedDanmaku: loadedDanmaku,
            controller: controller
        )
    }

    static func dismantleNSView(_ view: DanmakuCanvasHostView, coordinator: Coordinator) {
        coordinator.detach(from: view)
    }

    @MainActor
    final class Coordinator {
        private let engine = DanmakuEngine()
        private weak var controller: PlayerController?
        private var currentDanmakuID: UUID?
        private var currentPayload: DanmakuPayload?
        private var lastPlaybackTime: TimeInterval = 0
        private var lastEnqueuedSecond: UInt?
        private var isEngineStarted = false
        private var timelineCancellable: AnyCancellable?
        private var stateCancellable: AnyCancellable?

        func attach(to view: DanmakuCanvasHostView) {
            engine.speed = 1
            engine.layoutStyle = .nonOverlapping
            engine.start()
            isEngineStarted = true
            view.attach(canvas: engine.canvas)
        }

        func detach(from view: DanmakuCanvasHostView) {
            engine.stop()
            isEngineStarted = false
            timelineCancellable = nil
            stateCancellable = nil
            controller = nil
            currentDanmakuID = nil
            currentPayload = nil
            lastPlaybackTime = 0
            lastEnqueuedSecond = nil
        }

        func update(
            view: DanmakuCanvasHostView,
            loadedDanmaku: PlayerPresenter.State.LoadedDanmaku?,
            controller: PlayerController
        ) {
            bind(to: controller)
            let clampedTime = max(controller.timeline.currentTime, 0)
            let payload = loadedDanmaku?.payload

            if currentDanmakuID != loadedDanmaku?.id {
                currentDanmakuID = loadedDanmaku?.id
                replacePayload(payload, at: clampedTime)
                return
            }
        }

        private func replacePayload(_ payload: DanmakuPayload?, at playbackTime: TimeInterval) {
            engine.stop()
            isEngineStarted = false
            currentPayload = payload
            lastPlaybackTime = playbackTime
            lastEnqueuedSecond = nil

            guard let payload else { return }

            engine.start()
            isEngineStarted = true
            engine.speed = 1
            engine.layoutStyle = .nonOverlapping
            engine.time = playbackTime
            let currentSecond = max(Int(playbackTime.rounded(.towardZero)), 0)
            enqueueSecondBuckets(
                payload.commentsBySecond,
                from: currentSecond,
                through: currentSecond
            )
        }

        private func bind(to controller: PlayerController) {
            guard self.controller !== controller else { return }
            self.controller = controller
            timelineCancellable = controller.$timeline.sink { [weak self] timeline in
                Task { @MainActor in
                    self?.handlePlaybackTimeChange(timeline.currentTime)
                }
            }
            stateCancellable = controller.$playbackState.sink { [weak self] state in
                Task { @MainActor in
                    self?.updateEnginePlaybackState(state)
                }
            }
        }

        private func handlePlaybackTimeChange(_ playbackTime: TimeInterval) {
            let clampedTime = max(playbackTime, 0)
            guard let payload = currentPayload else {
                lastPlaybackTime = clampedTime
                return
            }

            if clampedTime + 0.1 < lastPlaybackTime || clampedTime - lastPlaybackTime > 5 {
                replacePayload(payload, at: clampedTime)
                return
            }

            let upperSecond = Int((clampedTime + 0.35).rounded(.towardZero))
            let lowerSecond = Int(lastPlaybackTime.rounded(.towardZero))
            enqueueSecondBuckets(
                payload.commentsBySecond,
                from: lowerSecond,
                through: upperSecond
            )
            lastPlaybackTime = clampedTime
        }

        private func updateEnginePlaybackState(_ playbackState: PlayerPlaybackState) {
            switch playbackState {
            case .playing, .buffering:
                if !isEngineStarted {
                    engine.start()
                    isEngineStarted = true
                }
            case .paused, .stopped, .completed, .idle, .error:
                if isEngineStarted {
                    engine.pause()
                    isEngineStarted = false
                }
            case .preparing:
                break
            }
        }

        private func enqueueSecondBuckets(
            _ commentsBySecond: [UInt: [DanmakuPayload.Comment]],
            from lowerSecond: Int,
            through upperSecond: Int
        ) {
            guard upperSecond >= lowerSecond else { return }
            let startSecond = max(lastEnqueuedSecond.map { Int($0) + 1 } ?? lowerSecond, lowerSecond)
            guard upperSecond >= startSecond else { return }

            for second in startSecond...upperSecond {
                guard let comments = commentsBySecond[UInt(second)] else { continue }
                for comment in comments {
                    if let danmaku = makeDanmaku(from: comment) {
                        engine.send(danmaku)
                    }
                }
                lastEnqueuedSecond = UInt(second)
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
    let loadedDanmaku: PlayerPresenter.State.LoadedDanmaku?
    let controller: PlayerController

    var body: some View {
        Color.clear
    }
}
#endif
