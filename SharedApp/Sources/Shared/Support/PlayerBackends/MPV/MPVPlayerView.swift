import Foundation
import SwiftUI
import QuartzCore

#if canImport(Libmpv) && (os(iOS) || os(tvOS))
import Libmpv

#if canImport(UIKit)
import UIKit
typealias PlatformViewControllerRepresentable = UIViewControllerRepresentable
typealias PlatformViewController = UIViewController
typealias PlatformView = UIView
#elseif canImport(AppKit)
import AppKit
typealias PlatformViewControllerRepresentable = NSViewControllerRepresentable
typealias PlatformViewController = NSViewController
typealias PlatformView = NSView
#endif

struct MPVPlayerView {
    let source: PlayerSource
    let controller: PlayerController
    let options: PlayerLoadOptions
    let eventSink: PlayerBackendEventSink
}

extension MPVPlayerView: PlatformViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(eventSink: eventSink)
    }

#if canImport(UIKit)
    func makeUIViewController(context: Context) -> MPVContainerViewController {
        context.coordinator.makeView(source: source, controller: controller, options: options)
    }

    func updateUIViewController(_ uiViewController: MPVContainerViewController, context: Context) {
        context.coordinator.updateView(view: uiViewController, source: source, controller: controller, options: options)
    }

    static func dismantleUIViewController(_ uiViewController: MPVContainerViewController, coordinator: Coordinator) {
        coordinator.reset()
    }
#elseif canImport(AppKit)
    func makeNSViewController(context: Context) -> MPVContainerViewController {
        context.coordinator.makeView(source: source, controller: controller, options: options)
    }

    func updateNSViewController(_ nsViewController: MPVContainerViewController, context: Context) {
        context.coordinator.updateView(view: nsViewController, source: source, controller: controller, options: options)
    }

    static func dismantleNSViewController(_ nsViewController: MPVContainerViewController, coordinator: Coordinator) {
        coordinator.reset()
    }
#endif
}

extension MPVPlayerView {
    @MainActor
    final class Coordinator: NSObject, ObservableObject, @unchecked Sendable {
        typealias SurfaceView = MPVContainerViewController
        let capabilities = PlayerBackendKind.mpv.capabilities
        private let eventSink: PlayerBackendEventSink

        private var controller: MPVContainerViewController?
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

        func makeView(source: PlayerSource, controller: PlayerController, options: PlayerLoadOptions) -> MPVContainerViewController {
            let surfaceController = MPVContainerViewController(eventSink: eventSink) { [weak self] newState in
                self?.state = newState
            }
            self.controller = surfaceController
            self.currentSource = source
            self.currentOptions = options
            surfaceController.configure(source: source, options: options)
            handleCommandIfNeeded(from: controller)
            return surfaceController
        }

        func updateView(view surfaceController: MPVContainerViewController, source: PlayerSource, controller: PlayerController, options: PlayerLoadOptions) {
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

extension MPVPlayerView.Coordinator: PlayerBackendRenderer {
    static var backend: PlayerBackendKind { .mpv }
}

@MainActor
final class MPVContainerViewController: PlatformViewController {
    private let eventSink: PlayerBackendEventSink
    private let stateChanged: (PlayerPlaybackState) -> Void

    private let metalLayer = MPVMetalLayer()
    private let queue = DispatchQueue(label: "CineFlow.MPV", qos: .userInitiated)

    nonisolated(unsafe) private var mpv: OpaquePointer?
    nonisolated(unsafe) private var wakeupContext: UnsafeMutableRawPointer?
    private var currentSource: PlayerSource?
    private var currentOptions: PlayerLoadOptions?
    private var lastLoadedSource: PlayerSource?
    private var isPaused = false
    private var isBuffering = false
    private var currentDuration: TimeInterval?

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

#if canImport(AppKit)
    override func loadView() {
        view = PlatformView(frame: defaultSurfaceFrame)
        view.wantsLayer = true
        view.layer = metalLayer
        view.layer?.backgroundColor = platformClearColor
    }
#endif

    override func viewDidLoad() {
        super.viewDidLoad()

#if canImport(UIKit)
        view.layer.addSublayer(metalLayer)
#endif
        metalLayer.backgroundColor = platformClearColor
        metalLayer.framebufferOnly = true
        updateMetalLayerGeometry()
    }

#if canImport(UIKit)
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateMetalLayerGeometry()
        startPlaybackIfReady()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        shutdown()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateMetalLayerGeometry()
        startPlaybackIfReady()
    }
#elseif canImport(AppKit)
    override func viewDidAppear() {
        super.viewDidAppear()
        updateMetalLayerGeometry()
        startPlaybackIfReady()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        shutdown()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateMetalLayerGeometry()
        startPlaybackIfReady()
    }
#endif

    func configure(source: PlayerSource, options: PlayerLoadOptions) {
        currentSource = source
        currentOptions = options

        guard isViewLoaded else { return }
        startPlaybackIfReady()
    }

    func apply(options: PlayerLoadOptions) {
        currentOptions = options
        startPlaybackIfReady()
        applyAudioTrackSelection(options.selectedAudioTrackID)
        applyEmbeddedSubtitleTrackSelection(options.selectedEmbeddedSubtitleTrackID)
        applySubtitleSettings(options)
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
        case let .seekBy(delta):
            runCommand("seek", args: [String(delta), "relative"])
        case let .seekTo(time):
            runCommand("seek", args: [String(max(time, 0)), "absolute"])
        }
    }

