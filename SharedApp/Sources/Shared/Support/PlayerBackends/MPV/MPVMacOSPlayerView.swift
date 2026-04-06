import Foundation
import SwiftUI

#if os(macOS) && canImport(Libmpv)
import AppKit
import Libmpv
import OpenGL.GL
import OpenGL.GL3

struct MPVMacOSPlayerView {
    let source: PlayerSource
    let controller: PlayerController
    let options: PlayerLoadOptions
    let eventSink: PlayerBackendEventSink
}

extension MPVMacOSPlayerView: NSViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(eventSink: eventSink)
    }

    func makeNSViewController(context: Context) -> MPVMacOSViewController {
        context.coordinator.makeView(source: source, controller: controller, options: options)
    }

    func updateNSViewController(_ nsViewController: MPVMacOSViewController, context: Context) {
        context.coordinator.updateView(view: nsViewController, source: source, controller: controller, options: options)
    }

    static func dismantleNSViewController(_ nsViewController: MPVMacOSViewController, coordinator: Coordinator) {
        coordinator.reset()
    }
}

extension MPVMacOSPlayerView {
    @MainActor
    final class Coordinator: NSObject, ObservableObject, @unchecked Sendable {
        typealias SurfaceView = MPVMacOSViewController
        let capabilities = PlayerBackendKind.mpv.capabilities
        private let eventSink: PlayerBackendEventSink

        private var controller: MPVMacOSViewController?
        private var currentSource: PlayerSource?
        private var currentOptions: PlayerLoadOptions?
        private var state: PlayerPlaybackState = .idle {
            didSet {
                guard state != oldValue else { return }
                eventSink.onStateChanged?(state)
            }
        }
        private var lastHandledCommandRevision: UInt64 = 0

        init(eventSink: PlayerBackendEventSink) {
            self.eventSink = eventSink
        }

        func makeView(source: PlayerSource, controller: PlayerController, options: PlayerLoadOptions) -> MPVMacOSViewController {
            let surfaceController = MPVMacOSViewController(eventSink: eventSink) { [weak self] state in
                self?.state = state
            }
            self.controller = surfaceController
            self.currentSource = source
            self.currentOptions = options
            surfaceController.configure(source: source, options: options)
            handleCommandIfNeeded(from: controller)
            return surfaceController
        }

        func updateView(view surfaceController: MPVMacOSViewController, source: PlayerSource, controller: PlayerController, options: PlayerLoadOptions) {
            self.controller = surfaceController

            if source != currentSource {
                currentSource = source
                currentOptions = options
                surfaceController.configure(source: source, options: options)
                handleCommandIfNeeded(from: controller)
                return
            }

            if currentOptions != options {
                currentOptions = options
                surfaceController.apply(options: options)
            }
            handleCommandIfNeeded(from: controller)
        }

        func reset() {
            controller?.shutdown()
            controller = nil
            currentSource = nil
            currentOptions = nil
            if state != .idle {
                state = .stopped
            }
        }

        private func handleCommandIfNeeded(from controller: PlayerController) {
            guard controller.commandRevision != lastHandledCommandRevision,
                  let command = controller.latestCommand else {
                return
            }
            lastHandledCommandRevision = controller.commandRevision
            self.controller?.handle(command: command)
        }
    }
}

extension MPVMacOSPlayerView.Coordinator: PlayerBackendRenderer {
    static var backend: PlayerBackendKind { .mpv }
}

@MainActor
final class MPVMacOSViewController: NSViewController {
    private let eventSink: PlayerBackendEventSink
    private let stateChanged: (PlayerPlaybackState) -> Void

    private var glView: MPVMacOSOpenGLView?
    private var currentSource: PlayerSource?
    private var currentOptions: PlayerLoadOptions?

