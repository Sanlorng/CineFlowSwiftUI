import SwiftUI
import DanmakuRendererCore

#if os(macOS)
import AppKit
import CoreText
import CoreVideo

public struct DanmakuRendererOverlay: NSViewRepresentable {
    public let document: DanmakuDocument?
    public let documentID: UUID?
    public let playbackTime: TimeInterval
    public let isPlaybackActive: Bool
    public let playbackRate: Double
    public let settings: DanmakuRenderSettings

    public init(
        document: DanmakuDocument?,
        documentID: UUID? = nil,
        playbackTime: TimeInterval,
        isPlaybackActive: Bool,
        playbackRate: Double = 1,
        settings: DanmakuRenderSettings
    ) {
        self.document = document
        self.documentID = documentID
        self.playbackTime = playbackTime
        self.isPlaybackActive = isPlaybackActive
        self.playbackRate = playbackRate
        self.settings = settings
    }

    public func makeNSView(context: Context) -> DanmakuOverlayView {
        DanmakuOverlayView(frame: .zero)
    }

    public func updateNSView(_ view: DanmakuOverlayView, context: Context) {
        view.apply(
            snapshot: .init(
                document: document,
                documentID: documentID,
                playbackTime: playbackTime,
                isPlaybackActive: isPlaybackActive,
                playbackRate: playbackRate,
                settings: settings
            )
        )
    }
}

public final class DanmakuOverlayView: NSView {
    fileprivate struct Snapshot {
        var document: DanmakuDocument?
        var documentID: UUID?
        var playbackTime: TimeInterval
        var isPlaybackActive: Bool
        var playbackRate: Double
        var settings: DanmakuRenderSettings

        static let empty = Snapshot(
            document: nil,
            documentID: nil,
            playbackTime: 0,
            isPlaybackActive: false,
            playbackRate: 1,
            settings: .init()
        )
    }