    func shutdown() {
        NotificationCenter.default.removeObserver(self)
        guard let mpv else { return }
        mpv_set_wakeup_callback(mpv, nil, nil)
        queue.sync {
            if let mpv = self.mpv {
                mpv_terminate_destroy(mpv)
                self.mpv = nil
            }
        }
        lastLoadedSource = nil
        if let wakeupContext {
            Unmanaged<MPVContainerViewController>.fromOpaque(wakeupContext).release()
            self.wakeupContext = nil
        }
        eventSink.onVideoPresentationSizeChanged?(nil)
    }

    private func startPlaybackIfReady() {
        guard let currentSource, let currentOptions else { return }
        guard isRenderSurfaceReady else {
#if DEBUG
            print("[MPV] Skip start because render surface is not ready yet. window=\(String(describing: view.window)) bounds=\(view.bounds) drawable=\(metalLayer.drawableSize)")
#endif
            return
        }
        initializeIfNeeded()
        if lastLoadedSource != currentSource {
            load(source: currentSource, options: currentOptions)
            lastLoadedSource = currentSource
        }
    }

    private func initializeIfNeeded() {
        guard mpv == nil else { return }

        let handle = mpv_create()
        guard let handle else {
            stateChanged(.error("创建 mpv 上下文失败。"))
            return
        }

        mpv = handle
        stateChanged(.preparing)
        configureBaseOptions(handle: handle)
        observeProperties(handle: handle)
        checkError(mpv_initialize(handle), fallback: "初始化 mpv 失败。")

        let retainedSelf = Unmanaged.passRetained(self).toOpaque()
        wakeupContext = retainedSelf
        mpv_set_wakeup_callback(handle, mpvWakeupCallback, retainedSelf)

        setupLifecycleNotifications()
    }

    private func configureBaseOptions(handle: OpaquePointer) {
#if DEBUG
        _ = mpv_request_log_messages(handle, "debug")
#else
        _ = mpv_request_log_messages(handle, "no")
#endif
#if os(macOS)
        _ = mpv_set_option_string(handle, "input-media-keys", "yes")
        _ = mpv_set_option_string(handle, "ytdl", "no")
#endif
        let rawHandle = Unmanaged.passUnretained(metalLayer).toOpaque()
        var wid = Int64(UInt(bitPattern: rawHandle))
        _ = mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid)
        _ = mpv_set_option_string(handle, "subs-match-os-language", "yes")
        _ = mpv_set_option_string(handle, "subs-fallback", "no")
        _ = mpv_set_option_string(handle, "sub-auto", "no")
        _ = mpv_set_option_string(handle, "sid", "no")
        _ = mpv_set_option_string(handle, "sub-visibility", "no")
        _ = mpv_set_option_string(handle, "vo", "gpu-next")
        _ = mpv_set_option_string(handle, "gpu-api", "vulkan")
        _ = mpv_set_option_string(handle, "gpu-context", "moltenvk")
        _ = mpv_set_option_string(handle, "video-rotate", "no")
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

