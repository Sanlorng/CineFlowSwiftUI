import SwiftUI
import DanmakuRendererCore

#if os(macOS)
import AppKit
import CoreText
import MetalKit
import QuartzCore

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
    fileprivate struct Snapshot: Equatable {
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

    private let metalView = DanmakuMetalView(frame: .zero)
    private let debugBadge = DanmakuDebugBadgeView(frame: .zero)
    private var lastAppliedSnapshot = Snapshot.empty

    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { false }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(metalView)
        addSubview(debugBadge)
        metalView.onStatsChanged = { [weak self] text in
            self?.debugBadge.text = text
            self?.needsLayout = true
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func apply(snapshot: Snapshot) {
        guard snapshot != lastAppliedSnapshot else { return }
        lastAppliedSnapshot = snapshot
        metalView.apply(snapshot: snapshot)
    }

    public override func layout() {
        super.layout()
        metalView.frame = bounds

        let badgeSize = debugBadge.intrinsicContentSize
        debugBadge.frame = CGRect(
            x: max(bounds.width - badgeSize.width - 14, 0),
            y: 14,
            width: badgeSize.width,
            height: badgeSize.height
        )
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        metalView.updateViewportAndRefresh()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        metalView.updateViewportAndRefresh()
    }
}

private final class DanmakuDebugBadgeView: NSView {
    var text: String = "DMK --" {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    override var isOpaque: Bool { false }

    override var intrinsicContentSize: CGSize {
        let attributed = makeAttributedText()
        let textSize = attributed.size()
        return CGSize(width: ceil(textSize.width) + 16, height: ceil(textSize.height) + 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let badgePath = NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9)
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.58).cgColor)
        context.addPath(badgePath.cgPath)
        context.fillPath()
        context.restoreGState()

        let attributed = makeAttributedText()
        let textSize = attributed.size()
        let textRect = CGRect(
            x: bounds.maxX - textSize.width - 8,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributed.draw(in: textRect)
    }

    private func makeAttributedText() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}

private final class DanmakuMetalView: NSView {
    var onStatsChanged: ((String) -> Void)?

    private let playbackTimeResyncThreshold: TimeInterval = 1.0 / 12.0
    private let renderQueue = DispatchQueue(label: "CineFlow.DanmakuMetalRenderLoop", qos: .userInteractive)
    private let displayLinkSemaphore = DispatchSemaphore(value: 1)
    private let renderer: DanmakuCanvasRenderer
    private let device: MTLDevice?
    private let compositor: DanmakuMetalCompositor?
    private var metalLayer: CAMetalLayer?
    nonisolated(unsafe) private var displayLink: CADisplayLink?
    private var snapshot = DanmakuOverlayView.Snapshot.empty
    private var currentViewport = DanmakuCanvasViewport(size: .zero, scale: 2)
    private var isAttachedToWindow = false
    private var isAnimating = false
    private var drawSampleStartedAt = CACurrentMediaTime()
    private var drawCount = 0
    private var measuredFPS = 0.0
    private var targetFPS = 60.0

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        let resolvedDevice = MTLCreateSystemDefaultDevice()
        self.renderer = DanmakuCanvasRenderer(callbackQueue: renderQueue)
        self.device = resolvedDevice
        self.compositor = resolvedDevice.flatMap(DanmakuMetalCompositor.init(device:))
        super.init(frame: frameRect)
        commonInit()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        metalLayer = makeMetalLayer()
        layer = metalLayer
        layer?.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "backgroundColor": NSNull()
        ]
        setupDisplayLink()

        renderer.onInvalidation = { [weak self] in
            self?.handleRendererInvalidationLocked()
        }
    }

    func apply(snapshot: DanmakuOverlayView.Snapshot) {
        let surfaceState = currentSurfaceState()
        renderQueue.async {
            let shouldRefresh = self.shouldRefreshRenderer(for: snapshot)
            self.snapshot = snapshot
            self.apply(surfaceState: surfaceState)
            guard shouldRefresh else {
                self.updateAnimationStateLocked()
                return
            }
            self.updateRendererLocked()
        }
    }

    func updateViewportAndRefresh() {
        let surfaceState = currentSurfaceState()
        updateMetalLayerGeometry(with: surfaceState.viewport)
        renderQueue.async {
            self.apply(surfaceState: surfaceState)
            self.updateRendererLocked()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateViewportAndRefresh()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateViewportAndRefresh()
    }

    override func layout() {
        super.layout()
        updateViewportAndRefresh()
    }

    deinit {
        if let displayLink {
            displayLink.invalidate()
        }
    }

    private func makeMetalLayer() -> CAMetalLayer {
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.backgroundColor = NSColor.clear.cgColor
        return layer
    }

    private func setupDisplayLink() {
        let displayLink = displayLink(
            target: self,
            selector: #selector(handleDisplayLinkTick(_:))
        )
        displayLink.add(to: .main, forMode: .common)
        displayLink.isPaused = true
        self.displayLink = displayLink
    }

    private func currentSurfaceState() -> DanmakuSurfaceState {
        DanmakuSurfaceState(
            viewport: .init(
                size: bounds.size,
                scale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            ),
            isAttachedToWindow: window != nil,
            targetFPS: {
                if let screen = window?.screen, #available(macOS 12.0, *) {
                    return Double(screen.maximumFramesPerSecond)
                }
                return 60
            }()
        )
    }

    private func updateMetalLayerGeometry(with viewport: DanmakuCanvasViewport) {
        guard let metalLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.contentsScale = viewport.scale
        metalLayer.drawableSize = CGSize(
            width: max(viewport.size.width * viewport.scale, 1),
            height: max(viewport.size.height * viewport.scale, 1)
        )
        CATransaction.commit()
    }

    private func apply(surfaceState: DanmakuSurfaceState) {
        currentViewport = surfaceState.viewport
        isAttachedToWindow = surfaceState.isAttachedToWindow
        targetFPS = surfaceState.targetFPS
    }

    private func updateRendererLocked() {
        renderer.update(
            document: snapshot.document,
            documentID: snapshot.documentID,
            playbackTime: snapshot.playbackTime,
            isPlaybackActive: snapshot.isPlaybackActive,
            playbackRate: snapshot.playbackRate,
            settings: snapshot.settings,
            viewport: currentViewport
        )
        updateAnimationStateLocked()
        requestImmediateDrawIfNeededLocked()
    }

    private func shouldRefreshRenderer(for newSnapshot: DanmakuOverlayView.Snapshot) -> Bool {
        // Let the internal playback clock free-run while playback is stable.
        // Re-sync only when scene inputs change, playback state changes,
        // or the external player time has drifted materially.
        if newSnapshot.documentID != snapshot.documentID
            || newSnapshot.document != snapshot.document
            || newSnapshot.settings != snapshot.settings {
            return true
        }

        if newSnapshot.isPlaybackActive != snapshot.isPlaybackActive
            || abs(newSnapshot.playbackRate - snapshot.playbackRate) >= 0.0001 {
            return true
        }

        if newSnapshot.isPlaybackActive == false {
            return abs(newSnapshot.playbackTime - snapshot.playbackTime) >= 0.0001
        }

        let playbackDrift = abs(newSnapshot.playbackTime - renderer.presentationTime)
        return playbackDrift >= playbackTimeResyncThreshold
    }

    private func updateAnimationStateLocked() {
        let shouldAnimate = renderer.shouldAnimate && compositor != nil && isAttachedToWindow && currentViewport.isRenderable
        guard shouldAnimate != isAnimating else { return }
        isAnimating = shouldAnimate
        configureDisplayLink(shouldAnimate: shouldAnimate, targetFPS: targetFPS)
    }

    private func requestImmediateDrawIfNeededLocked() {
        guard isAttachedToWindow, isAnimating == false else { return }
        drawFrameLocked()
    }

    private func handleRendererInvalidationLocked() {
        updateAnimationStateLocked()
        requestImmediateDrawIfNeededLocked()
    }

    private func drawFrameLocked() {
        guard let compositor,
              isAttachedToWindow,
              currentViewport.isRenderable,
              let metalLayer,
              let drawable = metalLayer.nextDrawable() else {
            return
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )

        renderer.withFrameAssets(
            in: CGRect(origin: .zero, size: currentViewport.size)
        ) { prewarmAssets, sprites in
            compositor.draw(
                sprites: sprites,
                prewarmAssets: prewarmAssets,
                drawable: drawable,
                renderPassDescriptor: descriptor,
                viewportSize: currentViewport.size
            )
        }
        recordDrawLocked()
    }

    fileprivate func enqueueDisplayLinkDraw() {
        guard displayLinkSemaphore.wait(timeout: .now()) == .success else { return }
        renderQueue.async {
            self.drawFrameLocked()
            self.displayLinkSemaphore.signal()
        }
    }

    private func configureDisplayLink(shouldAnimate: Bool, targetFPS: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let displayLink = self.displayLink else { return }
            if #available(macOS 14.0, *) {
                let preferredFPS = Float(max(targetFPS, 30))
                displayLink.preferredFrameRateRange = CAFrameRateRange(
                    minimum: 30,
                    maximum: preferredFPS,
                    preferred: preferredFPS
                )
            }
            displayLink.isPaused = !shouldAnimate
        }
    }

    @objc
    private func handleDisplayLinkTick(_ displayLink: CADisplayLink) {
        enqueueDisplayLinkDraw()
    }

    private func recordDrawLocked() {
        let now = CACurrentMediaTime()
        drawCount += 1
        let elapsed = now - drawSampleStartedAt
        guard elapsed >= 0.4 else { return }

        let instantaneousFPS = Double(drawCount) / elapsed
        if measuredFPS == 0 {
            measuredFPS = instantaneousFPS
        } else {
            measuredFPS = (measuredFPS * 0.7) + (instantaneousFPS * 0.3)
        }
        drawCount = 0
        drawSampleStartedAt = now
        let text = String(format: "DMK %.1f / %.0f FPS", measuredFPS, targetFPS)
        DispatchQueue.main.async { [weak self] in
            self?.onStatsChanged?(text)
        }
    }
}