    init(
        eventSink: PlayerBackendEventSink,
        stateChanged: @escaping (PlayerPlaybackState) -> Void
    ) {
        self.eventSink = eventSink
        self.stateChanged = stateChanged
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 720))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let glView = MPVMacOSOpenGLView(frame: view.bounds, eventSink: eventSink, stateChanged: stateChanged)
        glView.autoresizingMask = [.width, .height]
        view.addSubview(glView)
        self.glView = glView
        glView.setupContext()
        glView.setupMpv()

        if let currentSource, let currentOptions {
            glView.load(source: currentSource, options: currentOptions)
        }
    }

    func configure(source: PlayerSource, options: PlayerLoadOptions) {
        currentSource = source
        currentOptions = options
        glView?.load(source: source, options: options)
    }

    func apply(options: PlayerLoadOptions) {
        currentOptions = options
        glView?.apply(options: options)
    }

    func handle(command: PlayerCommand) {
        glView?.handle(command: command)
    }

    func shutdown() {
        glView?.shutdown()
        glView = nil
    }
}

final class MPVMacOSOpenGLView: NSOpenGLView {
    private let eventSink: PlayerBackendEventSink
    private let stateChanged: (PlayerPlaybackState) -> Void

    nonisolated(unsafe) private var mpv: OpaquePointer?
    nonisolated(unsafe) private var mpvGL: OpaquePointer?
    private let queue = DispatchQueue(label: "CineFlow.MPV.OpenGL", qos: .userInteractive)
    private var currentSource: PlayerSource?
    private var currentOptions: PlayerLoadOptions?
    private var lastLoadedSource: PlayerSource?
    private var isPaused = false
    private var isBuffering = false
    private var defaultFBO: GLint = -1
    private var currentDuration: TimeInterval?
    private var currentPlaybackRate: Double = 1

