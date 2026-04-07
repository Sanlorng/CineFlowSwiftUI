import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

enum PlayerShortcutAction: String, CaseIterable, Identifiable {
    case toggleFullscreen
    case togglePlayPause
    case seekBackward
    case seekForwardOrBoost
    case decreasePlaybackRate
    case increasePlaybackRate
    case resetPlaybackRate
    case volumeUp
    case volumeDown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleFullscreen:
            return "全屏切换"
        case .togglePlayPause:
            return "播放 / 暂停"
        case .seekBackward:
            return "后退"
        case .seekForwardOrBoost:
            return "前进 / 按住倍速"
        case .decreasePlaybackRate:
            return "倍速 -0.5x"
        case .increasePlaybackRate:
            return "倍速 +0.5x"
        case .resetPlaybackRate:
            return "重置到 1.25x"
        case .volumeUp:
            return "音量增加"
        case .volumeDown:
            return "音量减少"
        }
    }

    var detail: String {
        switch self {
        case .toggleFullscreen:
            return "进入或退出全屏"
        case .togglePlayPause:
            return "切换播放状态"
        case .seekBackward:
            return "按设置的步进时间后退"
        case .seekForwardOrBoost:
            return "轻按前进，按住临时加速"
        case .decreasePlaybackRate:
            return "保持当前倍速降低 0.5x"
        case .increasePlaybackRate:
            return "保持当前倍速提高 0.5x"
        case .resetPlaybackRate:
            return "直接设置为 1.25x"
        case .volumeUp:
            return "按设置的步进增加音量"
        case .volumeDown:
            return "按设置的步进降低音量"
        }
    }

    var storageKey: String {
        "player.shortcut.binding.\(rawValue)"
    }

    var defaultKey: PlayerShortcutKey {
        switch self {
        case .toggleFullscreen:
            return .enter
        case .togglePlayPause:
            return .space
        case .seekBackward:
            return .leftArrow
        case .seekForwardOrBoost:
            return .rightArrow
        case .decreasePlaybackRate:
            return .function(1)
        case .increasePlaybackRate:
            return .function(2)
        case .resetPlaybackRate:
            return .function(4)
        case .volumeUp:
            return .upArrow
        case .volumeDown:
            return .downArrow
        }
    }
}

enum PlayerShortcutDefaults {
    static let seekStepMilliseconds = 5000.0
    static let holdToBoostRate = 3.0
    static let holdToBoostActivationDelay: Duration = .milliseconds(260)
    static let playbackRateAdjustmentDelta = 0.5
    static let resetPlaybackRate = 1.25
    static let volumeStepPercent = 5.0
}

struct PlayerShortcutKey: RawRepresentable, Equatable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let enter = Self(rawValue: "special:enter")
    static let space = Self(rawValue: "special:space")
    static let leftArrow = Self(rawValue: "special:leftArrow")
    static let rightArrow = Self(rawValue: "special:rightArrow")
    static let upArrow = Self(rawValue: "special:upArrow")
    static let downArrow = Self(rawValue: "special:downArrow")
    static let escape = Self(rawValue: "special:escape")

    static func function(_ index: Int) -> Self {
        Self(rawValue: "special:f\(index)")
    }

    static func character(_ value: String) -> Self {
        Self(rawValue: "char:\(value.lowercased())")
    }

    var displayTitle: String {
        switch rawValue {
        case Self.enter.rawValue:
            return "Enter"
        case Self.space.rawValue:
            return "Space"
        case Self.leftArrow.rawValue:
            return "←"
        case Self.rightArrow.rawValue:
            return "→"
        case Self.upArrow.rawValue:
            return "↑"
        case Self.downArrow.rawValue:
            return "↓"
        case Self.escape.rawValue:
            return "Esc"
        default:
            if let suffix = rawValue.stripPrefix("special:f") {
                return "F\(suffix)"
            }
            if let character = rawValue.stripPrefix("char:") {
                return character.uppercased()
            }
            return rawValue
        }
    }

    var accessibilityTitle: String {
        switch rawValue {
        case Self.leftArrow.rawValue:
            return "左方向键"
        case Self.rightArrow.rawValue:
            return "右方向键"
        case Self.upArrow.rawValue:
            return "上方向键"
        case Self.downArrow.rawValue:
            return "下方向键"
        default:
            return displayTitle
        }
    }