private struct DanmakuSurfaceState {
    let viewport: DanmakuCanvasViewport
    let isAttachedToWindow: Bool
    let targetFPS: Double
}

private struct DanmakuSprite {
    let textureKey: NSString
    let image: CGImage
    let frame: CGRect
    let alpha: Float
    let rotation: Float
}

private struct DanmakuMetalInstance {
    var center: SIMD2<Float>
    var halfSize: SIMD2<Float>
    var uvMin: SIMD2<Float>
    var uvMax: SIMD2<Float>
    var rotation: SIMD2<Float>
    var alpha: Float
    var textureIndex: Float
}

private struct DanmakuAtlasEntry {
    let pageIndex: Int
    let uvMin: SIMD2<Float>
    let uvMax: SIMD2<Float>
}

private final class DanmakuAtlasEntryBox: NSObject {
    let value: DanmakuAtlasEntry

    init(_ value: DanmakuAtlasEntry) {
        self.value = value
    }
}

private struct DanmakuAtlasPlacement {
    let pageIndex: Int
    let origin: MTLOrigin
}

private final class DanmakuInstanceBufferAllocator {
    private let alignment = 256
    private let device: MTLDevice
    private(set) var buffer: MTLBuffer
    private var cursor = 0

    init?(device: MTLDevice, initialLength: Int) {
        self.device = device
        guard let buffer = device.makeBuffer(
            length: max(initialLength, alignment),
            options: .storageModeShared
        ) else {
            return nil
        }
        self.buffer = buffer
    }

