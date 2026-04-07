import SwiftUI

#if os(macOS)
import AppKit

public struct SharedSettingsView: View {
    @State private var pendingShortcutCaptureAction: PlayerShortcutAction?
    @AppStorage("player.shortcut.seekStepMilliseconds") private var shortcutSeekStepMilliseconds = PlayerShortcutDefaults.seekStepMilliseconds
    @AppStorage("player.shortcut.holdToBoostRate") private var shortcutHoldToBoostRate = PlayerShortcutDefaults.holdToBoostRate
    @AppStorage("player.shortcut.volumeStepPercent") private var shortcutVolumeStepPercent = PlayerShortcutDefaults.volumeStepPercent
    @AppStorage("player.shortcut.binding.toggleFullscreen") private var shortcutToggleFullscreenRawValue = PlayerShortcutAction.toggleFullscreen.defaultKey.rawValue
    @AppStorage("player.shortcut.binding.togglePlayPause") private var shortcutTogglePlayPauseRawValue = PlayerShortcutAction.togglePlayPause.defaultKey.rawValue
    @AppStorage("player.shortcut.binding.seekBackward") private var shortcutSeekBackwardRawValue = PlayerShortcutAction.seekBackward.defaultKey.rawValue
    @AppStorage("player.shortcut.binding.seekForwardOrBoost") private var shortcutSeekForwardOrBoostRawValue = PlayerShortcutAction.seekForwardOrBoost.defaultKey.rawValue
    @AppStorage("player.shortcut.binding.decreasePlaybackRate") private var shortcutDecreasePlaybackRateRawValue = PlayerShortcutAction.decreasePlaybackRate.defaultKey.rawValue
    @AppStorage("player.shortcut.binding.increasePlaybackRate") private var shortcutIncreasePlaybackRateRawValue = PlayerShortcutAction.increasePlaybackRate.defaultKey.rawValue
    @AppStorage("player.shortcut.binding.resetPlaybackRate") private var shortcutResetPlaybackRateRawValue = PlayerShortcutAction.resetPlaybackRate.defaultKey.rawValue
    @AppStorage("player.shortcut.binding.volumeUp") private var shortcutVolumeUpRawValue = PlayerShortcutAction.volumeUp.defaultKey.rawValue
    @AppStorage("player.shortcut.binding.volumeDown") private var shortcutVolumeDownRawValue = PlayerShortcutAction.volumeDown.defaultKey.rawValue

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("播放器快捷键")
                        .font(.title2.weight(.semibold))
                    Text("这里的设置会直接作用到播放器页面。修改绑定后立即生效。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            settingsSectionTitle("行为")
                            Spacer(minLength: 0)
                            Button("恢复默认", action: resetShortcutSettingsToDefaults)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }

                        Text("同一个按键只保留最后一次绑定。点击右侧当前按键后直接按键，按 Esc 取消。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let pendingShortcutCaptureAction {
                            Text("正在录制“\(pendingShortcutCaptureAction.title)”")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                )
                        }

                        settingsControlRow(
                            title: "前进 / 后退步进",
                            value: settingsFormattedShortcutMilliseconds(shortcutSeekStepMilliseconds)
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Slider(value: $shortcutSeekStepMilliseconds, in: 1000...30000, step: 500)
                                HStack(spacing: 8) {
                                    settingsSmallButton("-500 ms") {
                                        shortcutSeekStepMilliseconds = max(shortcutSeekStepMilliseconds - 500, 1000)
                                    }
                                    settingsSmallButton("重置") {
                                        shortcutSeekStepMilliseconds = PlayerShortcutDefaults.seekStepMilliseconds
                                    }
                                    settingsSmallButton("+500 ms") {
                                        shortcutSeekStepMilliseconds = min(shortcutSeekStepMilliseconds + 500, 30000)
                                    }
                                }
                            }
                        }

                        settingsControlRow(
                            title: "按住右键倍速",
                            value: settingsPlaybackRateTitle(shortcutHoldToBoostRate)
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Slider(value: $shortcutHoldToBoostRate, in: 1.25...6.0, step: 0.25)
                                HStack(spacing: 8) {
                                    settingsSmallButton("-0.25x") {
                                        shortcutHoldToBoostRate = max(shortcutHoldToBoostRate - 0.25, 1.25)
                                    }
                                    settingsSmallButton("重置") {
                                        shortcutHoldToBoostRate = PlayerShortcutDefaults.holdToBoostRate
                                    }
                                    settingsSmallButton("+0.25x") {
                                        shortcutHoldToBoostRate = min(shortcutHoldToBoostRate + 0.25, 6)
                                    }
                                }
                            }
                        }

                        settingsControlRow(
                            title: "音量步进",
                            value: settingsFormattedVolumeStepPercent(shortcutVolumeStepPercent)
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Slider(value: $shortcutVolumeStepPercent, in: 1...20, step: 1)
                                HStack(spacing: 8) {
                                    settingsSmallButton("-1%") {
                                        shortcutVolumeStepPercent = max(shortcutVolumeStepPercent - 1, 1)
                                    }
                                    settingsSmallButton("重置") {
                                        shortcutVolumeStepPercent = PlayerShortcutDefaults.volumeStepPercent
                                    }
                                    settingsSmallButton("+1%") {
                                        shortcutVolumeStepPercent = min(shortcutVolumeStepPercent + 1, 20)
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        settingsSectionTitle("按键绑定")
                        ForEach(PlayerShortcutAction.allCases) { action in
                            settingsShortcutBindingRow(for: action)
                        }
                    }
                    .padding(14)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 620, idealHeight: 680)
        .background {
            PlayerKeyboardEventMonitor(
                onKeyDown: handleShortcutCaptureKeyDown(_:),
                onKeyUp: { _ in false },
                canHandleEvent: { pendingShortcutCaptureAction != nil }
            )
            .frame(width: 0, height: 0)
        }
    }

    @ViewBuilder
    private func settingsShortcutBindingRow(for action: PlayerShortcutAction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.subheadline.weight(.semibold))
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    pendingShortcutCaptureAction = pendingShortcutCaptureAction == action ? nil : action
                } label: {
                    Text(
                        pendingShortcutCaptureAction == action
                        ? "按键中…"
                        : (shortcutBinding(for: action)?.displayTitle ?? "未绑定")
                    )
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 84)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(pendingShortcutCaptureAction == action ? Color.accentColor : Color.secondary)

                HStack(spacing: 6) {
                    if shortcutBinding(for: action) != nil {
                        settingsSmallButton("清空") {
                            setShortcutBinding(nil, for: action)
                            if pendingShortcutCaptureAction == action {
                                pendingShortcutCaptureAction = nil
                            }
                        }
                    }
                    settingsSmallButton("默认") {
                        resetShortcutBindingToDefault(for: action)
                        if pendingShortcutCaptureAction == action {
                            pendingShortcutCaptureAction = nil
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func handleShortcutCaptureKeyDown(_ event: NSEvent) -> Bool {
        guard let pendingShortcutCaptureAction else { return false }
        guard !hasUnsupportedShortcutModifiers(event) else { return true }
        if PlayerShortcutKey.escape.matches(event) {
            self.pendingShortcutCaptureAction = nil
            return true
        }
        guard let binding = PlayerShortcutKey.from(event: event) else {
            return true
        }
        setShortcutBinding(binding, for: pendingShortcutCaptureAction)
        self.pendingShortcutCaptureAction = nil
        return true
    }

    private func hasUnsupportedShortcutModifiers(_ event: NSEvent) -> Bool {
        let allowed: NSEvent.ModifierFlags = [.numericPad, .function]
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return !modifiers.subtracting(allowed).isEmpty
    }

    private func shortcutBinding(for action: PlayerShortcutAction) -> PlayerShortcutKey? {
        let rawValue = switch action {
        case .toggleFullscreen:
            shortcutToggleFullscreenRawValue
        case .togglePlayPause:
            shortcutTogglePlayPauseRawValue
        case .seekBackward:
            shortcutSeekBackwardRawValue
        case .seekForwardOrBoost:
            shortcutSeekForwardOrBoostRawValue
        case .decreasePlaybackRate:
            shortcutDecreasePlaybackRateRawValue
        case .increasePlaybackRate:
            shortcutIncreasePlaybackRateRawValue
        case .resetPlaybackRate:
            shortcutResetPlaybackRateRawValue
        case .volumeUp:
            shortcutVolumeUpRawValue
        case .volumeDown:
            shortcutVolumeDownRawValue
        }
        guard !rawValue.isEmpty else { return nil }
        return PlayerShortcutKey(rawValue: rawValue)
    }

    private func setShortcutBinding(_ binding: PlayerShortcutKey?, for action: PlayerShortcutAction) {
        if let binding {
            for otherAction in PlayerShortcutAction.allCases where otherAction != action {
                if shortcutBinding(for: otherAction) == binding {
                    setShortcutBinding(nil, for: otherAction)
                }
            }
        }

        let rawValue = binding?.rawValue ?? ""
        switch action {
        case .toggleFullscreen:
            shortcutToggleFullscreenRawValue = rawValue
        case .togglePlayPause:
            shortcutTogglePlayPauseRawValue = rawValue
        case .seekBackward:
            shortcutSeekBackwardRawValue = rawValue
        case .seekForwardOrBoost:
            shortcutSeekForwardOrBoostRawValue = rawValue
        case .decreasePlaybackRate:
            shortcutDecreasePlaybackRateRawValue = rawValue
        case .increasePlaybackRate:
            shortcutIncreasePlaybackRateRawValue = rawValue
        case .resetPlaybackRate:
            shortcutResetPlaybackRateRawValue = rawValue
        case .volumeUp:
            shortcutVolumeUpRawValue = rawValue
        case .volumeDown:
            shortcutVolumeDownRawValue = rawValue
        }
    }

    private func resetShortcutBindingToDefault(for action: PlayerShortcutAction) {
        setShortcutBinding(action.defaultKey, for: action)
    }

    private func resetShortcutSettingsToDefaults() {
        for action in PlayerShortcutAction.allCases {
            setShortcutBinding(action.defaultKey, for: action)
        }
        shortcutSeekStepMilliseconds = PlayerShortcutDefaults.seekStepMilliseconds
        shortcutHoldToBoostRate = PlayerShortcutDefaults.holdToBoostRate
        shortcutVolumeStepPercent = PlayerShortcutDefaults.volumeStepPercent
        pendingShortcutCaptureAction = nil
    }
}

@MainActor
@ViewBuilder
private func settingsSectionTitle(_ title: String) -> some View {
    Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .tracking(0.8)
}

@MainActor
@ViewBuilder
private func settingsControlRow<Content: View>(
    title: String,
    value: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        content()
    }
}

@MainActor
@ViewBuilder
private func settingsSmallButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .buttonStyle(.bordered)
        .controlSize(.small)
}

private func settingsFormattedShortcutMilliseconds(_ milliseconds: Double) -> String {
    "\(Int(milliseconds.rounded())) ms"
}

private func settingsFormattedVolumeStepPercent(_ percent: Double) -> String {
    "\(Int(percent.rounded()))%"
}

private func settingsPlaybackRateTitle(_ rate: Double) -> String {
    if abs(rate.rounded() - rate) < 0.001 {
        return "\(Int(rate.rounded()))x"
    }
    return String(format: "%.2fx", rate)
}
#else
public struct SharedSettingsView: View {
    public init() {}

    public var body: some View {
        EmptyView()
    }
}
#endif