    private func load(source: PlayerSource, options: PlayerLoadOptions) {
        guard let mpv else { return }

        prepareForSourceChange()
        _ = mpv_set_option_string(mpv, "hwdec", options.enableHardwareDecoding ? "videotoolbox" : "no")
        applyHTTPHeaders(source.headers, to: mpv)
        applyAudioTrackSelection(options.selectedAudioTrackID)
        applyEmbeddedSubtitleTrackSelection(options.selectedEmbeddedSubtitleTrackID)
        applySubtitleSettings(options)
        stateChanged(.preparing)

        if !options.allowAutoPlay {
            setPause(true)
        }
        command("loadfile", args: [source.url.absoluteString, "replace"])
        if options.allowAutoPlay {
            setPause(false)
        }
    }

    private func prepareForSourceChange() {
        currentDuration = nil
        eventSink.onVideoPresentationSizeChanged?(nil)
        isBuffering = false
        isPaused = true
    }

    private func applyHTTPHeaders(_ headers: [String: String], to mpv: OpaquePointer) {
        guard headers.isEmpty == false else {
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

    private func setPause(_ paused: Bool) {
        guard let mpv else { return }
        isPaused = paused
        var flag: Int32 = paused ? 1 : 0
        _ = mpv_set_property(mpv, MPVProperty.pause, MPV_FORMAT_FLAG, &flag)
        syncPlaybackState()
    }

    private func applyAudioTrackSelection(_ trackID: String?) {
        guard let mpv else { return }
        if let trackID, !trackID.isEmpty {
            _ = mpv_set_property_string(mpv, MPVProperty.aid, trackID)
        } else {
            _ = mpv_set_property_string(mpv, MPVProperty.aid, "auto")
        }
    }

    private func applyEmbeddedSubtitleTrackSelection(_ trackID: String?) {
        guard let mpv else { return }
        if let trackID, !trackID.isEmpty {
            _ = mpv_set_property_string(mpv, MPVProperty.sid, trackID)
            _ = mpv_set_property_string(mpv, "sub-visibility", "yes")
        } else {
            _ = mpv_set_property_string(mpv, MPVProperty.sid, "no")
            _ = mpv_set_property_string(mpv, "sub-visibility", "no")
        }
    }

    private func applySubtitleSettings(_ options: PlayerLoadOptions) {
        guard let mpv else { return }
        var subtitleDelay = options.subtitleTimeOffset
        _ = mpv_set_property(mpv, MPVProperty.subDelay, MPV_FORMAT_DOUBLE, &subtitleDelay)
        var subtitleFontSize = max(options.subtitleFontSize, 12)
        _ = mpv_set_property(mpv, MPVProperty.subFontSize, MPV_FORMAT_DOUBLE, &subtitleFontSize)
        _ = mpv_set_property_string(mpv, MPVProperty.subFont, options.subtitleFontFamily ?? "")
    }

    private func runCommand(_ command: String, args: [String] = []) {
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
                    DispatchQueue.main.async {
                        self.stateChanged(.preparing)
                    }
                case MPV_EVENT_FILE_LOADED:
                    DispatchQueue.main.async {
                        self.publishVideoPresentationSize()
                        self.publishTracksSnapshot()
                        self.syncPlaybackState()
                    }
                case MPV_EVENT_END_FILE:
                    let endFile = UnsafePointer<mpv_event_end_file>(OpaquePointer(event.pointee.data))
                    let shouldHandleCompletion = endFile?.pointee.reason == MPV_END_FILE_REASON_EOF
#if DEBUG
                    if let endFile {
                        print("[MPV] end-file reason=\(endFile.pointee.reason) playlistEntryID=\(endFile.pointee.playlist_entry_id)")
                    }
#endif
                    if shouldHandleCompletion {
                        DispatchQueue.main.async {
                            self.stateChanged(.completed)
                            self.eventSink.onFinish?(nil)
                        }
                    }
                case MPV_EVENT_PROPERTY_CHANGE:
                    self.handlePropertyChange(event)
                case MPV_EVENT_LOG_MESSAGE:
#if DEBUG
                    let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data))
                    if let msg {
                        print("[mpv][\(String(cString: msg.pointee.prefix))] \(String(cString: msg.pointee.text))", terminator: "")
                    }
#endif
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
                self.eventSink.onTimelineChanged?(.init(currentTime: self.currentPlaybackTime, duration: self.currentDuration))
            }
        case MPVProperty.videoParams:
            DispatchQueue.main.async {
                self.publishVideoPresentationSize()
            }
        case MPVProperty.trackList, MPVProperty.aid, MPVProperty.sid:
            DispatchQueue.main.async {
                self.publishTracksSnapshot()
            }
        default:
            break
        }
    }

    private func publishTracksSnapshot() {
        guard let mpv else { return }
        var node = mpv_node()
        let status = mpv_get_property(mpv, MPVProperty.trackList, MPV_FORMAT_NODE, &node)
        guard status >= 0 else { return }
        defer {
            mpv_free_node_contents(&node)
        }
        let tracks = Self.parseTrackList(from: node)
#if DEBUG
        let summary = tracks
            .map { "\($0.kind.rawValue)#\($0.id):\($0.displayName)[selected=\($0.isSelected)]" }
            .joined(separator: ", ")
        print("[MPV] track-list => [\(summary)]")
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
        defer {
            mpv_free_node_contents(&node)
        }
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

    private func setupLifecycleNotifications() {
#if canImport(UIKit)
        NotificationCenter.default.addObserver(self, selector: #selector(enterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
#endif
    }

#if canImport(UIKit)
    @objc private func enterBackground() {
        setPause(true)
        guard let mpv else { return }
        _ = mpv_set_option_string(mpv, "vid", "no")
    }

    @objc private func enterForeground() {
        guard let mpv else { return }
        _ = mpv_set_option_string(mpv, "vid", "auto")
        if currentOptions?.allowAutoPlay == true {
            setPause(false)
        }
    }
#endif

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

private enum MPVProperty {
    static let pause = "pause"
    static let pausedForCache = "paused-for-cache"
    static let timePos = "time-pos"
    static let duration = "duration"
    static let aid = "aid"
    static let sid = "sid"
    static let subDelay = "sub-delay"
    static let subFontSize = "sub-font-size"
    static let subFont = "sub-font"
    static let trackList = "track-list"
    static let videoParams = "video-params"
}

private final class MPVMetalLayer: CAMetalLayer {}

private func mpvWakeupCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let controller = Unmanaged<MPVContainerViewController>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in
        controller.readEvents()
    }
}