    func reset() {
        cursor = 0
    }

    func allocate<T>(from values: [T]) -> (buffer: MTLBuffer, offset: Int)? {
        let byteCount = values.count * MemoryLayout<T>.stride
        guard byteCount > 0 else { return nil }

        let alignedOffset = aligned(cursor)
        let requiredLength = alignedOffset + byteCount
        guard ensureCapacity(requiredLength) else { return nil }

        values.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            memcpy(buffer.contents().advanced(by: alignedOffset), baseAddress, rawBuffer.count)
        }
        cursor = requiredLength
        return (buffer, alignedOffset)
    }

    private func ensureCapacity(_ requiredLength: Int) -> Bool {
        guard requiredLength > buffer.length else { return true }

        var newLength = max(buffer.length, alignment)
        while newLength < requiredLength {
            newLength *= 2
        }

        guard let newBuffer = device.makeBuffer(length: newLength, options: .storageModeShared) else {
            return false
        }
        buffer = newBuffer
        return true
    }

    private func aligned(_ value: Int) -> Int {
        ((value + alignment - 1) / alignment) * alignment
    }
}

private final class DanmakuInstanceBufferPool {
    private let availabilitySemaphore: DispatchSemaphore
    private let lock = NSLock()
    private var availableAllocators: [DanmakuInstanceBufferAllocator]

    init?(device: MTLDevice, allocatorCount: Int = 3, initialLength: Int = 256 * 1024) {
        var allocators: [DanmakuInstanceBufferAllocator] = []
        allocators.reserveCapacity(max(allocatorCount, 1))
        for _ in 0..<max(allocatorCount, 1) {
            guard let allocator = DanmakuInstanceBufferAllocator(
                device: device,
                initialLength: initialLength
            ) else {
                return nil
            }
            allocators.append(allocator)
        }
        self.availableAllocators = allocators
        self.availabilitySemaphore = DispatchSemaphore(value: allocators.count)
    }

    func checkout() -> DanmakuInstanceBufferAllocator? {
        availabilitySemaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return availableAllocators.popLast()
    }

    func `return`(_ allocator: DanmakuInstanceBufferAllocator) {
        allocator.reset()
        lock.lock()
        availableAllocators.append(allocator)
        lock.unlock()
        availabilitySemaphore.signal()
    }
}

private final class DanmakuAtlasPage {
    let index: Int
    let texture: MTLTexture
    let width: Int
    let height: Int

    private var nextX = 0
    private var nextY = 0
    private var rowHeight = 0

    init(index: Int, texture: MTLTexture) {
        self.index = index
        self.texture = texture
        self.width = texture.width
        self.height = texture.height
    }

    func allocate(contentWidth: Int, contentHeight: Int, padding: Int) -> DanmakuAtlasPlacement? {
        let requiredWidth = contentWidth + padding * 2
        let requiredHeight = contentHeight + padding * 2
        guard requiredWidth <= width, requiredHeight <= height else { return nil }

        if nextX + requiredWidth > width {
            nextX = 0
            nextY += rowHeight
            rowHeight = 0
        }

        guard nextY + requiredHeight <= height else { return nil }

        let placement = DanmakuAtlasPlacement(
            pageIndex: index,
            origin: MTLOrigin(x: nextX + padding, y: nextY + padding, z: 0)
        )
        nextX += requiredWidth
        rowHeight = max(rowHeight, requiredHeight)
        return placement
    }
}

private final class DanmakuMetalCompositor {
    private let atlasTextureDimension = 2048
    private let atlasPadding = 1
    private let maxTextureSlotsPerDraw = 16
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let textureLoader: MTKTextureLoader
    private let instanceBufferPool: DanmakuInstanceBufferPool
    private let atlasCache = NSCache<NSString, DanmakuAtlasEntryBox>()
    private var atlasPages: [DanmakuAtlasPage] = []
    private var currentInstancesScratch: [DanmakuMetalInstance] = []
    private var currentTexturesScratch: [MTLTexture] = []
    private var currentTextureSlotsScratch: [Int: Int] = [:]

