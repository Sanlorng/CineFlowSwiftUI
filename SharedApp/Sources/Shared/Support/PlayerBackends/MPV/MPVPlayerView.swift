import Foundation
import SwiftUI
import QuartzCore

#if canImport(Libmpv) && (os(iOS) || os(macOS) || os(tvOS))
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
    let options: PlayerLoadOptions
    let eventSink: PlayerBackendEventSink
}

extension MPVPlayerView: PlatformViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(eventSink: eventSink)
    }

#if canImport(UIKit)
    func makeUIViewController(context: Context) -> MPVContainerViewController {
        context.coordinator.makeView(source: source, options: options)
    }

    func updateUIViewController(_ uiViewController: MPVContainerViewController, context: Context) {
        context.coordinator.updateView(view: uiViewController, source: source, options: options)
    }

    static func dismantleUIViewController(_ uiViewController: MPVContainerViewController, coordinator: Coordinator) {
        coordinator.reset()
    }
#elseif canImport(AppKit)
    func makeNSViewController(context: Context) -> MPVContainerViewController {
        context.coordinator.makeView(source: source, options: options)
    }

    func updateNSViewController(_ nsViewController: MPVContainerViewController, context: Context) {
        context.coordinator.updateView(view: nsViewController, source: source, options: options)
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

        init(eventSink: PlayerBackendEventSink) {
            self.eventSink = eventSink
        }

        func makeView(source: PlayerSource, options: PlayerLoadOptions) -> MPVContainerViewController {
            let controller = MPVContainerViewController(eventSink: eventSink) { [weak self] newState in
                self?.state = newState
            }
            self.controller = controller
            self.currentSource = source
            self.currentOptions = options
            controller.configure(source: source, options: options)
            return controller
        }

        func updateView(view controller: MPVContainerViewController, source: PlayerSource, options: PlayerLoadOptions) {
            self.controller = controller

            if source != currentSource {
                currentSource = source
                currentOptions = options
                controller.configure(source: source, options: options)
                return
            }

            guard currentOptions != options else { return }
            currentOptions = options
            controller.apply(options: options)
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
    private var currentSource: PlayerSource?
    private var currentOptions: PlayerLoadOptions?
    private var isPaused = false
    private var isBuffering = false

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
        view = PlatformView(frame: .zero)
        view.wantsLayer = true
        view.layer = metalLayer
    }
#endif

    override func viewDidLoad() {
        super.viewDidLoad()

#if canImport(UIKit)
        view.layer.addSublayer(metalLayer)
#endif
        metalLayer.backgroundColor = platformBlackColor
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = currentScreenScale

        initializeIfNeeded()
        if let currentSource, let currentOptions {
            load(source: currentSource, options: currentOptions)
        }
    }

#if canImport(UIKit)
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalLayer.frame = view.bounds
        let scale = view.window?.screen.nativeScale ?? currentScreenScale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
    }
#elseif canImport(AppKit)
    override func viewDidLayout() {
        super.viewDidLayout()
        metalLayer.frame = view.bounds
        let scale = view.window?.screen?.backingScaleFactor ?? currentScreenScale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
    }
#endif

    func configure(source: PlayerSource, options: PlayerLoadOptions) {
        currentSource = source
        currentOptions = options

        guard isViewLoaded else { return }
        initializeIfNeeded()
        load(source: source, options: options)
    }

    func apply(options: PlayerLoadOptions) {
        currentOptions = options
        if options.allowAutoPlay {
            setPause(false)
        }
    }

    func shutdown() {
        NotificationCenter.default.removeObserver(self)
        guard let mpv else { return }
        mpv_set_wakeup_callback(mpv, nil, nil)
        let retainedSelf = Unmanaged.passUnretained(self).toOpaque()
        queue.sync {
            if let mpv = self.mpv {
                mpv_terminate_destroy(mpv)
                self.mpv = nil
            }
        }
        Unmanaged<MPVContainerViewController>.fromOpaque(retainedSelf).release()
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
        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            let controller = Unmanaged<MPVContainerViewController>.fromOpaque(context).takeUnretainedValue()
            controller.readEvents()
        }, retainedSelf)

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
    }

    private func load(source: PlayerSource, options: PlayerLoadOptions) {
        guard let mpv else { return }

        _ = mpv_set_option_string(mpv, "hwdec", options.enableHardwareDecoding ? "videotoolbox" : "no")
        applyHTTPHeaders(source.headers, to: mpv)
        stateChanged(.preparing)

        var args = [source.url.absoluteString, "replace"]
        if !options.allowAutoPlay {
            args.append("pause=yes")
        }
        command("loadfile", args: args)
        if options.allowAutoPlay {
            setPause(false)
        }
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

    private func command(_ command: String, args: [String] = []) {
        guard let mpv else { return }
        var cargs: [UnsafePointer<CChar>?] = ([command] + args).map { UnsafePointer(strdup($0)) } + [nil]
        defer {
            for case let pointer? in cargs {
                free(UnsafeMutablePointer(mutating: pointer))
            }
        }
        _ = mpv_command(mpv, &cargs)
    }

    private func readEvents() {
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
                        self.syncPlaybackState()
                    }
                case MPV_EVENT_END_FILE:
                    DispatchQueue.main.async {
                        self.stateChanged(.completed)
                        self.eventSink.onFinish?(nil)
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
            }
        default:
            break
        }
    }

    private func syncPlaybackState() {
        if isBuffering {
            stateChanged(.buffering)
        } else if isPaused {
            stateChanged(.paused)
        } else {
            stateChanged(.playing)
        }
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
}

private final class MPVMetalLayer: CAMetalLayer {}

private extension MPVContainerViewController {
    var currentScreenScale: CGFloat {
#if canImport(AppKit)
        NSScreen.main?.backingScaleFactor ?? 2
#elseif canImport(UIKit)
        UIScreen.main.nativeScale
#else
        2
#endif
    }

    var platformBlackColor: CGColor {
#if canImport(AppKit)
        NSColor.black.cgColor
#elseif canImport(UIKit)
        UIColor.black.cgColor
#else
        CGColor(gray: 0, alpha: 1)
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
            .fill(Color.black)
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