    init(
        frame frameRect: NSRect,
        eventSink: PlayerBackendEventSink,
        stateChanged: @escaping (PlayerPlaybackState) -> Void
    ) {
        self.eventSink = eventSink
        self.stateChanged = stateChanged
        let pixelFormat = Self.defaultPixelFormat()
        super.init(frame: frameRect, pixelFormat: pixelFormat)!
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override class func defaultPixelFormat() -> NSOpenGLPixelFormat {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAColorSize), NSOpenGLPixelFormatAttribute(32),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADepthSize), NSOpenGLPixelFormatAttribute(24),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAStencilSize), NSOpenGLPixelFormatAttribute(8),
            NSOpenGLPixelFormatAttribute(0),
        ]
        return NSOpenGLPixelFormat(attributes: attributes)!
    }

    func setupContext() {
        autoresizingMask = [.width, .height]
        openGLContext?.makeCurrentContext()
    }

    func setupMpv() {
        let handle = mpv_create()
        guard let handle else {
            stateChanged(.error("创建 mpv 上下文失败。"))
            return
        }
        mpv = handle

        _ = mpv_request_log_messages(handle, "warn")
        _ = mpv_set_option_string(handle, "input-media-keys", "yes")
        _ = mpv_set_option_string(handle, "subs-match-os-language", "yes")
        _ = mpv_set_option_string(handle, "subs-fallback", "no")
        _ = mpv_set_option_string(handle, "sub-auto", "no")
        _ = mpv_set_option_string(handle, "sid", "no")
        _ = mpv_set_option_string(handle, "sub-visibility", "no")
        _ = mpv_set_option_string(handle, "hwdec", "auto-safe")
        _ = mpv_set_option_string(handle, "vo", "libmpv")
        _ = mpv_set_option_string(handle, "ytdl", "no")

        stateChanged(.preparing)
        observeProperties(handle: handle)
        checkError(mpv_initialize(handle), fallback: "初始化 mpv 失败。")

        let api = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var initParams = mpv_opengl_init_params(
            get_proc_address: { _, name in
                MPVMacOSOpenGLView.getProcAddress(name)
            },
            get_proc_address_ctx: nil
        )
        withUnsafeMutablePointer(to: &initParams) { initParams in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initParams),
                mpv_render_param(),
            ]
            if mpv_render_context_create(&mpvGL, handle, &params) < 0 {
                stateChanged(.error("初始化 mpv OpenGL 上下文失败。"))
                return
            }
        }

        mpv_render_context_set_update_callback(
            mpvGL,
            mpvMacOSGLUpdate,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        mpv_set_wakeup_callback(handle, mpvMacOSWakeUp, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }

    func load(source: PlayerSource, options: PlayerLoadOptions) {
        currentSource = source
        currentOptions = options
        guard let mpv else { return }

        _ = mpv_set_option_string(mpv, "hwdec", options.enableHardwareDecoding ? "auto-safe" : "no")
        applyHTTPHeaders(source.headers)
        applyAudioTrackSelection(options.selectedAudioTrackID)
        stateChanged(.preparing)

        var args = [source.url.absoluteString, "replace"]
        if !options.allowAutoPlay {
            args.append("pause=yes")
        }
        runCommand("loadfile", args: args)
        lastLoadedSource = source
        if options.allowAutoPlay {
            setPause(false)
        }
    }

    func apply(options: PlayerLoadOptions) {
        currentOptions = options
        applyAudioTrackSelection(options.selectedAudioTrackID)
        applyPlaybackRate(currentPlaybackRate)
        if options.allowAutoPlay {
            setPause(false)
        }
    }

    func handle(command playerCommand: PlayerCommand) {
        switch playerCommand {
        case .togglePlayPause:
            setPause(!isPaused)
        case let .setPaused(paused):
            setPause(paused)
        case let .setRate(rate):
            currentPlaybackRate = rate
            applyPlaybackRate(rate)
        case let .seekBy(delta):
            runCommand("seek", args: [String(delta), "relative"])
        case let .seekTo(time):
            runCommand("seek", args: [String(max(time, 0)), "absolute"])
        }
    }

    func shutdown() {
        guard let mpv else { return }
        mpv_set_wakeup_callback(mpv, nil, nil)
        if let mpvGL {
            mpv_render_context_set_update_callback(mpvGL, nil, nil)
            mpv_render_context_free(mpvGL)
            self.mpvGL = nil
        }
        queue.sync {
            if let mpv = self.mpv {
                mpv_terminate_destroy(mpv)
                self.mpv = nil
            }
        }
        lastLoadedSource = nil
        eventSink.onVideoPresentationSizeChanged?(nil)
    }

    private func observeProperties(handle: OpaquePointer) {
        mpv_observe_property(handle, 0, MPVProperty.pause, MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, MPVProperty.pausedForCache, MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, MPVProperty.timePos, MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, MPVProperty.duration, MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, MPVProperty.aid, MPV_FORMAT_INT64)
        mpv_observe_property(handle, 0, MPVProperty.sid, MPV_FORMAT_INT64)
        mpv_observe_property(handle, 0, MPVProperty.trackList, MPV_FORMAT_NODE)
        mpv_observe_property(handle, 0, MPVProperty.videoParams, MPV_FORMAT_NODE)
    }

    private func applyHTTPHeaders(_ headers: [String: String]) {
        guard let mpv else { return }
        guard !headers.isEmpty else {
            _ = mpv_set_option_string(mpv, "http-header-fields", "")
            return
        }
        if let userAgent = headers["User-Agent"] ?? headers["user-agent"] {
            _ = mpv_set_option_string(mpv, "user-agent", userAgent)
        }
        if let referer = headers["Referer"] ?? headers["referer"] {
            _ = mpv_set_option_string(mpv, "referrer", referer)
        }
        let headerFields = headers
            .filter { key, _ in
                let lowered = key.lowercased()
                return lowered != "user-agent" && lowered != "referer"
            }
            .map { "\($0): \($1)" }
            .joined(separator: ",")
        _ = mpv_set_option_string(mpv, "http-header-fields", headerFields)
    }

    private func applyAudioTrackSelection(_ trackID: String?) {
        guard let mpv else { return }
        if let trackID, !trackID.isEmpty {
            _ = mpv_set_property_string(mpv, MPVProperty.aid, trackID)
        } else {
            _ = mpv_set_property_string(mpv, MPVProperty.aid, "auto")
        }
    }

    private func applyPlaybackRate(_ rate: Double) {
        guard let mpv else { return }
        var value = rate
        _ = mpv_set_property(mpv, MPVProperty.speed, MPV_FORMAT_DOUBLE, &value)
    }

    private func setPause(_ paused: Bool) {
        guard let mpv else { return }
        isPaused = paused
        var flag: Int32 = paused ? 1 : 0
        _ = mpv_set_property(mpv, MPVProperty.pause, MPV_FORMAT_FLAG, &flag)
        syncPlaybackState()
    }

    private func runCommand(_ command: String, args: [String]) {
        guard let mpv else { return }
        var cargs: [UnsafePointer<CChar>?] = ([command] + args).map { UnsafePointer(strdup($0)) } + [nil]
        defer {
            for case let pointer? in cargs {
                free(UnsafeMutablePointer(mutating: pointer))
            }
        }
        _ = mpv_command(mpv, &cargs)
    }

    func readEvents() {
        queue.async { [weak self] in
            guard let self else { return }
            while let mpv = self.mpv {
                guard let event = mpv_wait_event(mpv, 0) else { break }
                if event.pointee.event_id == MPV_EVENT_NONE { break }

                switch event.pointee.event_id {
                case MPV_EVENT_START_FILE:
                    DispatchQueue.main.async { self.stateChanged(.preparing) }
                case MPV_EVENT_FILE_LOADED:
                    DispatchQueue.main.async {
                        self.publishVideoPresentationSize()
                        self.publishTracksSnapshot()
                        self.syncPlaybackState()
                    }
                case MPV_EVENT_END_FILE:
                    DispatchQueue.main.async {
                        self.stateChanged(.completed)
                        self.eventSink.onFinish?(nil)
                    }
                case MPV_EVENT_PROPERTY_CHANGE:
                    self.handlePropertyChange(event)
                case MPV_EVENT_SHUTDOWN:
                    DispatchQueue.main.async {
                        self.shutdown()
                    }
                case MPV_EVENT_LOG_MESSAGE:
                    break
                default:
                    break
                }
            }
        }
    }

    nonisolated private func handlePropertyChange(_ event: UnsafePointer<mpv_event>) {
        let opaque = OpaquePointer(event.pointee.data)
        guard let property = UnsafePointer<mpv_event_property>(opaque)?.pointee else { return }
        let propertyName = String(cString: property.name)

        switch propertyName {
        case MPVProperty.pause:
            let paused = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee ?? false
            DispatchQueue.main.async {
                self.isPaused = paused
                self.syncPlaybackState()
            }
        case MPVProperty.pausedForCache:
            let buffering = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee ?? false
            DispatchQueue.main.async {
                self.isBuffering = buffering
                self.syncPlaybackState()
            }
        case MPVProperty.timePos:
            let time = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee ?? 0
            DispatchQueue.main.async {
                self.eventSink.onPlaybackTimeChanged?(time)
                self.eventSink.onTimelineChanged?(.init(currentTime: time, duration: self.currentDuration))
            }
        case MPVProperty.duration:
            let duration = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee
            DispatchQueue.main.async {
                self.currentDuration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                let current = self.currentPlaybackTime
                self.eventSink.onTimelineChanged?(.init(currentTime: current, duration: self.currentDuration))
            }
        case MPVProperty.videoParams:
            DispatchQueue.main.async {
                self.publishVideoPresentationSize()
            }
        case MPVProperty.trackList, MPVProperty.aid, MPVProperty.sid:
            DispatchQueue.main.async { self.publishTracksSnapshot() }
        default:
            break
        }
    }

    private func publishTracksSnapshot() {
        guard let mpv else { return }
        var node = mpv_node()
        let status = mpv_get_property(mpv, MPVProperty.trackList, MPV_FORMAT_NODE, &node)
        guard status >= 0 else { return }
        defer { mpv_free_node_contents(&node) }
        let tracks = Self.parseTrackList(from: node)
#if DEBUG
        let summary = tracks.map { "\($0.kind.rawValue)#\($0.id):\($0.displayName)[selected=\($0.isSelected)]" }.joined(separator: ", ")
        print("[MPV-GL] track-list => [\(summary)]")
#endif
        eventSink.onTracksChanged?(tracks)
    }

    private func publishVideoPresentationSize() {
        guard let mpv else { return }
        var node = mpv_node()
        let status = mpv_get_property(mpv, MPVProperty.videoParams, MPV_FORMAT_NODE, &node)
        guard status >= 0 else {
            eventSink.onVideoPresentationSizeChanged?(nil)
            return
        }
        defer { mpv_free_node_contents(&node) }
        eventSink.onVideoPresentationSizeChanged?(Self.parseVideoPresentationSize(from: node))
    }

    private func syncPlaybackState() {
        if isBuffering {
            stateChanged(.buffering)
        } else if isPaused {
            stateChanged(.paused)
        } else {
            stateChanged(.playing)
        }
        eventSink.onTimelineChanged?(.init(currentTime: currentPlaybackTime, duration: currentDuration))
    }

    private func checkError(_ status: Int32, fallback: String) {
        guard status < 0 else { return }
        let message = String(cString: mpv_error_string(status))
        stateChanged(.error(message.isEmpty ? fallback : message))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let mpvGL else { return }
        glClearColor(0, 0, 0, 0)
        glClear(UInt32(GL_COLOR_BUFFER_BIT))
        glGetIntegerv(UInt32(GL_FRAMEBUFFER_BINDING), &defaultFBO)

        var dims: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &dims)

        var data = mpv_opengl_fbo(
            fbo: Int32(defaultFBO),
            w: Int32(dims[2]),
            h: Int32(dims[3]),
            internal_format: 0
        )
        var flip: CInt = 1
        withUnsafeMutablePointer(to: &flip) { flip in
            withUnsafeMutablePointer(to: &data) { data in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: data),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flip),
                    mpv_render_param()
                ]
                mpv_render_context_render(mpvGL, &params)
            }
        }
        openGLContext?.flushBuffer()
    }

    private static func getProcAddress(_ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
        guard let name else { return nil }
        let symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
        let identifier = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
        return CFBundleGetFunctionPointerForName(identifier, symbolName)
    }
}