    private let renderer = DanmakuCanvasRenderer()
    private var snapshot = Snapshot.empty
    private var displayLink: CVDisplayLink?

    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { false }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        renderer.onInvalidation = { [weak self] in
            self?.needsDisplay = true
            self?.updateDisplayLinkState()
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func apply(snapshot: Snapshot) {
        self.snapshot = snapshot
        updateRenderer()
    }

    public override func layout() {
        super.layout()
        updateRenderer()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRenderer()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateRenderer()
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        renderer.draw(in: context, bounds: bounds)
    }

    private func updateRenderer() {
        renderer.update(
            document: snapshot.document,
            documentID: snapshot.documentID,
            playbackTime: snapshot.playbackTime,
            isPlaybackActive: snapshot.isPlaybackActive,
            playbackRate: snapshot.playbackRate,
            settings: snapshot.settings,
            viewport: currentViewport
        )
        updateDisplayLinkState()
        needsDisplay = true
    }

    private var currentViewport: DanmakuCanvasViewport {
        DanmakuCanvasViewport(
            size: bounds.size,
            scale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        )
    }

    private func updateDisplayLinkState() {
        guard window != nil else {
            stopDisplayLink()
            return
        }

        if renderer.shouldAnimate {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    private func startDisplayLink() {
        if displayLink == nil {
            createDisplayLink()
        }
        guard let displayLink, CVDisplayLinkIsRunning(displayLink) == false else { return }
        CVDisplayLinkStart(displayLink)
    }

    private func stopDisplayLink() {
        guard let displayLink, CVDisplayLinkIsRunning(displayLink) else { return }
        CVDisplayLinkStop(displayLink)
    }

    private func createDisplayLink() {
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess,
              let link else {
            return
        }

        let callbackStatus = CVDisplayLinkSetOutputCallback(
            link,
            { _, _, _, _, _, context in
                guard let context else { return kCVReturnSuccess }
                let view = Unmanaged<DanmakuOverlayView>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async {
                    view.needsDisplay = true
                }
                return kCVReturnSuccess
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard callbackStatus == kCVReturnSuccess else { return }
        displayLink = link
    }
}

private struct DanmakuCanvasViewport: Equatable, Sendable {
    var size: CGSize
    var scale: CGFloat

    var isRenderable: Bool {
        size.width > 1 && size.height > 1
    }
}

private struct DanmakuSceneDescriptor: Equatable, Sendable {
    var documentID: UUID?
    var viewportSize: CGSize
    var scale: CGFloat
    var fontScale: Double
    var speed: Double
    var maximumTrackRatio: Double
    var trackSpacing: Double
}

private final class DanmakuCanvasRenderer: @unchecked Sendable {
    var onInvalidation: (() -> Void)?

    private let textCache = DanmakuTextRasterCache()
    private let scheduler = DanmakuPlaybackScheduler()
    private let clock = DanmakuPlaybackClock()
    private let preparationQueue = DispatchQueue(label: "CineFlow.DanmakuSceneBuilder", qos: .userInitiated)

    private var preparedScene: DanmakuPreparedScene?
    private var sceneDescriptor: DanmakuSceneDescriptor?
    private var preparationGeneration = 0
    private var currentSettings = DanmakuRenderSettings()

    var shouldAnimate: Bool {
        currentSettings.isVisible && preparedScene != nil && clock.isActive
    }

    func update(
        document: DanmakuDocument?,
        documentID: UUID?,
        playbackTime: TimeInterval,
        isPlaybackActive: Bool,
        playbackRate: Double,
        settings: DanmakuRenderSettings,
        viewport: DanmakuCanvasViewport
    ) {
        currentSettings = settings
        clock.sync(
            time: max(playbackTime, 0),
            isActive: settings.isVisible && isPlaybackActive,
            rate: max(playbackRate, 0.25)
        )

        guard let document, viewport.isRenderable else {
            preparedScene = nil
            sceneDescriptor = nil
            scheduler.reset(scene: nil, time: clock.currentTime)
            return
        }

        let descriptor = DanmakuSceneDescriptor(
            documentID: documentID,
            viewportSize: viewport.size,
            scale: viewport.scale,
            fontScale: settings.fontScale,
            speed: settings.speed,
            maximumTrackRatio: settings.maximumTrackRatio,
            trackSpacing: settings.trackSpacing
        )

        guard descriptor != sceneDescriptor else { return }
        sceneDescriptor = descriptor
        preparedScene = nil
        preparationGeneration += 1
        let generation = preparationGeneration
        let textCache = self.textCache

        preparationQueue.async {
            let scene = DanmakuSceneBuilder.build(
                document: document,
                descriptor: descriptor,
                textCache: textCache
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.preparationGeneration == generation, self.sceneDescriptor == descriptor else { return }
                self.preparedScene = scene
                self.scheduler.reset(scene: scene, time: self.clock.currentTime)
                self.onInvalidation?()
            }
        }
    }

    func draw(in context: CGContext, bounds: CGRect) {
        guard currentSettings.isVisible,
              let preparedScene,
              bounds.isEmpty == false else {
            return
        }

        let currentTime = clock.currentTime
        let visibleEntries = scheduler.visibleEntries(at: currentTime).sorted { lhs, rhs in
            if lhs.zIndex != rhs.zIndex {
                return lhs.zIndex < rhs.zIndex
            }
            if lhs.appearTime != rhs.appearTime {
                return lhs.appearTime < rhs.appearTime
            }
            return lhs.text < rhs.text
        }

        context.interpolationQuality = .high

        for entry in visibleEntries {
            guard let renderState = entry.renderState(at: currentTime) else {
                continue
            }

            if renderState.frame.intersects(bounds) == false {
                continue
            }

            guard let image = textCache.image(for: entry, scale: boundsScale(preparedScene: preparedScene)) else {
                continue
            }

            context.saveGState()
            context.setAlpha(CGFloat(clampedOpacity(renderState.opacity) * currentSettings.opacity))
            if abs(renderState.rotation) > 0.0001 {
                context.translateBy(x: renderState.frame.midX, y: renderState.frame.midY)
                context.rotate(by: renderState.rotation)
                let drawRect = CGRect(
                    x: -entry.size.width / 2,
                    y: -entry.size.height / 2,
                    width: entry.size.width,
                    height: entry.size.height
                )
                context.draw(image, in: drawRect)
            } else {
                context.draw(image, in: renderState.frame)
            }
            context.restoreGState()
        }
    }

    func invalidate() {
        preparationGeneration += 1
        sceneDescriptor = nil
        preparedScene = nil
        scheduler.reset(scene: nil, time: 0)
    }

    private func boundsScale(preparedScene: DanmakuPreparedScene) -> CGFloat {
        max(preparedScene.scale, 1)
    }

    private func clampedOpacity(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private final class DanmakuPlaybackClock {
    private var anchorTime: TimeInterval = 0
    private var anchorHostTime: CFTimeInterval = CACurrentMediaTime()
    private(set) var rate: Double = 1
    private(set) var isActive = false

    var currentTime: TimeInterval {
        guard isActive else { return anchorTime }
        let elapsed = CACurrentMediaTime() - anchorHostTime
        return max(anchorTime + elapsed * rate, 0)
    }

    func sync(time: TimeInterval, isActive: Bool, rate: Double) {
        let normalizedTime = max(time, 0)
        let normalizedRate = max(rate, 0.25)

        if self.isActive == isActive,
           abs(self.rate - normalizedRate) < 0.0001,
           abs(anchorTime - normalizedTime) < 0.12 {
            return
        }

        anchorTime = normalizedTime
        anchorHostTime = CACurrentMediaTime()
        self.isActive = isActive
        self.rate = normalizedRate
    }
}

private final class DanmakuPlaybackScheduler {
    private var scene: DanmakuPreparedScene?
    private var activeIndices: [Int] = []
    private var nextIndex = 0
    private var lastTime: TimeInterval = 0

    func reset(scene: DanmakuPreparedScene?, time: TimeInterval) {
        self.scene = scene
        guard let scene else {
            activeIndices = []
            nextIndex = 0
            lastTime = 0
            return
        }
        rebuild(for: scene, time: time)
    }

    func visibleEntries(at time: TimeInterval) -> [DanmakuPreparedComment] {
        guard let scene else { return [] }

        if time + 0.1 < lastTime || time - lastTime > 5 {
            rebuild(for: scene, time: time)
        }

        while nextIndex < scene.entries.count, scene.entries[nextIndex].appearTime <= time {
            activeIndices.append(nextIndex)
            nextIndex += 1
        }

        activeIndices.removeAll { index in
            scene.entries[index].endTime <= time
        }

        lastTime = time
        return activeIndices.compactMap { index in
            let entry = scene.entries[index]
            return entry.endTime > time ? entry : nil
        }
    }

    private func rebuild(for scene: DanmakuPreparedScene, time: TimeInterval) {
        let lowerTime = max(time - scene.maximumLifetime - 0.25, 0)
        let lowerBound = scene.lowerBound(for: lowerTime)
        let upperBound = scene.upperBound(for: time)
        activeIndices = (lowerBound..<upperBound).filter { scene.entries[$0].endTime > time }
        nextIndex = upperBound
        lastTime = time
    }
}

private struct DanmakuPreparedScene: Sendable {
    var descriptor: DanmakuSceneDescriptor
    var scale: CGFloat
    var entries: [DanmakuPreparedComment]
    var maximumLifetime: TimeInterval
    private let timelineIndex: DanmakuTimelineIndex

    init(
        descriptor: DanmakuSceneDescriptor,
        scale: CGFloat,
        entries: [DanmakuPreparedComment],
        maximumLifetime: TimeInterval
    ) {
        self.descriptor = descriptor
        self.scale = scale
        self.entries = entries
        self.maximumLifetime = maximumLifetime
        self.timelineIndex = DanmakuTimelineIndex(
            times: entries.map(\.appearTime),
            bucketDuration: 0.5
        )
    }

    func lowerBound(for time: TimeInterval) -> Int {
        binarySearch(
            time: time,
            range: timelineIndex.searchRange(for: time, totalCount: entries.count),
            isUpperBound: false
        )
    }

    func upperBound(for time: TimeInterval) -> Int {
        binarySearch(
            time: time,
            range: timelineIndex.searchRange(for: time, totalCount: entries.count),
            isUpperBound: true
        )
    }

    private func binarySearch(time: TimeInterval, range: Range<Int>, isUpperBound: Bool) -> Int {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper {
            let middle = (lower + upper) / 2
            if entries[middle].appearTime < time || (isUpperBound && entries[middle].appearTime == time) {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}

private struct DanmakuRenderState: Sendable {
    var frame: CGRect
    var opacity: Double
    var rotation: CGFloat
}

private struct DanmakuMotionTrajectory: Sendable {
    var points: [CGPoint]
    var delay: TimeInterval
    var duration: TimeInterval
    var curve: DanmakuMotionCurve

    func point(at elapsed: TimeInterval) -> CGPoint {
        guard points.isEmpty == false else { return .zero }
        guard points.count > 1 else { return points[0] }

        let effectiveDuration = max(duration, 0.0001)
        let motionProgress: CGFloat
        if elapsed <= delay {
            motionProgress = 0
        } else {
            motionProgress = min(max(CGFloat((elapsed - delay) / effectiveDuration), 0), 1)
        }

        let curvedProgress = curve.value(at: motionProgress)
        let segmentLengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let totalLength = max(segmentLengths.reduce(0, +), 0.0001)
        let targetLength = totalLength * curvedProgress

        var consumed: CGFloat = 0
        for (index, segmentLength) in segmentLengths.enumerated() {
            let nextConsumed = consumed + segmentLength
            if targetLength <= nextConsumed || index == segmentLengths.count - 1 {
                let localProgress = segmentLength > 0 ? (targetLength - consumed) / segmentLength : 0
                let start = points[index]
                let end = points[index + 1]
                return CGPoint(
                    x: start.x + (end.x - start.x) * localProgress,
                    y: start.y + (end.y - start.y) * localProgress
                )
            }
            consumed = nextConsumed
        }

        return points.last ?? .zero
    }
}

private struct DanmakuPreparedComment: Sendable {
    var appearTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var colorRGB: UInt32
    var fontSize: CGFloat
    var fontFamily: String?
    var usesStroke: Bool
    var size: CGSize
    var placement: DanmakuPlacement
    var alpha: ClosedRange<Double>
    var rotation: ClosedRange<Double>
    var zIndex: Int

    func renderState(at time: TimeInterval) -> DanmakuRenderState? {
        guard time >= appearTime, time <= endTime else { return nil }
        let elapsed = time - appearTime

        let origin: CGPoint
        switch placement {
        case let .scrollLeft(y, startX, travelDistance):
            let progress = CGFloat(elapsed / max(endTime - appearTime, 0.0001))
            origin = CGPoint(x: startX - progress * travelDistance, y: y)
        case let .scrollRight(y, startX, travelDistance):
            let progress = CGFloat(elapsed / max(endTime - appearTime, 0.0001))
            origin = CGPoint(x: startX + progress * travelDistance, y: y)
        case let .fixed(originPoint):
            origin = originPoint
        case let .motion(trajectory):
            origin = trajectory.point(at: elapsed)
        }

        let frame = CGRect(origin: origin, size: size)
        return DanmakuRenderState(
            frame: frame,
            opacity: opacity(at: time),
            rotation: CGFloat(rotation(at: time) * .pi / 180)
        )
    }

    func opacity(at time: TimeInterval) -> Double {
        guard alpha.lowerBound != alpha.upperBound else { return alpha.lowerBound }
        let progress = (time - appearTime) / max(endTime - appearTime, 0.0001)
        return alpha.lowerBound + (alpha.upperBound - alpha.lowerBound) * progress
    }

    func rotation(at time: TimeInterval) -> Double {
        guard rotation.lowerBound != rotation.upperBound else { return rotation.lowerBound }
        let progress = (time - appearTime) / max(endTime - appearTime, 0.0001)
        return rotation.lowerBound + (rotation.upperBound - rotation.lowerBound) * progress
    }
}

private enum DanmakuPlacement: Sendable {
    case scrollLeft(y: CGFloat, startX: CGFloat, travelDistance: CGFloat)
    case scrollRight(y: CGFloat, startX: CGFloat, travelDistance: CGFloat)
    case fixed(origin: CGPoint)
    case motion(DanmakuMotionTrajectory)
}

private struct DanmakuSceneBuilder {
    static func build(
        document: DanmakuDocument,
        descriptor: DanmakuSceneDescriptor,
        textCache: DanmakuTextRasterCache
    ) -> DanmakuPreparedScene {
        let fontScale = max(descriptor.fontScale, 0.6)
        let speed = max(descriptor.speed, 0.25)
        let trackSpacing = CGFloat(max(descriptor.trackSpacing, 2))
        let laneStride = max(CGFloat(22 * fontScale), 20) + trackSpacing
        let scrollHeight = max(descriptor.viewportSize.height * min(max(descriptor.maximumTrackRatio, 0.25), 0.92), laneStride)
        let scrollLaneCount = max(Int((scrollHeight - 12) / laneStride), 1)
        let fixedLaneCount = max(Int((max(descriptor.viewportSize.height * 0.18, laneStride * 2) - 12) / laneStride), 1)

        var leftLaneStates = Array(repeating: ScrollLaneState(), count: scrollLaneCount)
        var rightLaneStates = Array(repeating: ScrollLaneState(), count: scrollLaneCount)
        var topLaneStates = Array(repeating: FixedLaneState(), count: fixedLaneCount)
        var bottomLaneStates = Array(repeating: FixedLaneState(), count: fixedLaneCount)

        var entries: [DanmakuPreparedComment] = []
        entries.reserveCapacity(document.renderableComments.count)

        for comment in document.renderableComments {
            let displayText = sanitize(comment.text)
            guard displayText.isEmpty == false else { continue }

            let fontSize = CGFloat(clamp(comment.fontSize * 0.72 * fontScale, minimum: 14, maximum: 42))
            let fontFamily = comment.advancedPayload?.fontFamily?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let usesStroke = comment.advancedPayload?.usesStroke ?? true
            let metrics = textCache.metrics(
                for: displayText,
                fontSize: fontSize,
                fontFamily: fontFamily,
                usesStroke: usesStroke
            )
            let duration = max(comment.visibilityWindow / speed, 0.2)
            let laneSpan = max(1, Int(ceil((metrics.size.height + trackSpacing) / max(laneStride, 1))))
            let alpha = alphaRange(for: comment)
            let rotation = rotationRange(for: comment)

            if comment.mode == .advanced {
                if let placement = advancedPlacement(
                    for: comment,
                    payload: comment.advancedPayload,
                    duration: duration,
                    viewportSize: descriptor.viewportSize,
                    commentSize: metrics.size
                ) {
                    entries.append(
                        DanmakuPreparedComment(
                            appearTime: comment.appearTime,
                            endTime: comment.appearTime + duration,
                            text: displayText,
                            colorRGB: comment.colorRGB,
                            fontSize: fontSize,
                            fontFamily: fontFamily,
                            usesStroke: usesStroke,
                            size: metrics.size,
                            placement: placement,
                            alpha: alpha,
                            rotation: rotation,
                            zIndex: 2
                        )
                    )
                    continue
                }
            }

            switch comment.mode {
            case .scroll, .scrollAlt, .scrollBottom:
                let y = assignScrollLane(
                    states: &leftLaneStates,
                    appearTime: comment.appearTime,
                    endTime: comment.appearTime + duration,
                    width: metrics.size.width,
                    height: metrics.size.height,
                    duration: duration,
                    laneStride: laneStride,
                    laneSpan: min(laneSpan, scrollLaneCount),
                    topInset: 12,
                    viewportWidth: descriptor.viewportSize.width,
                    fontSize: fontSize
                )
                entries.append(
                    DanmakuPreparedComment(
                        appearTime: comment.appearTime,
                        endTime: comment.appearTime + duration,
                        text: displayText,
                        colorRGB: comment.colorRGB,
                        fontSize: fontSize,
                        fontFamily: fontFamily,
                        usesStroke: usesStroke,
                        size: metrics.size,
                        placement: .scrollLeft(
                            y: y,
                            startX: descriptor.viewportSize.width,
                            travelDistance: descriptor.viewportSize.width + metrics.size.width
                        ),
                        alpha: alpha,
                        rotation: rotation,
                        zIndex: 0
                    )
                )
            case .reverseScroll:
                let y = assignScrollLane(
                    states: &rightLaneStates,
                    appearTime: comment.appearTime,
                    endTime: comment.appearTime + duration,
                    width: metrics.size.width,
                    height: metrics.size.height,
                    duration: duration,
                    laneStride: laneStride,
                    laneSpan: min(laneSpan, scrollLaneCount),
                    topInset: 12,
                    viewportWidth: descriptor.viewportSize.width,
                    fontSize: fontSize
                )
                entries.append(
                    DanmakuPreparedComment(
                        appearTime: comment.appearTime,
                        endTime: comment.appearTime + duration,
                        text: displayText,
                        colorRGB: comment.colorRGB,
                        fontSize: fontSize,
                        fontFamily: fontFamily,
                        usesStroke: usesStroke,
                        size: metrics.size,
                        placement: .scrollRight(
                            y: y,
                            startX: -metrics.size.width,
                            travelDistance: descriptor.viewportSize.width + metrics.size.width
                        ),
                        alpha: alpha,
                        rotation: rotation,
                        zIndex: 0
                    )
                )
            case .top:
                let laneIndex = assignFixedLane(
                    states: &topLaneStates,
                    appearTime: comment.appearTime,
                    endTime: comment.appearTime + duration,
                    laneSpan: min(laneSpan, fixedLaneCount)
                )
                let y = 12 + CGFloat(laneIndex) * laneStride + max((laneStride * CGFloat(min(laneSpan, fixedLaneCount)) - metrics.size.height) / 2, 0)
                let x = max((descriptor.viewportSize.width - metrics.size.width) / 2, 0)
                entries.append(
                    DanmakuPreparedComment(
                        appearTime: comment.appearTime,
                        endTime: comment.appearTime + duration,
                        text: displayText,
                        colorRGB: comment.colorRGB,
                        fontSize: fontSize,
                        fontFamily: fontFamily,
                        usesStroke: usesStroke,
                        size: metrics.size,
                        placement: .fixed(origin: CGPoint(x: x, y: y)),
                        alpha: alpha,
                        rotation: rotation,
                        zIndex: 1
                    )
                )
            case .bottom:
                let span = min(laneSpan, fixedLaneCount)
                let laneIndex = assignFixedLane(
                    states: &bottomLaneStates,
                    appearTime: comment.appearTime,
                    endTime: comment.appearTime + duration,
                    laneSpan: span
                )
                let y = descriptor.viewportSize.height - 16 - CGFloat(laneIndex + span) * laneStride + max((laneStride * CGFloat(span) - metrics.size.height) / 2, 0)
                let x = max((descriptor.viewportSize.width - metrics.size.width) / 2, 0)
                entries.append(
                    DanmakuPreparedComment(
                        appearTime: comment.appearTime,
                        endTime: comment.appearTime + duration,
                        text: displayText,
                        colorRGB: comment.colorRGB,
                        fontSize: fontSize,
                        fontFamily: fontFamily,
                        usesStroke: usesStroke,
                        size: metrics.size,
                        placement: .fixed(origin: CGPoint(x: x, y: y)),
                        alpha: alpha,
                        rotation: rotation,
                        zIndex: 1
                    )
                )
            case .advanced:
                let laneIndex = assignFixedLane(
                    states: &topLaneStates,
                    appearTime: comment.appearTime,
                    endTime: comment.appearTime + duration,
                    laneSpan: min(laneSpan, fixedLaneCount)
                )
                let y = 12 + CGFloat(laneIndex) * laneStride + max((laneStride * CGFloat(min(laneSpan, fixedLaneCount)) - metrics.size.height) / 2, 0)
                let x = max((descriptor.viewportSize.width - metrics.size.width) / 2, 0)
                entries.append(
                    DanmakuPreparedComment(
                        appearTime: comment.appearTime,
                        endTime: comment.appearTime + duration,
                        text: displayText,
                        colorRGB: comment.colorRGB,
                        fontSize: fontSize,
                        fontFamily: fontFamily,
                        usesStroke: usesStroke,
                        size: metrics.size,
                        placement: .fixed(origin: CGPoint(x: x, y: y)),
                        alpha: alpha,
                        rotation: rotation,
                        zIndex: 2
                    )
                )
            case .code, .scripted:
                continue
            }
        }

        return DanmakuPreparedScene(
            descriptor: descriptor,
            scale: descriptor.scale,
            entries: entries,
            maximumLifetime: entries.map { $0.endTime - $0.appearTime }.max() ?? 0
        )
    }

    private static func assignScrollLane(
        states: inout [ScrollLaneState],
        appearTime: TimeInterval,
        endTime: TimeInterval,
        width: CGFloat,
        height: CGFloat,
        duration: TimeInterval,
        laneStride: CGFloat,
        laneSpan: Int,
        topInset: CGFloat,
        viewportWidth: CGFloat,
        fontSize: CGFloat
    ) -> CGFloat {
        var bestLane = 0
        var bestRequiredStart = TimeInterval.greatestFiniteMagnitude
        let clampedSpan = max(1, min(laneSpan, states.count))

        for candidateLane in 0...(states.count - clampedSpan) {
            var requiredStart = -TimeInterval.greatestFiniteMagnitude
            for offset in 0..<clampedSpan {
                let state = states[candidateLane + offset]
                requiredStart = max(
                    requiredStart,
                    scrollSafeStartTime(
                        state: state,
                        appearTime: appearTime,
                        width: width,
                        duration: duration,
                        viewportWidth: viewportWidth,
                        gap: max(fontSize * 0.45, 12)
                    )
                )
            }

            if appearTime >= requiredStart {
                bestLane = candidateLane
                bestRequiredStart = requiredStart
                break
            }

            if requiredStart < bestRequiredStart {
                bestRequiredStart = requiredStart
                bestLane = candidateLane
            }
        }

        let velocity = (viewportWidth + width) / CGFloat(max(duration, 0.01))
        let state = ScrollLaneState(
            startTime: appearTime,
            endTime: endTime,
            width: width,
            velocity: velocity
        )
        for offset in 0..<clampedSpan {
            states[bestLane + offset] = state
        }

        return topInset + CGFloat(bestLane) * laneStride + max((laneStride * CGFloat(clampedSpan) - height) / 2, 0)
    }

    private static func assignFixedLane(
        states: inout [FixedLaneState],
        appearTime: TimeInterval,
        endTime: TimeInterval,
        laneSpan: Int
    ) -> Int {
        let clampedSpan = max(1, min(laneSpan, states.count))
        var fallbackLane = 0
        var earliestEnd = TimeInterval.greatestFiniteMagnitude

        for candidateLane in 0...(states.count - clampedSpan) {
            var safe = true
            var latestEnd = -TimeInterval.greatestFiniteMagnitude
            for offset in 0..<clampedSpan {
                latestEnd = max(latestEnd, states[candidateLane + offset].endTime)
                if states[candidateLane + offset].endTime > appearTime {
                    safe = false
                }
            }

            if safe {
                for offset in 0..<clampedSpan {
                    states[candidateLane + offset] = FixedLaneState(endTime: endTime)
                }
                return candidateLane
            }

            if latestEnd < earliestEnd {
                earliestEnd = latestEnd
                fallbackLane = candidateLane
            }
        }

        for offset in 0..<clampedSpan {
            states[fallbackLane + offset] = FixedLaneState(endTime: endTime)
        }
        return fallbackLane
    }

    private static func scrollSafeStartTime(
        state: ScrollLaneState,
        appearTime: TimeInterval,
        width: CGFloat,
        duration: TimeInterval,
        viewportWidth: CGFloat,
        gap: CGFloat
    ) -> TimeInterval {
        guard state.width > 0 else { return -.greatestFiniteMagnitude }
        let newVelocity = (viewportWidth + width) / CGFloat(max(duration, 0.01))
        let tailSafe = state.startTime + TimeInterval((state.width + gap) / max(state.velocity, 1))
        let catchupSafe = state.endTime - TimeInterval(max(viewportWidth - gap, 0) / max(newVelocity, 1))
        return max(tailSafe, catchupSafe, appearTime - 60)
    }

    private static func alphaRange(for comment: DanmakuComment) -> ClosedRange<Double> {
        guard let payload = comment.advancedPayload else { return 1...1 }
        let lower = normalizeAlpha(payload.alphaFrom) ?? 1
        let upper = normalizeAlpha(payload.alphaTo) ?? lower
        return lower...upper
    }

    private static func rotationRange(for comment: DanmakuComment) -> ClosedRange<Double> {
        guard let payload = comment.advancedPayload else { return 0...0 }
        let start = payload.rotationZ ?? 0
        let end = payload.endRotationZ ?? start
        return start...end
    }

    private static func advancedPlacement(
        for comment: DanmakuComment,
        payload: DanmakuAdvancedPayload?,
        duration: TimeInterval,
        viewportSize: CGSize,
        commentSize: CGSize
    ) -> DanmakuPlacement? {
        guard let payload else { return nil }

        var points = payload.path ?? []
        if points.isEmpty, let startX = payload.startX, let startY = payload.startY {
            points.append(CGPoint(x: startX, y: startY))
        }
        if let endX = payload.endX, let endY = payload.endY {
            let endPoint = CGPoint(x: endX, y: endY)
            if points.last.map({ approximatelyEqual($0, endPoint) }) != true {
                points.append(endPoint)
            }
        }

        guard points.isEmpty == false else { return nil }

        let normalized = points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }
        let resolvedPoints = points.map {
            resolve(point: $0, normalized: normalized, viewportSize: viewportSize, commentSize: commentSize)
        }

        if resolvedPoints.count == 1 {
            return .fixed(origin: resolvedPoints[0])
        }

        let delay = max(payload.translationDelay, 0)
        let motionDuration = max(payload.translationDuration ?? max(duration - delay, 0), 0)
        if motionDuration <= 0.0001 {
            return .fixed(origin: resolvedPoints[0])
        }

        return .motion(
            DanmakuMotionTrajectory(
                points: resolvedPoints,
                delay: delay,
                duration: motionDuration,
                curve: payload.motionCurve
            )
        )
    }

    private static func resolve(
        point: CGPoint,
        normalized: Bool,
        viewportSize: CGSize,
        commentSize: CGSize
    ) -> CGPoint {
        guard normalized else { return point }
        return CGPoint(
            x: point.x * max(viewportSize.width - commentSize.width, 0),
            y: point.y * max(viewportSize.height - commentSize.height, 0)
        )
    }

    private static func approximatelyEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.0001 && abs(lhs.y - rhs.y) < 0.0001
    }

    private static func normalizeAlpha(_ rawValue: Double?) -> Double? {
        guard let rawValue else { return nil }
        if rawValue > 1 {
            return min(max(rawValue / 255, 0), 1)
        }
        return min(max(rawValue, 0), 1)
    }

    private static func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(max(value, minimum), maximum)
    }
}

private struct ScrollLaneState: Sendable {
    var startTime: TimeInterval = -.greatestFiniteMagnitude
    var endTime: TimeInterval = -.greatestFiniteMagnitude
    var width: CGFloat = 0
    var velocity: CGFloat = 1
}

private struct FixedLaneState: Sendable {
    var endTime: TimeInterval = -.greatestFiniteMagnitude
}

private final class DanmakuTextMetricsBox: NSObject {
    let value: DanmakuTextMetrics

    init(_ value: DanmakuTextMetrics) {
        self.value = value
    }
}

private final class DanmakuImageBox: NSObject {
    let value: CGImage

    init(_ value: CGImage) {
        self.value = value
    }
}

private struct DanmakuTextMetrics: Sendable {
    var size: CGSize
    var padding: CGFloat
    var ascent: CGFloat
    var descent: CGFloat
}

private final class DanmakuTextRasterCache: @unchecked Sendable {
    private let metricsCache = NSCache<NSString, DanmakuTextMetricsBox>()
    private let imageCache = NSCache<NSString, DanmakuImageBox>()

    init() {
        metricsCache.countLimit = 8_192
        imageCache.countLimit = 4_096
        imageCache.totalCostLimit = 128 * 1024 * 1024
    }

    func metrics(
        for text: String,
        fontSize: CGFloat,
        fontFamily: String?,
        usesStroke: Bool
    ) -> DanmakuTextMetrics {
        let key = NSString(
            string: "m|\(cacheValue(fontSize))|\(fontFamily ?? "<system>")|\(usesStroke ? 1 : 0)|\(text)"
        )
        if let cached = metricsCache.object(forKey: key) {
            return cached.value
        }

        let font = makeFont(size: fontSize, family: fontFamily)
        let strokeWidth = usesStroke ? strokeWidth(for: fontSize) : 0
        let line = makeLine(text: text, font: font, color: NSColor.white.cgColor, strokeWidth: strokeWidth)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let padding = ceil(max(strokeWidth + 2, fontSize * 0.12))
        let metrics = DanmakuTextMetrics(
            size: CGSize(
                width: ceil(width) + padding * 2,
                height: ceil(ascent + descent + leading) + padding * 2
            ),
            padding: padding,
            ascent: ascent,
            descent: descent
        )
        metricsCache.setObject(DanmakuTextMetricsBox(metrics), forKey: key)
        return metrics
    }

    func image(for comment: DanmakuPreparedComment, scale: CGFloat) -> CGImage? {
        let key = NSString(
            string: "i|\(cacheValue(comment.fontSize))|\(cacheValue(scale))|\(comment.fontFamily ?? "<system>")|\(comment.usesStroke ? 1 : 0)|\(comment.colorRGB)|\(comment.text)"
        )
        if let cached = imageCache.object(forKey: key) {
            return cached.value
        }

        let metrics = metrics(
            for: comment.text,
            fontSize: comment.fontSize,
            fontFamily: comment.fontFamily,
            usesStroke: comment.usesStroke
        )
        let pixelWidth = max(Int(ceil(metrics.size.width * scale)), 1)
        let pixelHeight = max(Int(ceil(metrics.size.height * scale)), 1)

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: metrics.size.height)
        context.scaleBy(x: 1, y: -1)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        let font = makeFont(size: comment.fontSize, family: comment.fontFamily)
        let line = makeLine(
            text: comment.text,
            font: font,
            color: color(for: comment.colorRGB),
            strokeWidth: comment.usesStroke ? strokeWidth(for: comment.fontSize) : 0
        )
        context.textPosition = CGPoint(x: metrics.padding, y: metrics.padding + metrics.descent)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else { return nil }
        imageCache.setObject(
            DanmakuImageBox(image),
            forKey: key,
            cost: pixelWidth * pixelHeight * 4
        )
        return image
    }

    private func makeFont(size: CGFloat, family: String?) -> CTFont {
        if let family, family.isEmpty == false {
            let custom = CTFontCreateWithName(family as CFString, size, nil)
            let postScriptName = CTFontCopyPostScriptName(custom) as String
            if postScriptName.caseInsensitiveCompare(family) == .orderedSame
                || postScriptName.localizedCaseInsensitiveContains(family) {
                return custom
            }
        }
        return CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size, nil)
    }

    private func makeLine(text: String, font: CTFont, color: CGColor, strokeWidth: CGFloat) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        if strokeWidth > 0 {
            attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = NSColor.black.withAlphaComponent(0.92).cgColor
            attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = -strokeWidth
        }
        let attributed = NSAttributedString(string: text, attributes: attributes)
        return CTLineCreateWithAttributedString(attributed)
    }

    private func color(for rgb: UInt32) -> CGColor {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        return NSColor(red: red, green: green, blue: blue, alpha: 1).cgColor
    }

    private func strokeWidth(for fontSize: CGFloat) -> CGFloat {
        min(max(fontSize * 0.14, 2.25), 5)
    }

    private func cacheValue(_ value: CGFloat) -> Int {
        Int((value * 100).rounded())
    }
}
#else
public struct DanmakuRendererOverlay: View {
    public let document: DanmakuDocument?
    public let documentID: UUID?
    public let playbackTime: TimeInterval
    public let isPlaybackActive: Bool
    public let playbackRate: Double
    public let settings: DanmakuRenderSettings

    public init(
        document: DanmakuDocument?,
        documentID: UUID? = nil,
        playbackTime: TimeInterval,
        isPlaybackActive: Bool,
        playbackRate: Double = 1,
        settings: DanmakuRenderSettings
    ) {
        self.document = document
        self.documentID = documentID
        self.playbackTime = playbackTime
        self.isPlaybackActive = isPlaybackActive
        self.playbackRate = playbackRate
        self.settings = settings
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