private extension MPVContainerViewController {
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
        guard let node = nodeValue(in: map, key: key), node.format == MPV_FORMAT_STRING, let value = node.u.string else {
            return nil
        }
        return String(cString: value)
    }

    static func int64Value(in map: UnsafePointer<mpv_node_list>, key: String) -> Int64? {
        guard let node = nodeValue(in: map, key: key), node.format == MPV_FORMAT_INT64 else {
            return nil
        }
        return node.u.int64
    }

    static func boolValue(in map: UnsafePointer<mpv_node_list>, key: String) -> Bool? {
        guard let node = nodeValue(in: map, key: key), node.format == MPV_FORMAT_FLAG else {
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
        guard let keys = map.pointee.keys,
              let values = map.pointee.values else {
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

private extension MPVContainerViewController {
    var isRenderSurfaceReady: Bool {
        view.window != nil &&
        metalLayer.drawableSize.width > 1 &&
        metalLayer.drawableSize.height > 1
    }

    func updateMetalLayerGeometry() {
        let bounds = view.bounds.isEmpty ? defaultSurfaceFrame : view.bounds
        metalLayer.frame = bounds
        let scale = currentScreenScale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: max(bounds.width * scale, 1),
            height: max(bounds.height * scale, 1)
        )
    }

    var defaultSurfaceFrame: CGRect {
#if canImport(AppKit)
        NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
#elseif canImport(UIKit)
        UIScreen.main.bounds
#else
        CGRect(x: 0, y: 0, width: 1280, height: 720)
#endif
    }

    var currentScreenScale: CGFloat {
#if canImport(AppKit)
        view.window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
#elseif canImport(UIKit)
        view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
#else
        2
#endif
    }

    var platformClearColor: CGColor {
#if canImport(AppKit)
        NSColor.clear.cgColor
#elseif canImport(UIKit)
        UIColor.clear.cgColor
#else
        CGColor(gray: 0, alpha: 0)
#endif
    }
}
#else
import SwiftUI

struct MPVPlayerView: View {
    let source: PlayerSource
    let options: PlayerLoadOptions
    let eventSink: PlayerBackendEventSink

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "play.square.stack")
                        .font(.system(size: 28, weight: .medium))
                    Text("mpv 后端未在当前构建中启用")
                        .font(.headline)
                }
                .foregroundStyle(.white.opacity(0.9))
            }
            .onAppear {
                eventSink.onStateChanged?(.error("mpv 后端未在当前构建中启用。"))
            }
    }
}
#endif