private func mpvMacOSGLUpdate(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let view = Unmanaged<MPVMacOSOpenGLView>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        view.needsDisplay = true
    }
}

private func mpvMacOSWakeUp(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let view = Unmanaged<MPVMacOSOpenGLView>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        view.readEvents()
    }
}

private enum MPVProperty {
    static let pause = "pause"
    static let pausedForCache = "paused-for-cache"
    static let timePos = "time-pos"
    static let duration = "duration"
    static let speed = "speed"
    static let aid = "aid"
    static let sid = "sid"
    static let trackList = "track-list"
    static let videoParams = "video-params"
}

private extension MPVMacOSOpenGLView {
    var currentPlaybackTime: TimeInterval {
        guard let mpv else { return 0 }
        var value = 0.0
        let status = mpv_get_property(mpv, MPVProperty.timePos, MPV_FORMAT_DOUBLE, &value)
        guard status >= 0, value.isFinite else { return 0 }
        return value
    }

    static func parseTrackList(from node: mpv_node) -> [PlayerTrack] {
        guard node.format == MPV_FORMAT_NODE_ARRAY || node.format == MPV_FORMAT_NODE_MAP,
              let list = node.u.list else {
            return []
        }
        let entries = UnsafeBufferPointer(start: list.pointee.values, count: Int(list.pointee.num))
        return entries.compactMap(parseTrackNode(_:))
    }