    init?(device: MTLDevice) {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else { return nil }
        self.commandQueue = commandQueue
        self.textureLoader = MTKTextureLoader(device: device)
        guard let instanceBufferPool = DanmakuInstanceBufferPool(device: device) else {
            return nil
        }
        self.instanceBufferPool = instanceBufferPool
        self.atlasCache.countLimit = 4096
        self.atlasCache.totalCostLimit = 192 * 1024 * 1024

        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct InstanceIn {
            float2 center;
            float2 halfSize;
            float2 uvMin;
            float2 uvMax;
            float2 rotation;
            float alpha;
            float textureIndex;
        };

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
            float alpha;
            float textureIndex;
        };

        vertex VertexOut danmaku_vertex(
            const device InstanceIn *instances [[buffer(0)]],
            constant float2 &viewportSize [[buffer(1)]],
            uint vertexID [[vertex_id]],
            uint instanceID [[instance_id]]
        ) {
            const float2 localCorners[6] = {
                float2(-1.0, -1.0),
                float2( 1.0, -1.0),
                float2(-1.0,  1.0),
                float2(-1.0,  1.0),
                float2( 1.0, -1.0),
                float2( 1.0,  1.0)
            };
            const float2 texCorners[6] = {
                float2(0.0, 0.0),
                float2(1.0, 0.0),
                float2(0.0, 1.0),
                float2(0.0, 1.0),
                float2(1.0, 0.0),
                float2(1.0, 1.0)
            };

            VertexOut out;
            InstanceIn instance = instances[instanceID];
            float2 local = localCorners[vertexID] * instance.halfSize;
            float2 rotated = float2(
                local.x * instance.rotation.x - local.y * instance.rotation.y,
                local.x * instance.rotation.y + local.y * instance.rotation.x
            );
            float2 world = instance.center + rotated;
            float2 clip = float2(
                (world.x / max(viewportSize.x, 1.0)) * 2.0 - 1.0,
                1.0 - (world.y / max(viewportSize.y, 1.0)) * 2.0
            );

            out.position = float4(clip, 0.0, 1.0);
            out.texCoord = mix(instance.uvMin, instance.uvMax, texCorners[vertexID]);
            out.alpha = instance.alpha;
            out.textureIndex = instance.textureIndex;
            return out;
        }

        fragment float4 danmaku_fragment(
            VertexOut in [[stage_in]],
            array<texture2d<float>, 16> textures [[texture(0)]],
            sampler texSampler [[sampler(0)]]
        ) {
            uint textureIndex = uint(in.textureIndex + 0.5);
            float4 color = textures[textureIndex].sample(texSampler, in.texCoord);
            return float4(color.rgb * in.alpha, color.a * in.alpha);
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "danmaku_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "danmaku_fragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else {
            return nil
        }
        self.samplerState = samplerState
    }

    func draw(
        sprites: [DanmakuSprite],
        prewarmAssets: [DanmakuRasterImage],
        drawable: CAMetalDrawable,
        renderPassDescriptor descriptor: MTLRenderPassDescriptor,
        viewportSize: CGSize
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        guard let instanceAllocator = instanceBufferPool.checkout() else {
            return
        }
        instanceAllocator.reset()

        prepareAtlasEntries(
            sprites,
            prewarmAssets: prewarmAssets,
            commandBuffer: commandBuffer
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            instanceBufferPool.return(instanceAllocator)
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        var viewportSize = SIMD2<Float>(
            Float(max(viewportSize.width, 1)),
            Float(max(viewportSize.height, 1))
        )
        encoder.setVertexBytes(
            &viewportSize,
            length: MemoryLayout<SIMD2<Float>>.stride,
            index: 1
        )

        encodeSprites(
            sprites,
            with: encoder,
            instanceAllocator: instanceAllocator
        )

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.instanceBufferPool.return(instanceAllocator)
        }
        commandBuffer.commit()
    }

    private func prepareAtlasEntries(
        _ sprites: [DanmakuSprite],
        prewarmAssets: [DanmakuRasterImage],
        commandBuffer: MTLCommandBuffer
    ) {
        var blitEncoder: MTLBlitCommandEncoder?
        for asset in prewarmAssets {
            _ = atlasEntry(
                textureKey: asset.key,
                image: asset.image,
                commandBuffer: commandBuffer,
                blitEncoder: &blitEncoder
            )
        }
        for sprite in sprites {
            _ = atlasEntry(
                textureKey: sprite.textureKey,
                image: sprite.image,
                commandBuffer: commandBuffer,
                blitEncoder: &blitEncoder
            )
        }
        blitEncoder?.endEncoding()
    }

