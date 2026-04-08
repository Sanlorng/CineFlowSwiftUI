import SwiftUI

#if os(macOS)
import AppKit

public struct SharedSettingsView: View {
    @State private var selectedTab: SharedSettingsTab = .danmaku
    @State private var pendingShortcutCaptureAction: PlayerShortcutAction?
    @AppStorage("player.danmaku.visible") private var isDanmakuVisible = true
    @AppStorage("player.danmaku.debugHUD") private var showsDanmakuPerformanceHUD = false
    @AppStorage("player.danmaku.fontScale") private var danmakuFontScale = 1.5
    @AppStorage("player.danmaku.opacity") private var danmakuOpacity = 0.9
    @AppStorage("player.danmaku.speed") private var danmakuSpeed = 1.0
    @AppStorage("player.shortcut.seekStepMilliseconds") private var shortcutSeekStepMilliseconds = PlayerShortcutDefaults.seekStepMilliseconds
    @AppStorage("player.shortcut.holdToBoostRate") private var shortcutHoldToBoostRate = PlayerShortcutDefaults.holdToBoostRate
    @AppStorage("player.shortcut.volumeStepPercent") private var shortcutVolumeStepPercent = PlayerShortcutDefaults.volumeStepPercent
    @AppStorage("player.shortcut.binding.toggleFullscreen") private var shortcutToggleFullscreenRawValue = PlayerShortcutBindingCodec.encode(PlayerShortcutAction.toggleFullscreen.defaultBindings)
    @AppStorage("player.shortcut.binding.togglePlayPause") private var shortcutTogglePlayPauseRawValue = PlayerShortcutBindingCodec.encode(PlayerShortcutAction.togglePlayPause.defaultBindings)
    @AppStorage("player.shortcut.binding.playPreviousEpisode") private var shortcutPlayPreviousEpisodeRawValue = PlayerShortcutBindingCodec.encode(PlayerShortcutAction.playPreviousEpisode.defaultBindings)
    @AppStorage("player.shortcut.binding.playNextEpisode") private var shortcutPlayNextEpisodeRawValue = PlayerShortcutBindingCodec.encode(PlayerShortcutAction.playNextEpisode.defaultBindings)
    @AppStorage("player.shortcut.binding.seekBackward") private var shortcutSeekBackwardRawValue = PlayerShortcutBindingCodec.encode(PlayerShortcutAction.seekBackward.defaultBindings)
    @AppStorage("player.shortcut.binding.seekForwardOrBoost") private var shortcutSeekForwardOrBoostRawValue = PlayerShortcutBindingCodec.encode(PlayerShortcutAction.seekForwardOrBoost.defaultBindings)
    @AppStorage("player.shortcut.binding.decreasePlaybackRate") private var shortcutDecreasePlaybackRateRawValue = PlayerShortcutBindingCodec.encode(PlayerShortcutAction.decreasePlaybackRate.defaultBindings)
    @AppStorage("player.shortcut.binding.increasePlaybackRate") private var shortcutIncreasePlaybackRateRawValue = PlayerShortcutBindingCodec.encode(PlayerShortcutAction.increasePlaybackRate.defaultBindings)
    @AppStorage("player.shortcut.binding.resetPlaybackRate") private var shortcutResetPlaybackRateRawValue = PlayerShortcutBindingCodec.encode(PlayerShortcutAction.resetPlaybackRate.defaultBindings)
    @AppStorage("player.shortcut.binding.volumeUp") private var shortcutVolumeUpRawValue = PlayerShortcutBindingCodec.encode(PlayerShortcutAction.volumeUp.defaultBindings)
    @AppStorage("player.shortcut.binding.volumeDown") private var shortcutVolumeDownRawValue = PlayerShortcutBindingCodec.encode(PlayerShortcutAction.volumeDown.defaultBindings)

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            Tab("弹幕", systemImage: "text.bubble", value: SharedSettingsTab.danmaku) {
                settingsScrollPage {
                    danmakuSettingsPage
                }
            }

            Tab("快捷键", systemImage: "keyboard", value: SharedSettingsTab.shortcuts) {
                settingsScrollPage {
                    shortcutSettingsPage
                }
            }