    static func parseTrackNode(_ node: mpv_node) -> PlayerTrack? {
        guard node.format == MPV_FORMAT_NODE_MAP,
              let map = node.u.list else {
            return nil
        }
        guard let type = stringValue(in: map, key: "type"),
              let kind = PlayerTrack.Kind(mpvtTrackType: type),
              let id = int64Value(in: map, key: "id") else {
            return nil
        }
        let title = stringValue(in: map, key: "title")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = stringValue(in: map, key: "lang")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let codec = stringValue(in: map, key: "codec")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ffIndex = int64Value(in: map, key: "ff-index").flatMap(Int.init)
        let selected = boolValue(in: map, key: "selected") ?? false
        let external = boolValue(in: map, key: "external") ?? false

        let displayName: String
        if let title, !title.isEmpty {
            displayName = title
        } else if let language, !language.isEmpty, let codec, !codec.isEmpty {
            displayName = "\(language) [\(codec)]"
        } else if let language, !language.isEmpty {
            displayName = language
        } else if let codec, !codec.isEmpty {
            displayName = "\(kind.rawValue) [\(codec)]"
        } else {
            displayName = "\(kind.rawValue.capitalized) #\(id)"
        }

        return PlayerTrack(
            id: String(id),
            kind: kind,
            displayName: displayName,
            language: language,
            codec: codec,
            streamIndex: ffIndex,
            isSelected: selected,
            isExternal: external
        )
    }