#if os(macOS)
    static func from(event: NSEvent) -> Self? {
        switch Int(event.keyCode) {
        case PlayerShortcutKeyCode.returnKey, PlayerShortcutKeyCode.keypadEnter:
            return .enter
        case PlayerShortcutKeyCode.space:
            return .space
        case PlayerShortcutKeyCode.leftArrow:
            return .leftArrow
        case PlayerShortcutKeyCode.rightArrow:
            return .rightArrow
        case PlayerShortcutKeyCode.upArrow:
            return .upArrow
        case PlayerShortcutKeyCode.downArrow:
            return .downArrow
        case PlayerShortcutKeyCode.escape:
            return .escape
        case let keyCode where PlayerShortcutKeyCode.functionKeys[keyCode] != nil:
            return .function(PlayerShortcutKeyCode.functionKeys[keyCode]!)
        default:
            guard let characters = event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  characters.count == 1 else {
                return nil
            }
            guard let scalar = characters.unicodeScalars.first,
                  scalar.properties.isAlphabetic
                    || scalar.properties.numericType != nil
                    || PlayerShortcutKeyCode.supportedPrintableScalars.contains(scalar) else {
                return nil
            }
            return .character(String(characters))
        }
    }

    func matches(_ event: NSEvent) -> Bool {
        Self.from(event: event) == self
    }
#endif
}

#if os(macOS)
struct PlayerKeyboardEventMonitor: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    let onKeyUp: (NSEvent) -> Bool
    var canHandleEvent: () -> Bool = { true }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onKeyDown: onKeyDown,
            onKeyUp: onKeyUp,
            canHandleEvent: canHandleEvent
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.onKeyDown = onKeyDown
        context.coordinator.onKeyUp = onKeyUp
        context.coordinator.canHandleEvent = canHandleEvent
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onKeyDown: (NSEvent) -> Bool
        var onKeyUp: (NSEvent) -> Bool
        var canHandleEvent: () -> Bool

        private weak var view: NSView?
        private var localMonitor: Any?

        init(
            onKeyDown: @escaping (NSEvent) -> Bool,
            onKeyUp: @escaping (NSEvent) -> Bool,
            canHandleEvent: @escaping () -> Bool
        ) {
            self.onKeyDown = onKeyDown
            self.onKeyUp = onKeyUp
            self.canHandleEvent = canHandleEvent
        }

        func attach(to view: NSView) {
            self.view = view
            guard localMonitor == nil else { return }

            localMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .keyUp]
            ) { [weak self] event in
                guard let self else { return event }
                guard self.isRelevant(event) else { return event }

                let handled: Bool
                switch event.type {
                case .keyDown:
                    handled = self.onKeyDown(event)
                case .keyUp:
                    handled = self.onKeyUp(event)
                default:
                    handled = false
                }
                return handled ? nil : event
            }
        }

        func teardown() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
            view = nil
        }

        private func isRelevant(_ event: NSEvent) -> Bool {
            guard canHandleEvent(),
                  let view,
                  let window = view.window,
                  event.window === window else {
                return false
            }
            if let firstResponder = window.firstResponder as? NSTextView,
               firstResponder.isEditable {
                return false
            }
            return true
        }
    }
}

private enum PlayerShortcutKeyCode {
    static let returnKey = 36
    static let keypadEnter = 76
    static let space = 49
    static let escape = 53
    static let leftArrow = 123
    static let rightArrow = 124
    static let downArrow = 125
    static let upArrow = 126

    static let functionKeys: [Int: Int] = [
        122: 1,
        120: 2,
        99: 3,
        118: 4,
        96: 5,
        97: 6,
        98: 7,
        100: 8,
        101: 9,
        109: 10,
        103: 11,
        111: 12,
    ]

    static let supportedPrintableScalars: Set<UnicodeScalar> = [
        ".", ",", "/", ";", "'", "[", "]", "\\", "-", "=",
        "`"
    ]
}
#endif

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
