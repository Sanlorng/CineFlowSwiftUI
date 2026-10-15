import SwiftUI

#if os(macOS)
struct PlayerWindowObserver: NSViewRepresentable {
    let onWindowChanged: (NSWindow?) -> Void
    let onFullscreenWillChange: (Bool) -> Void
    let onFullscreenChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onWindowChanged: onWindowChanged,
            onFullscreenWillChange: onFullscreenWillChange,
            onFullscreenChanged: onFullscreenChanged
        )
    }

    func makeNSView(context: Context) -> PlayerWindowObserverView {
        let view = PlayerWindowObserverView(frame: .zero)
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: PlayerWindowObserverView, context: Context) {
        view.coordinator = context.coordinator
        context.coordinator.refresh(for: view.window)
    }

    static func dismantleNSView(_ view: PlayerWindowObserverView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject {
        private let onWindowChanged: (NSWindow?) -> Void
        private let onFullscreenWillChange: (Bool) -> Void
        private let onFullscreenChanged: (Bool) -> Void
        private weak var observedWindow: NSWindow?
        private var notificationTokens: [NSObjectProtocol] = []

        init(
            onWindowChanged: @escaping (NSWindow?) -> Void,
            onFullscreenWillChange: @escaping (Bool) -> Void,
            onFullscreenChanged: @escaping (Bool) -> Void
        ) {
            self.onWindowChanged = onWindowChanged
            self.onFullscreenWillChange = onFullscreenWillChange
            self.onFullscreenChanged = onFullscreenChanged
        }

        @MainActor
        func refresh(for window: NSWindow?) {
            guard observedWindow !== window else { return }
            notificationTokens.forEach(NotificationCenter.default.removeObserver)
            notificationTokens.removeAll()
            observedWindow = window
            reportWindowChange(window)
            reportFullscreenChange(window?.styleMask.contains(.fullScreen) ?? false)

            guard let window else { return }
            notificationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willEnterFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.reportFullscreenWillChange(true)
                    }
                }
            )
            notificationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willExitFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.reportFullscreenWillChange(false)
                    }
                }
            )
            notificationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didEnterFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.reportFullscreenChange(true)
                    }
                }
            )
            notificationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didExitFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.reportFullscreenChange(false)
                    }
                }
            )
        }

        func teardown() {
            notificationTokens.forEach(NotificationCenter.default.removeObserver)
            notificationTokens.removeAll()
            observedWindow = nil
            reportWindowChange(nil)
        }

        private func reportWindowChange(_ window: NSWindow?) {
            Task { @MainActor in
                onWindowChanged(window)
            }
        }

        private func reportFullscreenWillChange(_ fullscreen: Bool) {
            Task { @MainActor in
                onFullscreenWillChange(fullscreen)
            }
        }

        private func reportFullscreenChange(_ fullscreen: Bool) {
            Task { @MainActor in
                onFullscreenChanged(fullscreen)
            }
        }
    }
}

final class PlayerWindowObserverView: NSView {
    weak var coordinator: PlayerWindowObserver.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.refresh(for: window)
    }
}
#endif