            Tab("调试", systemImage: "ladybug", value: SharedSettingsTab.debug) {
                settingsScrollPage {
                    debugSettingsPage
                }
            }
        }
        .tabViewStyle(.automatic)
        .frame(minWidth: 680, idealWidth: 740, minHeight: 620, idealHeight: 700)
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
    private var danmakuSettingsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingsSectionTitle("弹幕默认值")
                    Toggle("显示弹幕", isOn: $isDanmakuVisible)
                        .toggleStyle(.switch)

                    settingsControlRow(
                        title: "字号",
                        value: "\(Int((danmakuFontScale * 100).rounded()))%"
                    ) {
                        Slider(value: $danmakuFontScale, in: 1.0...2.5, step: 0.1)
                    }

                    settingsControlRow(
                        title: "透明度",
                        value: "\(Int((danmakuOpacity * 100).rounded()))%"
                    ) {
                        Slider(value: $danmakuOpacity, in: 0.2...1.0, step: 0.05)
                    }

                    settingsControlRow(
                        title: "速度",
                        value: String(format: "%.1fx", danmakuSpeed)
                    ) {
                        Slider(value: $danmakuSpeed, in: 0.5...2.0, step: 0.1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var shortcutSettingsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        settingsSectionTitle("行为")
                        Spacer(minLength: 0)
                        Button("恢复默认", action: resetShortcutSettingsToDefaults)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    Text("一个功能可以绑定多个按键；同一个按键只会归属最后一次绑定。点击“添加按键”后直接按键，按 Esc 取消。")
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
            }

            settingsGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle("按键绑定")
                    ForEach(PlayerShortcutAction.allCases) { action in
                        settingsShortcutBindingRow(for: action)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var debugSettingsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingsSectionTitle("调试")
                    Toggle("显示弹幕帧率 HUD", isOn: $showsDanmakuPerformanceHUD)
                        .toggleStyle(.switch)
                    Text("默认关闭。开启后会在弹幕层右上角显示实时 FPS 和目标 FPS，用于调试渲染节奏。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
                        : "添加按键"
                    )
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 84)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(pendingShortcutCaptureAction == action ? Color.accentColor : Color.secondary)

                VStack(alignment: .trailing, spacing: 6) {
                    if shortcutBindings(for: action).isEmpty {
                        Text("未绑定")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(shortcutBindings(for: action), id: \.self) { binding in
                            HStack(spacing: 6) {
                                Text(binding.displayTitle)
                                    .font(.caption.monospacedDigit())
                                settingsSmallButton("移除") {
                                    removeShortcutBinding(binding, for: action)
                                    if pendingShortcutCaptureAction == action,
                                       shortcutBindings(for: action).isEmpty {
                                        pendingShortcutCaptureAction = nil
                                    }
                                }
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
        addShortcutBinding(binding, for: pendingShortcutCaptureAction)
        self.pendingShortcutCaptureAction = nil
        return true
    }

    private func hasUnsupportedShortcutModifiers(_ event: NSEvent) -> Bool {
        let allowed: NSEvent.ModifierFlags = [.numericPad, .function]
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return !modifiers.subtracting(allowed).isEmpty
    }

    private func shortcutBindings(for action: PlayerShortcutAction) -> [PlayerShortcutKey] {
        let rawValue = switch action {
        case .toggleFullscreen:
            shortcutToggleFullscreenRawValue
        case .togglePlayPause:
            shortcutTogglePlayPauseRawValue
        case .playPreviousEpisode:
            shortcutPlayPreviousEpisodeRawValue
        case .playNextEpisode:
            shortcutPlayNextEpisodeRawValue
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
        return PlayerShortcutBindingCodec.decode(rawValue)
    }

    private func setShortcutBindings(_ bindings: [PlayerShortcutKey], for action: PlayerShortcutAction) {
        let rawValue = PlayerShortcutBindingCodec.encode(bindings)
        switch action {
        case .toggleFullscreen:
            shortcutToggleFullscreenRawValue = rawValue
        case .togglePlayPause:
            shortcutTogglePlayPauseRawValue = rawValue
        case .playPreviousEpisode:
            shortcutPlayPreviousEpisodeRawValue = rawValue
        case .playNextEpisode:
            shortcutPlayNextEpisodeRawValue = rawValue
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

    private func addShortcutBinding(_ binding: PlayerShortcutKey, for action: PlayerShortcutAction) {
        for otherAction in PlayerShortcutAction.allCases where otherAction != action {
            let filtered = shortcutBindings(for: otherAction).filter { $0 != binding }
            if filtered.count != shortcutBindings(for: otherAction).count {
                setShortcutBindings(filtered, for: otherAction)
            }
        }

        var updated = shortcutBindings(for: action)
        updated.append(binding)
        setShortcutBindings(updated, for: action)
    }

    private func removeShortcutBinding(_ binding: PlayerShortcutKey, for action: PlayerShortcutAction) {
        let updated = shortcutBindings(for: action).filter { $0 != binding }
        setShortcutBindings(updated, for: action)
    }

    private func resetShortcutBindingToDefault(for action: PlayerShortcutAction) {
        setShortcutBindings(action.defaultBindings, for: action)
    }

    private func resetShortcutSettingsToDefaults() {
        for action in PlayerShortcutAction.allCases {
            setShortcutBindings(action.defaultBindings, for: action)
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

private enum SharedSettingsTab: String, CaseIterable, Identifiable {
    case danmaku
    case shortcuts
    case debug

    var id: String { rawValue }
}

private extension SharedSettingsView {
    @ViewBuilder
    func settingsScrollPage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
@ViewBuilder
private func settingsGlassCard<Content: View>(
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        content()
    }
    .padding(16)
    .background {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
            )
    }
}
#else
public struct SharedSettingsView: View {
    public init() {}

    public var body: some View {
        EmptyView()
    }
}
#endif