    private func encodeSprites(
        _ sprites: [DanmakuSprite],
        with encoder: MTLRenderCommandEncoder,
        instanceAllocator: DanmakuInstanceBufferAllocator
    ) {
        currentInstancesScratch.removeAll(keepingCapacity: true)
        currentTexturesScratch.removeAll(keepingCapacity: true)
        currentTextureSlotsScratch.removeAll(keepingCapacity: true)
        currentInstancesScratch.reserveCapacity(sprites.count)

        for sprite in sprites {
            guard let atlasEntry = cachedAtlasEntry(for: sprite.textureKey) else { continue }
            let slot: Int
            if let existingSlot = currentTextureSlotsScratch[atlasEntry.pageIndex] {
                slot = existingSlot
            } else {
                if currentTexturesScratch.count >= maxTextureSlotsPerDraw {
                    flushCurrentSegment(
                        with: encoder,
                        instanceAllocator: instanceAllocator
                    )
                }
                slot = currentTexturesScratch.count
                currentTextureSlotsScratch[atlasEntry.pageIndex] = slot
                currentTexturesScratch.append(atlasPages[atlasEntry.pageIndex].texture)
            }

            currentInstancesScratch.append(
                makeInstance(
                    for: sprite,
                    atlasEntry: atlasEntry,
                    textureSlot: slot
                )
            )
        }
        flushCurrentSegment(with: encoder, instanceAllocator: instanceAllocator)
    }

    private func flushCurrentSegment(
        with encoder: MTLRenderCommandEncoder,
        instanceAllocator: DanmakuInstanceBufferAllocator
    ) {
        guard currentInstancesScratch.isEmpty == false,
              let instanceAllocation = instanceAllocator.allocate(from: currentInstancesScratch) else {
            return
        }

        encoder.setVertexBuffer(instanceAllocation.buffer, offset: instanceAllocation.offset, index: 0)
        encoder.setFragmentTextures(currentTexturesScratch, range: 0..<currentTexturesScratch.count)
        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6,
            instanceCount: currentInstancesScratch.count
        )