    static func stringValue(in map: UnsafePointer<mpv_node_list>, key: String) -> String? {
        guard let node = nodeValue(in: map, key: key),
              node.format == MPV_FORMAT_STRING,
              let value = node.u.string else {
            return nil
        }
        return String(cString: value)
    }

    static func int64Value(in map: UnsafePointer<mpv_node_list>, key: String) -> Int64? {
        guard let node = nodeValue(in: map, key: key),
              node.format == MPV_FORMAT_INT64 else {
            return nil
        }
        return node.u.int64
    }

    static func boolValue(in map: UnsafePointer<mpv_node_list>, key: String) -> Bool? {
        guard let node = nodeValue(in: map, key: key),
              node.format == MPV_FORMAT_FLAG else {
            return nil
        }
        return node.u.flag != 0
    }

    static func doubleValue(in map: UnsafePointer<mpv_node_list>, key: String) -> Double? {
        guard let node = nodeValue(in: map, key: key) else {
            return nil
        }
        if node.format == MPV_FORMAT_DOUBLE {
            return node.u.double_
        }
        if node.format == MPV_FORMAT_INT64 {
            return Double(node.u.int64)
        }
        return nil
    }

    static func nodeValue(in map: UnsafePointer<mpv_node_list>, key: String) -> mpv_node? {
        guard let keys = map.pointee.keys, let values = map.pointee.values else {
            return nil
        }
        let count = Int(map.pointee.num)
        for index in 0..<count {
            let currentKey = String(cString: keys[index]!)
            if currentKey == key {
                return values[index]
            }
        }
        return nil
    }

    static func parseVideoPresentationSize(from node: mpv_node) -> CGSize? {
        guard node.format == MPV_FORMAT_NODE_MAP,
              let map = node.u.list,
              let width = doubleValue(in: map, key: "dw") ?? doubleValue(in: map, key: "w"),
              let height = doubleValue(in: map, key: "dh") ?? doubleValue(in: map, key: "h"),
              width.isFinite,
              height.isFinite,
              width > 0,
              height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}

private extension PlayerTrack.Kind {
    init?(mpvtTrackType: String) {
        switch mpvtTrackType {
        case "video":
            self = .video
        case "audio":
            self = .audio
        case "sub":
            self = .subtitle
        default:
            return nil
        }
    }
}
#endif