        currentInstancesScratch.removeAll(keepingCapacity: true)
        currentTexturesScratch.removeAll(keepingCapacity: true)
        currentTextureSlotsScratch.removeAll(keepingCapacity: true)
    }

    private func atlasEntry(
        textureKey: NSString,
        image: CGImage,
        commandBuffer: MTLCommandBuffer,
        blitEncoder: inout MTLBlitCommandEncoder?
    ) -> DanmakuAtlasEntry? {
        if let cached = atlasCache.object(forKey: textureKey) {
            return cached.value
        }

        guard let sourceTexture = makeSourceTexture(image: image),
              let placement = allocateAtlasPlacement(
                contentWidth: sourceTexture.width,
                contentHeight: sourceTexture.height
              ) else {
            return nil
        }

        if blitEncoder == nil {
            blitEncoder = commandBuffer.makeBlitCommandEncoder()
        }
        blitEncoder?.copy(
            from: sourceTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: sourceTexture.width, height: sourceTexture.height, depth: 1),
            to: atlasPages[placement.pageIndex].texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: placement.origin
        )

        let atlasPage = atlasPages[placement.pageIndex]
        let halfTexelX = sourceTexture.width > 1 ? 0.5 / Float(atlasPage.width) : 0
        let halfTexelY = sourceTexture.height > 1 ? 0.5 / Float(atlasPage.height) : 0
        let uvMin = SIMD2<Float>(
            Float(placement.origin.x) / Float(atlasPage.width) + halfTexelX,
            Float(placement.origin.y) / Float(atlasPage.height) + halfTexelY
        )
        let uvMax = SIMD2<Float>(
            Float(placement.origin.x + sourceTexture.width) / Float(atlasPage.width) - halfTexelX,
            Float(placement.origin.y + sourceTexture.height) / Float(atlasPage.height) - halfTexelY
        )

        let entry = DanmakuAtlasEntry(
            pageIndex: placement.pageIndex,
            uvMin: uvMin,
            uvMax: uvMax
        )
        atlasCache.setObject(
            DanmakuAtlasEntryBox(entry),
            forKey: textureKey,
            cost: sourceTexture.width * sourceTexture.height * 4
        )
        return entry
    }

    private func cachedAtlasEntry(for textureKey: NSString) -> DanmakuAtlasEntry? {
        atlasCache.object(forKey: textureKey)?.value
    }

    private func makeSourceTexture(image: CGImage) -> MTLTexture? {
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            .origin: MTKTextureLoader.Origin.bottomLeft
        ]
        return try? textureLoader.newTexture(cgImage: image, options: options)
    }

    private func allocateAtlasPlacement(
        contentWidth: Int,
        contentHeight: Int
    ) -> DanmakuAtlasPlacement? {
        for page in atlasPages {
            if let placement = page.allocate(
                contentWidth: contentWidth,
                contentHeight: contentHeight,
                padding: atlasPadding
            ) {
                return placement
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: atlasTextureDimension,
            height: atlasTextureDimension,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        let page = DanmakuAtlasPage(
            index: atlasPages.count,
            texture: texture
        )
        atlasPages.append(page)
        return page.allocate(
            contentWidth: contentWidth,
            contentHeight: contentHeight,
            padding: atlasPadding
        )
    }

    private func makeInstance(
        for sprite: DanmakuSprite,
        atlasEntry: DanmakuAtlasEntry,
        textureSlot: Int
    ) -> DanmakuMetalInstance {
        let angle = Double(sprite.rotation)
        return DanmakuMetalInstance(
            center: SIMD2<Float>(
                Float(sprite.frame.midX),
                Float(sprite.frame.midY)
            ),
            halfSize: SIMD2<Float>(
                Float(sprite.frame.width * 0.5),
                Float(sprite.frame.height * 0.5)
            ),
            uvMin: atlasEntry.uvMin,
            uvMax: atlasEntry.uvMax,
            rotation: SIMD2<Float>(
                Float(cos(angle)),
                Float(sin(angle))
            ),
            alpha: sprite.alpha,
            textureIndex: Float(textureSlot)
        )
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

    private let callbackQueue: DispatchQueue
    private let textCache = DanmakuTextRasterCache()
    private let scheduler = DanmakuPlaybackScheduler()
    private let clock = DanmakuPlaybackClock()
    private let preparationQueue = DispatchQueue(label: "CineFlow.DanmakuSceneBuilder", qos: .userInitiated)

    private var preparedScene: DanmakuPreparedScene?
    private var sceneDescriptor: DanmakuSceneDescriptor?
    private var preparationGeneration = 0
    private var currentSettings = DanmakuRenderSettings()
    private var visibleEntriesScratch: [DanmakuPreparedComment] = []
    private var spriteBuckets: [[DanmakuSprite]] = [[], [], []]
    private var spriteScratch: [DanmakuSprite] = []
    private var prewarmScratch: [DanmakuRasterImage] = []

    init(callbackQueue: DispatchQueue) {
        self.callbackQueue = callbackQueue
    }

    var shouldAnimate: Bool {
        currentSettings.isVisible && preparedScene != nil && clock.isActive
    }

    var presentationTime: TimeInterval {
        clock.currentTime
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
            self.callbackQueue.async { [weak self] in
                guard let self else { return }
                guard self.preparationGeneration == generation, self.sceneDescriptor == descriptor else { return }
                self.preparedScene = scene
                self.scheduler.reset(scene: scene, time: self.clock.currentTime)
                self.onInvalidation?()
            }
        }
    }

    func withFrameAssets(
        in bounds: CGRect,
        prewarmLookahead: TimeInterval = 2,
        maximumPrewarmCount: Int = 24,
        _ body: ([DanmakuRasterImage], [DanmakuSprite]) -> Void
    ) {
        guard currentSettings.isVisible,
              let preparedScene,
              bounds.isEmpty == false else {
            body([], [])
            return
        }

        let currentTime = clock.currentTime
        scheduler.populateVisibleEntries(
            at: currentTime,
            sceneEntries: preparedScene.entries,
            into: &visibleEntriesScratch
        )
        let scale = boundsScale(preparedScene: preparedScene)
        prewarmScratch.removeAll(keepingCapacity: true)
        if maximumPrewarmCount > 0 {
            let lowerBound = preparedScene.lowerBound(for: currentTime)
            let upperBound = preparedScene.upperBound(for: currentTime + max(prewarmLookahead, 0))
            if lowerBound < upperBound {
                prewarmScratch.reserveCapacity(min(maximumPrewarmCount, upperBound - lowerBound))
                for entry in preparedScene.entries[lowerBound..<upperBound] {
                    guard let asset = textCache.imageAsset(for: entry, scale: scale) else { continue }
                    prewarmScratch.append(asset)
                    if prewarmScratch.count >= maximumPrewarmCount {
                        break
                    }
                }
            }
        }

        for index in spriteBuckets.indices {
            spriteBuckets[index].removeAll(keepingCapacity: true)
        }

        for entry in visibleEntriesScratch {
            let bucketIndex = max(0, min(entry.zIndex, spriteBuckets.count - 1))
            if let renderState = entry.renderState(at: currentTime),
               renderState.frame.intersects(bounds),
               let imageAsset = textCache.imageAsset(for: entry, scale: scale) {
                spriteBuckets[bucketIndex].append(
                    DanmakuSprite(
                        textureKey: imageAsset.key,
                        image: imageAsset.image,
                        frame: renderState.frame,
                        alpha: Float(
                            clampedOpacity(renderState.opacity)
                                * effectiveOpacity(currentSettings.opacity)
                        ),
                        rotation: Float(renderState.rotation)
                    )
                )
            }
        }

        spriteScratch.removeAll(keepingCapacity: true)
        spriteScratch.reserveCapacity(visibleEntriesScratch.count)
        for bucket in spriteBuckets {
            spriteScratch.append(contentsOf: bucket)
        }

        body(prewarmScratch, spriteScratch)
    }

    func draw(in context: CGContext, bounds: CGRect) {
        context.interpolationQuality = .high
        withFrameAssets(in: bounds) { _, sprites in
            for sprite in sprites {
                context.saveGState()
                context.setAlpha(CGFloat(sprite.alpha))
                if abs(sprite.rotation) > 0.0001 {
                    context.translateBy(x: sprite.frame.midX, y: sprite.frame.midY)
                    context.rotate(by: CGFloat(sprite.rotation))
                    let drawRect = CGRect(
                        x: -sprite.frame.width / 2,
                        y: -sprite.frame.height / 2,
                        width: sprite.frame.width,
                        height: sprite.frame.height
                    )
                    context.draw(sprite.image, in: drawRect)
                } else {
                    context.draw(sprite.image, in: sprite.frame)
                }
                context.restoreGState()
            }
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

    private func effectiveOpacity(_ value: Double) -> Double {
        let clamped = clampedOpacity(value)
        return pow(clamped, 1.2)
    }
}

private final class DanmakuPlaybackClock {
    private let driftIgnoreThreshold: TimeInterval = 1.0 / 240.0
    private let driftSnapThreshold: TimeInterval = 0.25
    private let driftCorrectionFactor = 0.18
    private var anchorTime: TimeInterval = 0
    private var anchorHostTime: CFTimeInterval = CACurrentMediaTime()
    private(set) var rate: Double = 1
    private(set) var isActive = false

    var currentTime: TimeInterval {
        currentTime(at: CACurrentMediaTime())
    }

    func sync(time: TimeInterval, isActive: Bool, rate: Double) {
        let normalizedTime = max(time, 0)
        let normalizedRate = max(rate, 0.25)
        let hostTime = CACurrentMediaTime()

        if self.isActive != isActive || abs(self.rate - normalizedRate) >= 0.0001 {
            snap(
                to: normalizedTime,
                hostTime: hostTime,
                isActive: isActive,
                rate: normalizedRate
            )
            return
        }

        guard isActive else {
            if abs(anchorTime - normalizedTime) <= driftIgnoreThreshold {
                return
            }
            snap(
                to: normalizedTime,
                hostTime: hostTime,
                isActive: false,
                rate: normalizedRate
            )
            return
        }

        let predictedTime = currentTime(at: hostTime)
        let drift = normalizedTime - predictedTime
        if abs(drift) <= driftIgnoreThreshold {
            return
        }

        if abs(drift) >= driftSnapThreshold {
            snap(
                to: normalizedTime,
                hostTime: hostTime,
                isActive: true,
                rate: normalizedRate
            )
            return
        }

        anchorTime = max(predictedTime + drift * driftCorrectionFactor, 0)
        anchorHostTime = hostTime
    }

    private func currentTime(at hostTime: CFTimeInterval) -> TimeInterval {
        guard isActive else { return anchorTime }
        let elapsed = hostTime - anchorHostTime
        return max(anchorTime + elapsed * rate, 0)
    }

    private func snap(
        to time: TimeInterval,
        hostTime: CFTimeInterval,
        isActive: Bool,
        rate: Double
    ) {
        anchorTime = time
        anchorHostTime = hostTime
        self.isActive = isActive
        self.rate = rate
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

    func populateVisibleEntries(
        at time: TimeInterval,
        sceneEntries: [DanmakuPreparedComment],
        into output: inout [DanmakuPreparedComment]
    ) {
        guard let scene else {
            output.removeAll(keepingCapacity: true)
            return
        }

        if time + 0.1 < lastTime || time - lastTime > 5 {
            rebuild(for: scene, time: time)
        }

        while nextIndex < scene.entries.count, scene.entries[nextIndex].appearTime <= time {
            activeIndices.append(nextIndex)
            nextIndex += 1
        }

        var writeIndex = 0
        for readIndex in activeIndices.indices {
            let entryIndex = activeIndices[readIndex]
            if scene.entries[entryIndex].endTime > time {
                activeIndices[writeIndex] = entryIndex
                writeIndex += 1
            }
        }
        if writeIndex < activeIndices.count {
            activeIndices.removeSubrange(writeIndex..<activeIndices.count)
        }

        lastTime = time
        output.removeAll(keepingCapacity: true)
        output.reserveCapacity(activeIndices.count)
        for index in activeIndices {
            let entry = sceneEntries[index]
            if entry.endTime > time {
                output.append(entry)
            }
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
    private var segmentLengths: [CGFloat]
    private var cumulativeLengths: [CGFloat]
    private var totalLength: CGFloat

    init(
        points: [CGPoint],
        delay: TimeInterval,
        duration: TimeInterval,
        curve: DanmakuMotionCurve
    ) {
        self.points = points
        self.delay = delay
        self.duration = duration
        self.curve = curve
        self.segmentLengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var cumulativeLengths: [CGFloat] = [0]
        cumulativeLengths.reserveCapacity(segmentLengths.count + 1)
        var runningLength: CGFloat = 0
        for segmentLength in segmentLengths {
            runningLength += segmentLength
            cumulativeLengths.append(runningLength)
        }
        self.cumulativeLengths = cumulativeLengths
        self.totalLength = max(runningLength, 0.0001)
    }

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
        let targetLength = totalLength * curvedProgress

        let segmentIndex = segmentIndex(for: targetLength)
        let segmentLength = segmentLengths[segmentIndex]
        let consumed = cumulativeLengths[segmentIndex]
        let localProgress = segmentLength > 0 ? (targetLength - consumed) / segmentLength : 0
        let start = points[segmentIndex]
        let end = points[segmentIndex + 1]
        return CGPoint(
            x: start.x + (end.x - start.x) * localProgress,
            y: start.y + (end.y - start.y) * localProgress
        )
    }

    private func segmentIndex(for targetLength: CGFloat) -> Int {
        guard segmentLengths.count > 1 else { return 0 }

        var lower = 0
        var upper = segmentLengths.count - 1
        while lower < upper {
            let middle = (lower + upper) / 2
            if cumulativeLengths[middle + 1] < targetLength {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
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

private struct DanmakuRasterImage {
    let key: NSString
    let image: CGImage
}

private struct DanmakuTextMetrics: Sendable {
    var size: CGSize
    var padding: CGFloat
    var drawOrigin: CGPoint
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

        let font = makeFont(size: fontSize, family: fontFamily, weight: .regular) as NSFont
        let outlineRadius = usesStroke ? outlineRadius(for: fontSize) : 0
        let attributed = makeAttributedString(
            text: text,
            font: font,
            color: .white
        )
        let measuredBounds = attributed.boundingRect(
            with: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral
        let padding = ceil(max(outlineRadius + 3, fontSize * 0.16))
        let metrics = DanmakuTextMetrics(
            size: CGSize(
                width: ceil(measuredBounds.width) + padding * 2,
                height: ceil(measuredBounds.height) + padding * 2
            ),
            padding: padding,
            drawOrigin: CGPoint(
                x: padding - measuredBounds.minX,
                y: padding - measuredBounds.minY
            )
        )
        metricsCache.setObject(DanmakuTextMetricsBox(metrics), forKey: key)
        return metrics
    }

    func imageAsset(for comment: DanmakuPreparedComment, scale: CGFloat) -> DanmakuRasterImage? {
        let key = imageCacheKey(for: comment, scale: scale)
        if let cached = imageCache.object(forKey: key) {
            return DanmakuRasterImage(key: key, image: cached.value)
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

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        let font = makeFont(size: comment.fontSize, family: comment.fontFamily, weight: .regular) as NSFont
        let fillAttributed = makeAttributedString(
            text: comment.text,
            font: font,
            color: fillColor(for: comment.colorRGB)
        )
        let outlineAttributed = comment.usesStroke ? makeAttributedString(
            text: comment.text,
            font: font,
            color: NSColor.black.withAlphaComponent(0.4)
        ) : nil
        let drawRect = CGRect(
            origin: metrics.drawOrigin,
            size: CGSize(
                width: max(metrics.size.width - metrics.padding * 2, 1),
                height: max(metrics.size.height - metrics.padding * 2, 1)
            )
        )

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        if let outlineAttributed {
            for offset in outlineOffsets(radius: outlineRadius(for: comment.fontSize)) {
                outlineAttributed.draw(
                    with: drawRect.offsetBy(dx: offset.x, dy: offset.y),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                )
            }
        }
        fillAttributed.draw(
            with: drawRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let image = context.makeImage() else { return nil }
        imageCache.setObject(
            DanmakuImageBox(image),
            forKey: key,
            cost: pixelWidth * pixelHeight * 4
        )
        return DanmakuRasterImage(key: key, image: image)
    }

    func image(for comment: DanmakuPreparedComment, scale: CGFloat) -> CGImage? {
        imageAsset(for: comment, scale: scale)?.image
    }

    private func makeAttributedString(
        text: String,
        font: NSFont,
        color: NSColor
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }

    private func makeFont(
        size: CGFloat,
        family: String?,
        weight: NSFont.Weight = .regular
    ) -> CTFont {
        if let family, family.isEmpty == false {
            let descriptor = NSFontDescriptor(
                fontAttributes: [
                    .family: family,
                    .traits: [NSFontDescriptor.TraitKey.weight: weight]
                ]
            )
            if let custom = NSFont(descriptor: descriptor, size: size) {
                let resolvedFamily = custom.familyName ?? ""
                let postScriptName = custom.fontName
                if postScriptName.localizedCaseInsensitiveContains("LastResort") == false,
                   (
                    resolvedFamily.caseInsensitiveCompare(family) == .orderedSame
                        || resolvedFamily.localizedCaseInsensitiveContains(family)
                        || family.localizedCaseInsensitiveContains(resolvedFamily)
                   ) {
                    return custom as CTFont
                }
            }
        }
        return NSFont.systemFont(ofSize: size, weight: weight) as CTFont
    }

    private func color(for rgb: UInt32) -> CGColor {
        nsColor(for: rgb).cgColor
    }

    private func fillColor(for rgb: UInt32) -> NSColor {
        nsColor(for: rgb).withAlphaComponent(0.92)
    }

    private func nsColor(for rgb: UInt32) -> NSColor {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        return NSColor(red: red, green: green, blue: blue, alpha: 1)
    }

    private func imageCacheKey(for comment: DanmakuPreparedComment, scale: CGFloat) -> NSString {
        NSString(
            string: "i|\(cacheValue(comment.fontSize))|\(cacheValue(scale))|\(comment.fontFamily ?? "<system>")|\(comment.usesStroke ? 1 : 0)|\(comment.colorRGB)|\(comment.text)"
        )
    }

    private func outlineRadius(for fontSize: CGFloat) -> CGFloat {
        min(max(fontSize * 0.045, 0.9), 1.7)
    }

    private func cacheValue(_ value: CGFloat) -> Int {
        Int((value * 100).rounded())
    }

    private func outlineOffsets(radius: CGFloat) -> [CGPoint] {
        guard radius > 0 else { return [] }
        return [
            CGPoint(x: -radius, y: 0),
            CGPoint(x: radius, y: 0),
            CGPoint(x: 0, y: -radius),
            CGPoint(x: 0, y: radius),
        ]
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

#if os(macOS)
private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}
#endif
