import SwiftUI
import UniformTypeIdentifiers
import ComposableArchitecture
import RemoteMediaLibrary
import SubtitleRendererCore
import SubtitleRendererLibass

struct PlayerContentView: View {
    let store: StoreOf<PlayerPresenter>?
    
    init(store: StoreOf<PlayerPresenter>? = nil) {
        self.store = store
    }
    
    var body: some View {
        if let store {
            PlayerContentMainView(store: store)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "play.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("请在番剧详情中选择一集开始播放。")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.platformBackground)
        }
    }
}

private struct PlayerContentMainView: View {
    let store: StoreOf<PlayerPresenter>
    @StateObject private var playerController = PlayerController()
    @State private var isImportingLocalSubtitle = false
    @State private var scrubPosition: TimeInterval = 0
    @State private var isScrubbing = false
    @State private var isControlBarVisible = true
    @State private var isPointerInsidePlayer = false
    @State private var isPointerInsideControls = false
    @State private var isAudioPopoverPresented = false
    @State private var isSubtitlePopoverPresented = false
    @State private var isSpeedPopoverPresented = false
    @State private var isEpisodePopoverPresented = false
    @State private var isDanmakuPopoverPresented = false
    @State private var isPlaybackSettingsPopoverPresented = false
    @State private var observedWindow: NSWindow?
    @State private var isFullscreen = false
    @State private var usesFullscreenLayout = false
    @State private var isCursorHidden = false
    @State private var lastPointerLocation: CGPoint?
    @State private var lastPointerMovementAt: ContinuousClock.Instant?
    @State private var isSubtitleRendererReady = false
    @State private var lastReportedSubtitleWindowPlaybackSecond: Int?
    @State private var isAdjustingSubtitleOffset = false
    @State private var isShowingSubtitleOffsetPopup = false
    @State private var selectedEpisodePageIndex = 0
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var subtitleOffsetPopupTask: Task<Void, Never>?
    @State private var shortcutHUDTask: Task<Void, Never>?
    @State private var fullscreenTransitionTask: Task<Void, Never>?
    @State private var pendingShortcutCaptureAction: PlayerShortcutAction?
    @State private var isForwardShortcutPressed = false
    @State private var isTemporaryBoostShortcutActive = false
    @State private var forwardShortcutActivationTask: Task<Void, Never>?
    @State private var fullscreenShortcutHUD: PlayerShortcutHUDState?
    @State private var pendingManagedFullscreenTarget: Bool?
    @AppStorage("player.danmaku.visible") private var isDanmakuVisible = true
    @AppStorage("player.danmaku.fontScale") private var danmakuFontScale = 1.5
    @AppStorage("player.danmaku.opacity") private var danmakuOpacity = 0.9
    @AppStorage("player.danmaku.speed") private var danmakuSpeed = 1.0
    @State private var subtitleTimeOffset = 0.0
    @AppStorage("player.subtitle.fontSize") private var subtitleFontSize = 54.0
    @AppStorage("player.subtitle.fontFamily") private var subtitleFontFamily = ""
    @AppStorage("player.playback.mode") private var playbackModeRawValue = PlaybackMode.sequential.rawValue
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
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            playerScreen(viewStore: viewStore)
        }
        .background(Color.platformBackground.ignoresSafeArea())
        .onChange(of: isAudioPopoverPresented) { _, _ in
            scheduleControlBarVisibilityUpdate()
        }
        .onChange(of: isSubtitlePopoverPresented) { _, _ in
            scheduleControlBarVisibilityUpdate()
        }
        .onChange(of: isSpeedPopoverPresented) { _, _ in
            scheduleControlBarVisibilityUpdate()
        }
        .onChange(of: isEpisodePopoverPresented) { _, _ in
            scheduleControlBarVisibilityUpdate()
        }
        .onChange(of: isDanmakuPopoverPresented) { _, _ in
            scheduleControlBarVisibilityUpdate()
        }
        .onChange(of: isPlaybackSettingsPopoverPresented) { _, _ in
            scheduleControlBarVisibilityUpdate()
        }
        .onChange(of: isPlaybackSettingsPopoverPresented) { _, isPresented in
            if !isPresented {
                cancelSubtitleOffsetPopup()
                isAdjustingSubtitleOffset = false
                pendingShortcutCaptureAction = nil
            }
        }
    }

    @ViewBuilder
    private func playerScreen(
        viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>
    ) -> some View {
        VStack(spacing: usesFullscreenLayout ? 0 : 16) {
            if let stream = viewStore.currentItem?.stream {
                let options = makeOptions(
                    for: stream,
                    selectedAudioTrackID: viewStore.selectedAudioTrackID,
                    selectedEmbeddedSubtitleTrackID: effectiveEmbeddedSubtitleTrackID(viewStore: viewStore),
                    subtitleTimeOffset: subtitleTimeOffset,
                    subtitleFontSize: subtitleFontSize,
                    subtitleFontFamily: effectiveSubtitleFontFamily,
                    allowAutoPlay: shouldAllowAutoPlay(
                        viewStore: viewStore,
                        isSubtitleRendererReady: isSubtitleRendererReady,
                        playbackState: playerController.playbackState
                    )
                )
                let customSubtitleDocument = makeCustomSubtitleDocument(
                    from: viewStore.activeSubtitle,
                    isSuppressed: viewStore.areSubtitlesSuppressed
                )
                HStack(alignment: .top, spacing: usesFullscreenLayout ? 0 : 18) {
                    playerStage(
                        viewStore: viewStore,
                        stream: stream,
                        options: options,
                        customSubtitleDocument: customSubtitleDocument
                    )
                    .frame(maxWidth: .infinity)

                    if !usesFullscreenLayout {
                        episodeSidebar(viewStore: viewStore)
                            .frame(width: 300)
                    }
                }
            } else {
                Text("暂无可播放内容。")
                    .foregroundStyle(.secondary)
            }

            if !usesFullscreenLayout, let error = viewStore.subtitleError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !usesFullscreenLayout, let playbackError = viewStore.playbackError, !playbackError.isEmpty {
                Text(playbackError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(usesFullscreenLayout ? 0 : 16)
        .background {
            playerBackgroundLayer(for: viewStore.coverURL)
                .ignoresSafeArea()
        }
#if os(macOS)
        .overlay {
            PlayerKeyboardEventMonitor(
                onKeyDown: handlePlayerKeyDown(_:),
                onKeyUp: handlePlayerKeyUp(_:),
                canHandleEvent: {
                    observedWindow != nil
                }
            )
            .frame(width: 0, height: 0)
        }
#endif
        .sheet(
            item: viewStore.binding(
                get: \.fileSelection,
                send: { _ in .fileSelectionDismissed }
            )
        ) { selection in
            PlayerFileSelectionView(
                selection: selection,
                onSelect: { file in
                    viewStore.send(.fileSelected(file))
                },
                onCancel: {
                    viewStore.send(.fileSelectionDismissed)
                }
            )
        }
        .onAppear {
            syncEpisodePageSelection(with: viewStore)
        }
        .onChange(of: viewStore.currentIndex) { _, _ in
            syncEpisodePageSelection(with: viewStore)
        }
        .onChange(of: viewStore.playlist.count) { _, _ in
            syncEpisodePageSelection(with: viewStore)
        }
    }

    @ViewBuilder
    private func playerStage(
        viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>,
        stream: RemoteMediaLibraryClient.StreamContext,
        options: PlayerLoadOptions,
        customSubtitleDocument: SubtitleDocument?
    ) -> some View {
        GeometryReader { geometry in
            let subtitleViewportSize = subtitleOverlayViewportSize(in: geometry.size)
            ZStack(alignment: .bottom) {
                PlayerView(
                    backend: .defaultDistributable,
                    source: .init(
                        url: stream.url,
                        headers: stream.headers
                    ),
                    controller: playerController,
                    options: options,
                )
                    .onStateChanged { state in
                        switch state {
                        case .error(let message):
                            viewStore.send(.setPlaybackError(message ?? "播放失败。"))
                        case .playing:
                            if let fileID = viewStore.currentFileID {
                                viewStore.send(.playbackStarted(fileID))
                            }
                            viewStore.send(.setPlaybackError(nil))
                        case .completed:
                            viewStore.send(.setPlaybackError(nil))
                        case .buffering, .preparing, .paused, .stopped, .idle:
                            break
                        }
                    }
                    .onFinish { error in
                        if let error {
                            viewStore.send(.setPlaybackError(error.localizedDescription))
                        } else {
                            handlePlaybackCompletion(viewStore: viewStore)
                        }
                    }
                    .onTracksChanged { tracks in
                        guard let fileID = viewStore.currentFileID else { return }
                        viewStore.send(.playerTracksChanged(fileID, tracks))
                    }
                    .onPlaybackTimeChanged { playbackTime in
                        guard let fileID = viewStore.currentFileID else { return }
                        let second = max(Int(playbackTime.rounded(.down)), 0)
                        guard lastReportedSubtitleWindowPlaybackSecond != second else { return }
                        lastReportedSubtitleWindowPlaybackSecond = second
                        viewStore.send(.playbackTimeUpdated(fileID, playbackTime))
                    }
                SubtitleRendererOverlay(
                    document: customSubtitleDocument,
                    playbackTime: adjustedSubtitlePlaybackTime(
                        playerController.timeline.currentTime,
                        subtitleTimeOffset: subtitleTimeOffset
                    ),
                    defaultFontFamily: effectiveSubtitleFontFamily,
                    fontSize: subtitleFontSize,
                    onReadinessChanged: { ready in
                        if isSubtitleRendererReady != ready {
                            debugLogSubtitleRenderer(
                                "readiness changed ready=\(ready) fileID=\(viewStore.currentFileID ?? "<none>") activeSubtitle=\(viewStore.activeSubtitle?.fileName ?? "<none>")"
                            )
                        }
                        isSubtitleRendererReady = ready
                    }
                )
                .frame(width: subtitleViewportSize.width, height: subtitleViewportSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                DanmakuRenderOverlay(
                    loadedDanmaku: viewStore.activeDanmaku,
                    controller: playerController,
                    settings: currentDanmakuSettings
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                if let fullscreenShortcutHUD, isFullscreen {
                    VStack {
                        fullscreenShortcutHUDView(fullscreenShortcutHUD)
                            .padding(.top, 28)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                playbackControlBar(viewStore: viewStore)
                    .opacity(isControlBarVisible ? 1 : 0)
                    .offset(y: isControlBarVisible ? 0 : 28)
                    .scaleEffect(isControlBarVisible ? 1 : 0.97, anchor: .bottom)
                    .allowsHitTesting(isControlBarVisible)
#if os(macOS)
                PlayerWindowObserver(
                    onWindowChanged: { window in
                        observedWindow = window
                        let fullscreen = window?.styleMask.contains(.fullScreen) ?? false
                        isFullscreen = fullscreen
                        if fullscreenTransitionTask == nil && pendingManagedFullscreenTarget == nil {
                            usesFullscreenLayout = fullscreen
                        }
                        updateWindowToolbarVisibility()
                        scheduleControlBarVisibilityUpdate()
                    },
                    onFullscreenWillChange: { fullscreen in
                        handleFullscreenTransitionStart(to: fullscreen)
                    },
                    onFullscreenChanged: { fullscreen in
                        isFullscreen = fullscreen
                        usesFullscreenLayout = fullscreen
                        updateWindowToolbarVisibility()
                        handleFullscreenTransitionCompletion(to: fullscreen)
                    }
                )
                .frame(width: 0, height: 0)
#endif
            }
        }
        .frame(minHeight: 240, maxHeight: usesFullscreenLayout ? .infinity : nil)
        .clipped()
#if os(macOS)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case let .active(location):
                isPointerInsidePlayer = true
                if didPointerMove(to: location) {
                    handlePlayerPointerMovement()
                }
            case .ended:
                isPointerInsidePlayer = false
                lastPointerLocation = nil
                if !usesFullscreenLayout {
                    scheduleControlBarVisibilityUpdate()
                }
            }
        }
#endif
        .onAppear {
            viewStore.send(.onAppear)
            viewStore.send(.setPlaybackError(nil))
            revealControls()
        }
        .onChange(of: viewStore.currentItem?.stream) { _, newStream in
            guard newStream != nil else { return }
            playerController.reset()
            cancelForwardShortcutTracking()
            dismissFullscreenShortcutHUD()
            fullscreenTransitionTask?.cancel()
            fullscreenTransitionTask = nil
            pendingManagedFullscreenTarget = nil
            scrubPosition = 0
            isScrubbing = false
            isSubtitleRendererReady = false
            lastReportedSubtitleWindowPlaybackSecond = nil
            subtitleTimeOffset = 0
            isAudioPopoverPresented = false
            isSubtitlePopoverPresented = false
            isSpeedPopoverPresented = false
            revealControls()
            viewStore.send(.setPlaybackError(nil))
        }
        .onChange(of: playerController.timeline.currentTime) { _, newValue in
            guard !isScrubbing else { return }
            scrubPosition = newValue
        }
        .onChange(of: viewStore.activeSubtitle?.fileName) { oldValue, newValue in
            debugLogSubtitleRenderer(
                "active subtitle changed old=\(oldValue ?? "<none>") new=\(newValue ?? "<none>") fileID=\(viewStore.currentFileID ?? "<none>")"
            )
        }
        .onChange(of: viewStore.selectedEmbeddedSubtitleTrackID) { oldValue, newValue in
            debugLogSubtitleRenderer(
                "selected embedded subtitle track changed old=\(oldValue ?? "<none>") new=\(newValue ?? "<none>") fileID=\(viewStore.currentFileID ?? "<none>")"
            )
        }
        .onDisappear {
            cancelForwardShortcutTracking()
            dismissFullscreenShortcutHUD()
            fullscreenTransitionTask?.cancel()
            fullscreenTransitionTask = nil
            pendingManagedFullscreenTarget = nil
            isScrubbing = false
            lastPointerLocation = nil
            cancelFullscreenPointerTasks()
            showCursorIfNeeded()
        }
    }
    
    private func currentTitle(for episode: Components.Schemas.LibraryBangumiEpisode) -> String {
        currentTitleStatic(for: episode)
    }
    
    @ViewBuilder
    private func playbackControlBar(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        let duration = max(playerController.timeline.duration ?? 0, 0)
        let effectiveDuration = max(duration, 1)
        let displayedTime = isScrubbing ? scrubPosition : min(playerController.timeline.currentTime, effectiveDuration)

        VStack(spacing: 14) {
            if let current = viewStore.currentItem {
                VStack(alignment: .leading, spacing: 6) {
                    Text("正在播放")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(0.8)
                    Text(currentTitle(for: current.episode))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.97))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        metadataPill(
                            title: current.file.name ?? "未知文件",
                            systemImage: "doc.text"
                        )
                        if let episodeNumber = current.episode.episodeNumber, !episodeNumber.isEmpty {
                            metadataPill(
                                title: "第\(episodeNumber)话",
                                systemImage: "play.tv"
                            )
                        }
                        if hasVisibleSubtitleOffset(subtitleTimeOffset) {
                            metadataPill(
                                title: subtitleOffsetStatusTitle(subtitleTimeOffset),
                                systemImage: "captions.bubble"
                            )
                        }
                    }
                    Text(current.stream.url.absoluteString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
            }

            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { scrubPosition = $0 }
                ),
                in: 0...effectiveDuration,
                onEditingChanged: { editing in
                    if editing {
                        isScrubbing = true
                        scrubPosition = playerController.timeline.currentTime
                    } else {
                        isScrubbing = false
                        playerController.seekTo(scrubPosition)
                    }
                }
            )
            .tint(.white.opacity(0.92))
            .disabled(duration <= 0)

            HStack(spacing: 14) {
                Text(formatPlaybackTime(displayedTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 58, alignment: .leading)

                ViewThatFits(in: .horizontal) {
                    controlBarActionRow(viewStore: viewStore, displayMode: .expanded)
                    controlBarActionRow(viewStore: viewStore, displayMode: .compact)
                }
                .frame(maxWidth: .infinity)

                Text(formatPlaybackTime(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 58, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: 1040)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
#if os(macOS)
        .onHover { inside in
            isPointerInsideControls = inside
            if usesFullscreenLayout {
                if inside {
                    cancelControlBarAutoHide()
                    revealControlsIfNeeded()
                }
            } else {
                if inside {
                    cancelControlBarAutoHide()
                    revealControlsIfNeeded()
                }
                scheduleControlBarVisibilityUpdate()
            }
        }
#endif
    }

    @ViewBuilder
    private func controlBarActionRow(
        viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>,
        displayMode: PlaybackControlDisplayMode
    ) -> some View {
        HStack(spacing: 10) {
            controlButtonCluster(opacity: 0.18) {
                glassIconButton("backward.end.fill", isDisabled: viewStore.currentIndex == 0) {
                    viewStore.send(.playPrevious)
                }
                glassIconButton(playerController.isPlaying ? "pause.fill" : "play.fill") {
                    playerController.togglePlayPause()
                }
                glassIconButton("forward.end.fill", isDisabled: viewStore.currentIndex + 1 >= viewStore.playlist.count) {
                    viewStore.send(.playNext)
                }
            }

            controlButtonCluster(opacity: 0.14) {
                danmakuMenu(displayMode: displayMode)
                playbackSettingsMenu(viewStore: viewStore, displayMode: displayMode)
                speedMenu(displayMode: displayMode)
            }

            controlButtonCluster(opacity: 0.14) {
                audioMenu(viewStore: viewStore, displayMode: displayMode)
                subtitleMenu(viewStore: viewStore, displayMode: displayMode)
                if usesFullscreenLayout {
                    episodeMenu(viewStore: viewStore)
                }
            }

            Spacer(minLength: 0)

#if os(macOS)
            glassIconButton(
                usesFullscreenLayout ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            ) {
                togglePlayerFullscreen()
            }
#endif
        }
    }

    @ViewBuilder
    private func speedMenu(displayMode: PlaybackControlDisplayMode = .expanded) -> some View {
        Button {
            isSpeedPopoverPresented.toggle()
            revealControls()
        } label: {
            glassAdaptiveControlLabel(
                title: playbackRateTitle(playerController.playbackRate),
                systemImage: "gauge.with.dots.needle.50percent",
                displayMode: displayMode
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isSpeedPopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button {
                        playerController.setPlaybackRate(rate)
                        isSpeedPopoverPresented = false
                    } label: {
                        selectionRowLabel(
                            title: playbackRateTitle(rate),
                            subtitle: rate == 1 ? "默认速度" : nil,
                            isSelected: abs(playerController.playbackRate - rate) < 0.001
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(minWidth: 180, alignment: .leading)
        }
    }

    @ViewBuilder
    private func danmakuMenu(displayMode: PlaybackControlDisplayMode = .expanded) -> some View {
        Button {
            isDanmakuPopoverPresented.toggle()
            revealControls()
        } label: {
            glassAdaptiveControlLabel(
                title: "弹幕设置",
                systemImage: "text.bubble",
                displayMode: displayMode
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isDanmakuPopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("显示弹幕", isOn: $isDanmakuVisible)
                    .toggleStyle(.switch)

                controlSettingRow(
                    title: "字号",
                    value: "\(Int((danmakuFontScale * 100).rounded()))%"
                ) {
                    Slider(value: $danmakuFontScale, in: 1.0...2.5, step: 0.1)
                }

                controlSettingRow(
                    title: "透明度",
                    value: "\(Int((danmakuOpacity * 100).rounded()))%"
                ) {
                    Slider(value: $danmakuOpacity, in: 0.2...1.0, step: 0.05)
                }

                controlSettingRow(
                    title: "速度",
                    value: String(format: "%.1fx", danmakuSpeed)
                ) {
                    Slider(value: $danmakuSpeed, in: 0.5...2.0, step: 0.1)
                }
            }
            .padding(14)
            .frame(width: 260, alignment: .leading)
        }
    }

    @ViewBuilder
    private func playbackSettingsMenu(
        viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>,
        displayMode: PlaybackControlDisplayMode = .expanded
    ) -> some View {
        Button {
            isPlaybackSettingsPopoverPresented.toggle()
            revealControls()
        } label: {
            glassAdaptiveControlLabel(
                title: "播放设置",
                systemImage: "slider.horizontal.3",
                displayMode: displayMode
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPlaybackSettingsPopoverPresented, arrowEdge: .bottom) {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            settingsSectionTitle("字幕")
                            controlSettingRow(
                                title: "时间偏移",
                                value: formattedSubtitleTimeOffset(subtitleTimeOffset)
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Slider(
                                        value: $subtitleTimeOffset,
                                        in: -10...10,
                                        step: 0.1,
                                        onEditingChanged: { editing in
                                            if editing {
                                                isAdjustingSubtitleOffset = true
                                                showSubtitleOffsetPopup()
                                            } else {
                                                isAdjustingSubtitleOffset = false
                                                
                                                keepSubtitleOffsetPopupVisibleBriefly()
                                            }
                                        }
                                    )
                                    HStack(spacing: 8) {
                                        smallSettingButton("提前 0.5s") {
                                            subtitleTimeOffset = max(subtitleTimeOffset - 0.5, -10)
                                            keepSubtitleOffsetPopupVisibleBriefly()
                                        }
                                        smallSettingButton("重置") {
                                            subtitleTimeOffset = 0
                                            keepSubtitleOffsetPopupVisibleBriefly()
                                        }
                                        smallSettingButton("推后 0.5s") {
                                            subtitleTimeOffset = min(subtitleTimeOffset + 0.5, 10)
                                            keepSubtitleOffsetPopupVisibleBriefly()
                                        }
                                    }
                                }
                            }
                            controlSettingRow(
                                title: "字号",
                                value: formattedSubtitleFontSize(subtitleFontSize)
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Slider(value: $subtitleFontSize, in: 24...84, step: 2)
                                    HStack(spacing: 8) {
                                        smallSettingButton("缩小") {
                                            subtitleFontSize = max(subtitleFontSize - 2, 24)
                                        }
                                        smallSettingButton("重置") {
                                            subtitleFontSize = 54
                                        }
                                        smallSettingButton("放大") {
                                            subtitleFontSize = min(subtitleFontSize + 2, 84)
                                        }
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("默认字体")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                    Text(currentSubtitleFontOption.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(subtitleFontOptions) { option in
                                    Button {
                                        subtitleFontFamily = option.rawValue
                                    } label: {
                                        selectionRowLabel(
                                            title: option.title,
                                            subtitle: option.preview,
                                            isSelected: subtitleFontFamily == option.rawValue
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            settingsSectionTitle("播放模式")
                            ForEach(PlaybackMode.allCases) { mode in
                                Button {
                                    playbackModeRawValue = mode.rawValue
                                } label: {
                                    selectionRowLabel(
                                        title: mode.title,
                                        subtitle: mode.description,
                                        isSelected: playbackMode == mode
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                settingsSectionTitle("快捷键")
                                Spacer(minLength: 0)
                                smallSettingButton("恢复默认") {
                                    resetShortcutSettingsToDefaults()
                                }
                            }

                            Text("一个功能可以绑定多个按键；同一个按键只会归属最后一次绑定。点击“添加按键”后直接按键，按 Esc 取消。")
                                .font(.caption2)
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

                            controlSettingRow(
                                title: "前进 / 后退步进",
                                value: formattedShortcutMilliseconds(shortcutSeekStepMilliseconds)
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Slider(value: $shortcutSeekStepMilliseconds, in: 1000...30000, step: 500)
                                    HStack(spacing: 8) {
                                        smallSettingButton("-500 ms") {
                                            shortcutSeekStepMilliseconds = max(shortcutSeekStepMilliseconds - 500, 1000)
                                        }
                                        smallSettingButton("重置") {
                                            shortcutSeekStepMilliseconds = PlayerShortcutDefaults.seekStepMilliseconds
                                        }
                                        smallSettingButton("+500 ms") {
                                            shortcutSeekStepMilliseconds = min(shortcutSeekStepMilliseconds + 500, 30000)
                                        }
                                    }
                                }
                            }

                            controlSettingRow(
                                title: "按住右键倍速",
                                value: playbackRateTitle(shortcutHoldToBoostRate)
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Slider(value: $shortcutHoldToBoostRate, in: 1.25...6.0, step: 0.25)
                                    HStack(spacing: 8) {
                                        smallSettingButton("-0.25x") {
                                            shortcutHoldToBoostRate = max(shortcutHoldToBoostRate - 0.25, 1.25)
                                        }
                                        smallSettingButton("重置") {
                                            shortcutHoldToBoostRate = PlayerShortcutDefaults.holdToBoostRate
                                        }
                                        smallSettingButton("+0.25x") {
                                            shortcutHoldToBoostRate = min(shortcutHoldToBoostRate + 0.25, 6)
                                        }
                                    }
                                }
                            }

                            controlSettingRow(
                                title: "音量步进",
                                value: formattedVolumeStepPercent(shortcutVolumeStepPercent)
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Slider(value: $shortcutVolumeStepPercent, in: 1...20, step: 1)
                                    HStack(spacing: 8) {
                                        smallSettingButton("-1%") {
                                            shortcutVolumeStepPercent = max(shortcutVolumeStepPercent - 1, 1)
                                        }
                                        smallSettingButton("重置") {
                                            shortcutVolumeStepPercent = PlayerShortcutDefaults.volumeStepPercent
                                        }
                                        smallSettingButton("+1%") {
                                            shortcutVolumeStepPercent = min(shortcutVolumeStepPercent + 1, 20)
                                        }
                                    }
                                }
                            }

                            ForEach(PlayerShortcutAction.allCases) { action in
                                shortcutBindingRow(for: action)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            settingsSectionTitle("当前状态")
                            Text("后端：\(PlayerBackendKind.defaultDistributable.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("当前字幕：\(subtitleMenuTitle(externalSubtitle: selectedExternalSubtitleTitle(viewStore: viewStore), embeddedSubtitle: viewStore.selectedEmbeddedSubtitle?.displayName, isSuppressed: viewStore.areSubtitlesSuppressed))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                }
                if isShowingSubtitleOffsetPopup || isAdjustingSubtitleOffset {
                    subtitleOffsetNotice(subtitleTimeOffset)
                        .padding(.top, 10)
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(width: 340, height: 620, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func shortcutBindingRow(for action: PlayerShortcutAction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.subheadline.weight(.semibold))
                Text(action.detail)
                    .font(.caption2)
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
                    .frame(minWidth: 72)
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
                                smallSettingButton("移除") {
                                    removeShortcutBinding(binding, for: action)
                                }
                            }
                        }
                    }
                    smallSettingButton("默认") {
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

    @ViewBuilder
    private func episodeMenu(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        Button {
            isEpisodePopoverPresented.toggle()
            revealControls()
        } label: {
            glassCapsuleLabel(
                title: "选集",
                systemImage: "list.bullet.rectangle"
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isEpisodePopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                episodePagePicker(viewStore: viewStore)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(displayedEpisodeItems(viewStore: viewStore)) { item in
                                Button {
                                    viewStore.send(.playItem(item.id))
                                    isEpisodePopoverPresented = false
                                } label: {
                                    selectionRowLabel(
                                        title: currentTitle(for: item.episode),
                                        subtitle: item.file.name ?? "未知文件",
                                        isSelected: viewStore.currentItem?.id == item.id
                                    )
                                }
                                .id(item.id)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(height: 320)
                    .onAppear {
                        scrollEpisodeSelectionIntoView(viewStore: viewStore, proxy: proxy)
                    }
                    .onChange(of: selectedEpisodePageIndex) { _, _ in
                        scrollEpisodeSelectionIntoView(viewStore: viewStore, proxy: proxy)
                    }
                }
            }
            .padding(.vertical, 12)
            .frame(width: 300)
        }
    }

    @ViewBuilder
    private func episodeSidebar(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("剧集")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                VStack(alignment: .leading, spacing: 0) {
                    Text(viewStore.seriesTitle ?? "未命名番剧")
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(currentTitle(for: viewStore.currentItem?.episode ?? .init()))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.92))
                        .lineLimit(2)
                }
                Text("\(viewStore.playlist.count) 集内容")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            episodePagePicker(viewStore: viewStore)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(displayedEpisodeItems(viewStore: viewStore)) { item in
                            Button {
                                viewStore.send(.playItem(item.id))
                            } label: {
                                episodeBrowserRow(
                                    item: item,
                                    isSelected: viewStore.currentItem?.id == item.id
                                )
                            }
                            .id(item.id)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
                .onAppear {
                    scrollEpisodeSelectionIntoView(viewStore: viewStore, proxy: proxy)
                }
                .onChange(of: selectedEpisodePageIndex) { _, _ in
                    scrollEpisodeSelectionIntoView(viewStore: viewStore, proxy: proxy)
                }
                .onChange(of: viewStore.currentItem?.id) { _, _ in
                    scrollEpisodeSelectionIntoView(viewStore: viewStore, proxy: proxy)
                }
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 22, y: 10)
    }

    @ViewBuilder
    private func episodePagePicker(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        let pages = episodePages(itemCount: viewStore.playlist.count)
        if pages.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pages) { page in
                        Button {
                            selectedEpisodePageIndex = page.index
                        } label: {
                            Text(page.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(
                                            selectedEpisodePageIndex == page.index
                                            ? Color.accentColor.opacity(0.22)
                                            : Color.white.opacity(0.06)
                                        )
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(
                                            selectedEpisodePageIndex == page.index
                                            ? Color.accentColor.opacity(0.7)
                                            : Color.white.opacity(0.06),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func displayedEpisodeItems(
        viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>
    ) -> [PlayerPresenter.State.PlaylistItem] {
        let pages = episodePages(itemCount: viewStore.playlist.count)
        guard let page = pages.first(where: { $0.index == selectedEpisodePageIndex }) else {
            return Array(viewStore.playlist)
        }
        return Array(viewStore.playlist[page.range])
    }

    private func syncEpisodePageSelection(
        with viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>
    ) {
        let pages = episodePages(itemCount: viewStore.playlist.count)
        guard !pages.isEmpty else {
            selectedEpisodePageIndex = 0
            return
        }
        selectedEpisodePageIndex = min(viewStore.currentIndex / 25, pages.count - 1)
    }

    private func scrollEpisodeSelectionIntoView(
        viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>,
        proxy: ScrollViewProxy
    ) {
        guard let currentItemID = viewStore.currentItem?.id,
              displayedEpisodeItems(viewStore: viewStore).contains(where: { $0.id == currentItemID }) else {
            return
        }
        DispatchQueue.main.async {
            proxy.scrollTo(currentItemID, anchor: .center)
        }
    }

    @ViewBuilder
    private func audioMenu(
        viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>,
        displayMode: PlaybackControlDisplayMode = .expanded
    ) -> some View {
        Button {
            isAudioPopoverPresented.toggle()
            revealControls()
        } label: {
            glassAdaptiveControlLabel(
                title: selectedAudioTrackTitle(
                    tracks: viewStore.availableAudioTracks,
                    selectedAudioTrackID: viewStore.selectedAudioTrackID
                ),
                systemImage: "waveform",
                displayMode: displayMode
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isAudioPopoverPresented, arrowEdge: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: {
                            viewStore.send(.audioTrackSelected(nil))
                            isAudioPopoverPresented = false
                        }) {
                            selectionRowLabel(title: "自动选择", subtitle: nil, isSelected: viewStore.selectedAudioTrackID == nil)
                        }
                        .id("audio-auto")
                        .buttonStyle(.plain)
                        ForEach(viewStore.availableAudioTracks) { track in
                            Button {
                                viewStore.send(.audioTrackSelected(track.id))
                                isAudioPopoverPresented = false
                            } label: {
                                selectionRowLabel(title: track.displayName, subtitle: track.language, isSelected: viewStore.selectedAudioTrackID == track.id)
                            }
                            .id(track.id)
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .frame(minWidth: 180, maxHeight: 260, alignment: .leading)
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(viewStore.selectedAudioTrackID ?? "audio-auto", anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func subtitleMenu(
        viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>,
        displayMode: PlaybackControlDisplayMode = .expanded
    ) -> some View {
        Button {
            isSubtitlePopoverPresented.toggle()
            revealControls()
        } label: {
            glassAdaptiveControlLabel(
                title: subtitleMenuTitle(
                    externalSubtitle: selectedExternalSubtitleTitle(viewStore: viewStore),
                    embeddedSubtitle: viewStore.selectedEmbeddedSubtitle?.displayName,
                    isSuppressed: viewStore.areSubtitlesSuppressed
                ),
                systemImage: "captions.bubble",
                displayMode: displayMode
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isSubtitlePopoverPresented, arrowEdge: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            viewStore.send(.setSubtitlesSuppressed(!viewStore.areSubtitlesSuppressed))
                        }) {
                            selectionRowLabel(
                                title: viewStore.areSubtitlesSuppressed ? "开启字幕" : "关闭字幕",
                                subtitle: nil,
                                isSelected: false
                            )
                        }
                        .buttonStyle(.plain)
                        Button(action: {
                            isImportingLocalSubtitle = true
                            isSubtitlePopoverPresented = false
                        }) {
                            selectionRowLabel(title: "导入本地字幕…", subtitle: nil, isSelected: false)
                        }

                        if !viewStore.areSubtitlesSuppressed,
                           (viewStore.availableSubtitles.isEmpty == false || viewStore.availableEmbeddedSubtitles.isEmpty == false) {
                            Divider()
                        }
                        if viewStore.availableSubtitles.isEmpty,
                           viewStore.availableEmbeddedSubtitles.isEmpty {
                            Text("暂无字幕")
                                .foregroundStyle(.secondary)
                        } else if !viewStore.areSubtitlesSuppressed {
                            if !viewStore.availableSubtitles.isEmpty {
                                if !viewStore.availableEmbeddedSubtitles.isEmpty {
                                    Text("外挂字幕")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(viewStore.availableSubtitles) { subtitle in
                                    Button {
                                        viewStore.send(.subtitleSelected(subtitle))
                                        isSubtitlePopoverPresented = false
                                    } label: {
                                        selectionRowLabel(
                                            title: externalSubtitleDisplayTitle(subtitle),
                                            subtitle: nil,
                                            isSelected: viewStore.selectedSubtitle?.id == subtitle.id
                                        )
                                    }
                                    .id("subtitle-external-\(subtitle.id)")
                                    .buttonStyle(.plain)
                                }
                            }
                            if !viewStore.availableEmbeddedSubtitles.isEmpty {
                                if !viewStore.availableSubtitles.isEmpty {
                                    Divider()
                                    Text("内嵌字幕")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(viewStore.availableEmbeddedSubtitles) { subtitle in
                                    Button {
                                        viewStore.send(.embeddedSubtitleSelected(subtitle.id))
                                        isSubtitlePopoverPresented = false
                                    } label: {
                                        selectionRowLabel(
                                            title: subtitle.displayName,
                                            subtitle: subtitle.language,
                                            isSelected: viewStore.selectedEmbeddedSubtitleTrackID == subtitle.id && viewStore.selectedSubtitle == nil
                                        )
                                    }
                                    .id("subtitle-embedded-\(subtitle.id)")
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .frame(minWidth: 240, maxHeight: 320, alignment: .leading)
                .onAppear {
                    let targetID = viewStore.selectedSubtitle.map { "subtitle-external-\($0.id)" }
                        ?? viewStore.selectedEmbeddedSubtitleTrackID.map { "subtitle-embedded-\($0)" }
                    guard let targetID else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingLocalSubtitle,
            allowedContentTypes: supportedSubtitleContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                let accessedSecurityScope = url.startAccessingSecurityScopedResource()
                defer {
                    if accessedSecurityScope {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    store.send(.localSubtitleLoaded(fileName: url.lastPathComponent, content: content))
                } catch {
                    store.send(.localSubtitleLoadFailed(error.localizedDescription))
                }
            case let .failure(error):
                store.send(.localSubtitleLoadFailed(error.localizedDescription))
            }
        }
    }

    private var isAnyControlPopoverPresented: Bool {
        isAudioPopoverPresented
            || isSubtitlePopoverPresented
            || isSpeedPopoverPresented
            || isEpisodePopoverPresented
            || isDanmakuPopoverPresented
            || isPlaybackSettingsPopoverPresented
    }

    private var currentDanmakuSettings: DanmakuRenderSettings {
        .init(
            isVisible: isDanmakuVisible,
            fontScale: danmakuFontScale,
            opacity: danmakuOpacity,
            speed: danmakuSpeed
        )
    }

    private var effectiveSubtitleFontFamily: String? {
        subtitleFontFamily.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private var currentSubtitleFontOption: SubtitleFontOption {
        subtitleFontOptions.first(where: { $0.rawValue == subtitleFontFamily }) ?? .systemDefault
    }

    private var playbackMode: PlaybackMode {
        PlaybackMode(rawValue: playbackModeRawValue) ?? .sequential
    }

    private var shortcutSeekStepSeconds: TimeInterval {
        max(shortcutSeekStepMilliseconds, 0) / 1000
    }

    private var shortcutVolumeStep: Double {
        min(max(shortcutVolumeStepPercent, 0), 100) / 100
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

#if os(macOS)
    private func handlePlayerKeyDown(_ event: NSEvent) -> Bool {
        if let pendingShortcutCaptureAction {
            return captureShortcutIfNeeded(event, action: pendingShortcutCaptureAction)
        }

        guard !hasUnsupportedShortcutModifiers(event),
              let action = matchingShortcutAction(for: event) else {
            return false
        }

        if event.type == .keyDown && event.isARepeat {
            return action == .seekForwardOrBoost
        }

        switch action {
        case .toggleFullscreen:
            togglePlayerFullscreen()
        case .togglePlayPause:
            playerController.togglePlayPause()
        case .playPreviousEpisode:
            store.send(.playPrevious)
        case .playNextEpisode:
            store.send(.playNext)
        case .seekBackward:
            playerController.seekBy(-shortcutSeekStepSeconds)
        case .seekForwardOrBoost:
            beginForwardShortcutTracking()
        case .decreasePlaybackRate:
            let newRate = max(playerController.playbackRate - PlayerShortcutDefaults.playbackRateAdjustmentDelta, 0.25)
            playerController.setPlaybackRate(newRate)
            showFullscreenShortcutHUD(
                title: "播放速度",
                value: playbackRateTitle(newRate),
                systemImage: "gauge.with.dots.needle.50percent"
            )
        case .increasePlaybackRate:
            let newRate = max(playerController.playbackRate + PlayerShortcutDefaults.playbackRateAdjustmentDelta, 0.25)
            playerController.setPlaybackRate(newRate)
            showFullscreenShortcutHUD(
                title: "播放速度",
                value: playbackRateTitle(newRate),
                systemImage: "gauge.with.dots.needle.50percent"
            )
        case .resetPlaybackRate:
            playerController.setPlaybackRate(PlayerShortcutDefaults.resetPlaybackRate)
            showFullscreenShortcutHUD(
                title: "播放速度",
                value: playbackRateTitle(PlayerShortcutDefaults.resetPlaybackRate),
                systemImage: "gauge.with.dots.needle.50percent"
            )
        case .volumeUp:
            let newVolume = min(max(playerController.volume + shortcutVolumeStep, 0), 1)
            playerController.setVolume(newVolume)
            showFullscreenShortcutHUD(
                title: "音量",
                value: formattedVolumeValue(newVolume),
                systemImage: "speaker.wave.2.fill"
            )
        case .volumeDown:
            let newVolume = min(max(playerController.volume - shortcutVolumeStep, 0), 1)
            playerController.setVolume(newVolume)
            showFullscreenShortcutHUD(
                title: "音量",
                value: formattedVolumeValue(newVolume),
                systemImage: newVolume <= 0.001 ? "speaker.slash.fill" : "speaker.wave.1.fill"
            )
        }
        return true
    }

    private func handlePlayerKeyUp(_ event: NSEvent) -> Bool {
        if pendingShortcutCaptureAction != nil {
            return true
        }
        guard !hasUnsupportedShortcutModifiers(event),
              shortcutBindings(for: .seekForwardOrBoost).contains(where: { $0.matches(event) }),
              isForwardShortcutPressed || isTemporaryBoostShortcutActive else {
            return false
        }

        endForwardShortcutTracking()
        return true
    }

    private func matchingShortcutAction(for event: NSEvent) -> PlayerShortcutAction? {
        PlayerShortcutAction.allCases.first { action in
            shortcutBindings(for: action).contains(where: { $0.matches(event) })
        }
    }

    private func hasUnsupportedShortcutModifiers(_ event: NSEvent) -> Bool {
        let allowed: NSEvent.ModifierFlags = [.numericPad, .function]
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return !modifiers.subtracting(allowed).isEmpty
    }

    private func captureShortcutIfNeeded(_ event: NSEvent, action: PlayerShortcutAction) -> Bool {
        guard !hasUnsupportedShortcutModifiers(event) else { return true }
        if PlayerShortcutKey.escape.matches(event) {
            pendingShortcutCaptureAction = nil
            return true
        }
        guard let binding = PlayerShortcutKey.from(event: event) else {
            return true
        }
        addShortcutBinding(binding, for: action)
        pendingShortcutCaptureAction = nil
        return true
    }
#endif

    private func beginForwardShortcutTracking() {
        forwardShortcutActivationTask?.cancel()
        forwardShortcutActivationTask = nil
        isForwardShortcutPressed = true
        isTemporaryBoostShortcutActive = false
        forwardShortcutActivationTask = Task { @MainActor in
            try? await Task.sleep(for: PlayerShortcutDefaults.holdToBoostActivationDelay)
            guard !Task.isCancelled, isForwardShortcutPressed else { return }
            isTemporaryBoostShortcutActive = true
            playerController.setPlaybackRate(shortcutHoldToBoostRate)
        }
    }

    private func endForwardShortcutTracking() {
        forwardShortcutActivationTask?.cancel()
        forwardShortcutActivationTask = nil

        let shouldRestoreNormalRate = isTemporaryBoostShortcutActive
        let shouldSeekForward = isForwardShortcutPressed && !isTemporaryBoostShortcutActive

        isForwardShortcutPressed = false
        isTemporaryBoostShortcutActive = false

        if shouldRestoreNormalRate {
            playerController.setPlaybackRate(1)
        } else if shouldSeekForward {
            playerController.seekBy(shortcutSeekStepSeconds)
        }
    }

    private func cancelForwardShortcutTracking() {
        forwardShortcutActivationTask?.cancel()
        forwardShortcutActivationTask = nil
        if isTemporaryBoostShortcutActive {
            playerController.setPlaybackRate(1)
        }
        isForwardShortcutPressed = false
        isTemporaryBoostShortcutActive = false
    }

#if os(macOS)
    private func togglePlayerFullscreen() {
        guard let observedWindow else { return }
        let target = !isFullscreen
        guard pendingManagedFullscreenTarget == nil else { return }

        pendingManagedFullscreenTarget = target
        fullscreenTransitionTask?.cancel()
        fullscreenTransitionTask = Task { @MainActor in
            if target {
                prepareForFullscreenEntry()
                try? await Task.sleep(for: .milliseconds(180))
            } else {
                dismissFullscreenShortcutHUD()
            }
            guard !Task.isCancelled else {
                pendingManagedFullscreenTarget = nil
                fullscreenTransitionTask = nil
                return
            }
            observedWindow.toggleFullScreen(nil)
        }
    }
#endif

    private func prepareForFullscreenEntry() {
        cancelControlBarAutoHide()
        lastPointerLocation = nil
        isPointerInsideControls = false
        withAnimation(.easeInOut(duration: 0.16)) {
            isControlBarVisible = false
        }
        hideCursorIfNeeded()
    }

    private func handleFullscreenTransitionStart(to fullscreen: Bool) {
        if fullscreen {
            withAnimation(.easeInOut(duration: 0.2)) {
                usesFullscreenLayout = true
            }
            updateWindowToolbarVisibility()
            cancelControlBarAutoHide()
            lastPointerLocation = nil
            isPointerInsideControls = false
            withAnimation(.easeInOut(duration: 0.18)) {
                isControlBarVisible = false
            }
            hideCursorIfNeeded()
        } else {
            cancelFullscreenPointerTasks()
            dismissFullscreenShortcutHUD()
        }
    }

    private func handleFullscreenTransitionCompletion(to fullscreen: Bool) {
        fullscreenTransitionTask?.cancel()
        fullscreenTransitionTask = nil
        pendingManagedFullscreenTarget = nil
        if fullscreen {
            cancelControlBarAutoHide()
            hideCursorIfNeeded()
            isControlBarVisible = false
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                usesFullscreenLayout = false
                isControlBarVisible = true
            }
            updateWindowToolbarVisibility()
            dismissFullscreenShortcutHUD()
            showCursorIfNeeded()
            scheduleControlBarVisibilityUpdate()
        }
    }

    private func showFullscreenShortcutHUD(title: String, value: String, systemImage: String) {
        guard isFullscreen else { return }
        shortcutHUDTask?.cancel()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            fullscreenShortcutHUD = .init(title: title, value: value, systemImage: systemImage)
        }
        shortcutHUDTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.15))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                fullscreenShortcutHUD = nil
            }
            shortcutHUDTask = nil
        }
    }

    private func dismissFullscreenShortcutHUD() {
        shortcutHUDTask?.cancel()
        shortcutHUDTask = nil
        fullscreenShortcutHUD = nil
    }

    @ViewBuilder
    private func fullscreenShortcutHUDView(_ hud: PlayerShortcutHUDState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: hud.systemImage)
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(hud.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .tracking(0.6)
                Text(hud.value)
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.96))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
    }

    private func handlePlaybackCompletion(
        viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>
    ) {
        switch playbackMode {
        case .singleRepeat:
            playerController.seekTo(0)
            playerController.setPaused(false)
        case .sequential:
            guard viewStore.currentIndex + 1 < viewStore.playlist.count else { return }
            viewStore.send(.playNext)
        case .listRepeat:
            if viewStore.currentIndex + 1 < viewStore.playlist.count {
                viewStore.send(.playNext)
            } else if let firstItem = viewStore.playlist.first {
                if firstItem.id == viewStore.currentItem?.id {
                    playerController.seekTo(0)
                    playerController.setPaused(false)
                } else {
                    viewStore.send(.playItem(firstItem.id))
                }
            }
        }
    }

    private func subtitleOverlayViewportSize(in containerSize: CGSize) -> CGSize {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        guard let videoPresentationSize = playerController.videoPresentationSize,
              videoPresentationSize.width > 0,
              videoPresentationSize.height > 0 else {
            return containerSize
        }

        let widthScale = containerSize.width / videoPresentationSize.width
        let heightScale = containerSize.height / videoPresentationSize.height
        let scale = min(widthScale, heightScale)

        guard scale.isFinite, scale > 0 else {
            return containerSize
        }

        return CGSize(
            width: max(videoPresentationSize.width * scale, 1),
            height: max(videoPresentationSize.height * scale, 1)
        )
    }

    private func didPointerMove(to location: CGPoint) -> Bool {
        guard let lastPointerLocation else {
            self.lastPointerLocation = location
            return true
        }

        let minimumDistanceToRevealControls: CGFloat = 8
        let deltaX = location.x - lastPointerLocation.x
        let deltaY = location.y - lastPointerLocation.y
        let distance = sqrt((deltaX * deltaX) + (deltaY * deltaY))
        guard distance >= minimumDistanceToRevealControls else {
            return false
        }

        self.lastPointerLocation = location
        return true
    }

    private func revealControls() {
        cancelControlBarAutoHide()
        showCursorIfNeeded()
        guard !isControlBarVisible else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            isControlBarVisible = true
        }
    }

    private func showSubtitleOffsetPopup() {
        subtitleOffsetPopupTask?.cancel()
        subtitleOffsetPopupTask = nil
        withAnimation(.easeOut(duration: 0.16)) {
            isShowingSubtitleOffsetPopup = true
        }
    }

    private func keepSubtitleOffsetPopupVisibleBriefly() {
        showSubtitleOffsetPopup()
        subtitleOffsetPopupTask?.cancel()
        subtitleOffsetPopupTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, !isAdjustingSubtitleOffset else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                isShowingSubtitleOffsetPopup = false
            }
            subtitleOffsetPopupTask = nil
        }
    }

    private func cancelSubtitleOffsetPopup() {
        subtitleOffsetPopupTask?.cancel()
        subtitleOffsetPopupTask = nil
        isShowingSubtitleOffsetPopup = false
    }

    private func revealControlsIfNeeded() {
        if isCursorHidden {
            showCursorIfNeeded()
        }
        guard !isControlBarVisible else { return }
        revealControls()
    }

    private func scheduleControlBarVisibilityUpdate() {
        cancelControlBarAutoHide()

#if os(macOS)
        if usesFullscreenLayout {
            if isAnyControlPopoverPresented || isPointerInsideControls {
                revealControlsIfNeeded()
                cancelControlBarAutoHide()
                return
            }
            resetFullscreenHideCountdown()
            return
        }

        let shouldHideLater = !isPointerInsidePlayer && !isAnyControlPopoverPresented
#else
        let shouldHideLater = false
#endif

        guard shouldHideLater else {
            revealControlsIfNeeded()
            return
        }

        hideControlsTask = Task { @MainActor in
            let delay: Duration = .seconds(1.5)
            let expectedMovementInstant = lastPointerMovementAt
            try? await Task.sleep(for: delay)
#if os(macOS)
            let stillEligible: Bool
            if usesFullscreenLayout {
                stillEligible = lastPointerMovementAt == expectedMovementInstant
                    && !isPointerInsideControls
                    && !isAnyControlPopoverPresented
            } else {
                stillEligible = lastPointerMovementAt == expectedMovementInstant
                    && !isPointerInsidePlayer
                    && !isAnyControlPopoverPresented
            }
#else
            let stillEligible = false
#endif
            guard stillEligible else { return }
            if usesFullscreenLayout {
                hideCursorIfNeeded()
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                isControlBarVisible = false
            }
        }
    }

    private func handlePlayerPointerMovement() {
        lastPointerMovementAt = .now
        if usesFullscreenLayout {
            if isCursorHidden {
                showCursorIfNeeded()
            }
            if !isControlBarVisible {
                revealControls()
            }
            resetFullscreenHideCountdown()
            return
        }
        revealControlsIfNeeded()
        scheduleControlBarVisibilityUpdate()
    }

    private func cancelControlBarAutoHide() {
        hideControlsTask?.cancel()
        hideControlsTask = nil
    }

    private func cancelFullscreenPointerTasks() {
        cancelControlBarAutoHide()
    }

    private func resetFullscreenHideCountdown() {
        cancelControlBarAutoHide()
        let expectedMovementInstant = lastPointerMovementAt
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard usesFullscreenLayout,
                  lastPointerMovementAt == expectedMovementInstant,
                  !isPointerInsideControls,
                  !isAnyControlPopoverPresented else { return }
            hideCursorIfNeeded()
            withAnimation(.easeInOut(duration: 0.22)) {
                isControlBarVisible = false
            }
        }
    }

#if os(macOS)
    private func updateWindowToolbarVisibility() {
        observedWindow?.toolbar?.isVisible = !usesFullscreenLayout
    }

    private func hideCursorIfNeeded() {
        guard !isCursorHidden else { return }
        NSCursor.hide()
        isCursorHidden = true
    }

    private func showCursorIfNeeded() {
        guard isCursorHidden else { return }
        NSCursor.unhide()
        isCursorHidden = false
    }
#else
    private func updateWindowToolbarVisibility() {}
    private func hideCursorIfNeeded() {}
    private func showCursorIfNeeded() {}
#endif
    
    @ViewBuilder
    private func playlistSection(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewStore.playlist) { item in
                    Button {
                        viewStore.send(.playItem(item.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentTitle(for: item.episode))
                                .font(.subheadline)
                                .lineLimit(2)
                            Text(item.file.name ?? "未知文件")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: 200, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    viewStore.currentItem?.id == item.id ?
                                    Color.accentColor.opacity(0.2) :
                                    Color.platformBackground.opacity(0.3)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    viewStore.currentItem?.id == item.id ?
                                    Color.accentColor :
                                    Color.platformBackground.opacity(0.4),
                                    lineWidth: viewStore.currentItem?.id == item.id ? 2 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct PlayerFileSelectionView: View {
    let selection: PlayerPresenter.State.FileSelection
    let onSelect: (Components.Schemas.LibraryBangumiMatchedFile) -> Void
    let onCancel: () -> Void
    
    private let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter
    }()
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("选择播放文件")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", action: onCancel)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if selection.files.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.square.dashed")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("没有可用的匹配文件")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(selection.files.enumerated()), id: \.offset) { _, file in
                        Button {
                            onSelect(file)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.name ?? "未知文件")
                                    .font(.headline)
                                if let size = file.size {
                                    Text(formatter.string(fromByteCount: size))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let path = file.dirPath {
                                    Text(path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.platformBackground.opacity(0.3))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

private struct EpisodePage: Identifiable {
    let index: Int
    let range: Range<Int>
    let title: String

    var id: Int { index }
}

private func episodePages(itemCount: Int) -> [EpisodePage] {
    guard itemCount > 0 else { return [] }
    let pageSize = 25
    let starts = stride(from: 0, to: itemCount, by: pageSize)
    return starts.enumerated().map { pageIndex, start in
        let end = min(start + pageSize, itemCount)
        return EpisodePage(
            index: pageIndex,
            range: start..<end,
            title: "\(start + 1)-\(end)"
        )
    }
}

private func makeOptions(
    for stream: RemoteMediaLibraryClient.StreamContext,
    selectedAudioTrackID: String?,
    selectedEmbeddedSubtitleTrackID: String?,
    subtitleTimeOffset: TimeInterval,
    subtitleFontSize: Double,
    subtitleFontFamily: String?,
    allowAutoPlay: Bool
) -> PlayerLoadOptions {
    PlayerLoadOptions(
        headers: stream.headers,
        enableHardwareDecoding: true,
        allowAutoPlay: allowAutoPlay,
        selectedAudioTrackID: selectedAudioTrackID,
        selectedEmbeddedSubtitleTrackID: selectedEmbeddedSubtitleTrackID,
        subtitleTimeOffset: subtitleTimeOffset,
        subtitleFontSize: subtitleFontSize,
        subtitleFontFamily: subtitleFontFamily
    )
}

private func adjustedSubtitlePlaybackTime(
    _ playbackTime: TimeInterval,
    subtitleTimeOffset: TimeInterval
) -> TimeInterval {
    max(playbackTime - subtitleTimeOffset, 0)
}

@MainActor
private func effectiveEmbeddedSubtitleTrackID(
    viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>
) -> String? {
    guard PlayerBackendKind.defaultDistributable.capabilities.contains(.embeddedSubtitleTracks),
          !viewStore.areSubtitlesSuppressed,
          viewStore.selectedSubtitle == nil else {
        return nil
    }
    return viewStore.selectedEmbeddedSubtitle?.backendTrackID
}

@MainActor
private func shouldAllowAutoPlay(
    viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>,
    isSubtitleRendererReady: Bool,
    playbackState: PlayerPlaybackState
) -> Bool {
    if playbackState == .paused {
        return false
    }
    if viewStore.areSubtitlesSuppressed {
        return true
    }
    if viewStore.subtitleError != nil,
       !viewStore.isLoadingSelectedSubtitle {
        return true
    }
    if viewStore.activeSubtitle != nil {
        return isSubtitleRendererReady
    }
    if PlayerBackendKind.defaultDistributable.capabilities.contains(.embeddedSubtitleTracks),
       viewStore.selectedEmbeddedSubtitle?.backendTrackID != nil {
        return true
    }
    if viewStore.selectedEmbeddedSubtitleTrackID != nil || viewStore.selectedSubtitle != nil {
        return false
    }
    if !viewStore.availableEmbeddedSubtitles.isEmpty {
        return false
    }
    if viewStore.isLoadingEmbeddedSubtitles {
        return false
    }
    return true
}

private func selectedAudioTrackTitle(
    tracks: [PlayerTrack],
    selectedAudioTrackID: PlayerTrack.ID?
) -> String {
    if let selectedAudioTrackID,
       let track = tracks.first(where: { $0.id == selectedAudioTrackID }) {
        return track.displayName
    }
    if let autoSelectedTrack = tracks.first(where: \.isSelected) {
        return autoSelectedTrack.displayName
    }
    return "自动音轨"
}

@MainActor
private func formatPlaybackTime(_ time: TimeInterval) -> String {
    guard time.isFinite, time > 0 else { return "00:00" }
    let totalSeconds = Int(time.rounded(.down))
    let seconds = totalSeconds % 60
    let minutes = (totalSeconds / 60) % 60
    let hours = totalSeconds / 3600
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}

@MainActor
@ViewBuilder
private func glassIconButton(
    _ systemName: String,
    isDisabled: Bool = false,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 38, height: 38)
            .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .background(
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0.2),
                        .white.opacity(0.1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    )
    .foregroundStyle(.white)
    .opacity(isDisabled ? 0.4 : 1)
    .disabled(isDisabled)
}

@MainActor
@ViewBuilder
private func glassCapsuleLabel(title: String, systemImage: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
        Text(title)
            .font(.caption.weight(.medium))
            .lineLimit(1)
    }
    .foregroundStyle(.white.opacity(0.9))
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(
        Capsule(style: .continuous)
            .fill(.white.opacity(0.12))
    )
}

@MainActor
@ViewBuilder
private func glassAdaptiveControlLabel(
    title: String,
    systemImage: String,
    displayMode: PlaybackControlDisplayMode
) -> some View {
    switch displayMode {
    case .expanded:
        glassCapsuleLabel(title: title, systemImage: systemImage)
    case .compact:
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 38, height: 38)
            .contentShape(Circle())
            .foregroundStyle(.white)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.2),
                                .white.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
    }
}

private func playbackRateTitle(_ rate: Double) -> String {
    if abs(rate.rounded() - rate) < 0.001 {
        return "\(Int(rate.rounded()))x"
    }
    return String(format: "%.2fx", rate)
}

@MainActor
@ViewBuilder
private func controlSettingRow<Content: View>(
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
private func settingsSectionTitle(_ title: String) -> some View {
    Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .tracking(0.8)
}

@MainActor
@ViewBuilder
private func smallSettingButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .buttonStyle(.bordered)
        .controlSize(.small)
}

@MainActor
@ViewBuilder
private func subtitleOffsetNotice(_ offset: TimeInterval) -> some View {
    HStack(spacing: 10) {
        Image(systemName: offset < 0 ? "backward.frame.fill" : "forward.frame.fill")
            .font(.system(size: 12, weight: .semibold))
        VStack(alignment: .leading, spacing: 2) {
            Text("当前总偏移")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(subtitleOffsetStatusTitle(offset))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.accentColor.opacity(0.12))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.accentColor.opacity(0.24), lineWidth: 1)
    )
}

@MainActor
@ViewBuilder
private func metadataPill(title: String, systemImage: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .semibold))
        Text(title)
            .font(.caption.weight(.medium))
            .lineLimit(1)
    }
    .foregroundStyle(.white.opacity(0.78))
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
        Capsule(style: .continuous)
            .fill(.white.opacity(0.08))
    )
}

@MainActor
@ViewBuilder
private func controlClusterBackground(opacity: Double) -> some View {
    Capsule(style: .continuous)
        .fill(
            LinearGradient(
                colors: [
                    Color.white.opacity(opacity + 0.06),
                    Color.white.opacity(opacity * 0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
}

@MainActor
@ViewBuilder
private func controlButtonCluster<Content: View>(
    opacity: Double,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(spacing: 8) {
        content()
    }
    .padding(6)
    .background(controlClusterBackground(opacity: opacity))
}

@MainActor
@ViewBuilder
private func selectionRowLabel(title: String, subtitle: String?, isSelected: Bool) -> some View {
    SelectionRowLabelView(title: title, subtitle: subtitle, isSelected: isSelected)
}

private struct SelectionRowLabelView: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14)
                .opacity(isSelected ? 1 : 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(isSelected ? .semibold : .medium)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelected
                    ? Color.accentColor.opacity(0.14)
                    : Color.white.opacity(isHovering ? 0.08 : 0)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected
                    ? Color.accentColor.opacity(0.28)
                    : Color.white.opacity(isHovering ? 0.12 : 0),
                    lineWidth: 1
                )
        )
#if os(macOS)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
#endif
    }
}

@MainActor
@ViewBuilder
private func episodeBrowserRow(
    item: PlayerPresenter.State.PlaylistItem,
    isSelected: Bool
) -> some View {
    EpisodeBrowserRowContent(item: item, isSelected: isSelected)
}

private struct EpisodeBrowserRowContent: View {
    let item: PlayerPresenter.State.PlaylistItem
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentTitleStatic(for: item.episode))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(item.file.name ?? "未知文件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .scaleEffect(isHovering && !isSelected ? 1.01 : 1)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isSelected
                    ? LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.24),
                            Color.accentColor.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [
                            Color.white.opacity(isHovering ? 0.24 : 0.1),
                            Color.white.opacity(isHovering ? 0.14 : 0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isSelected
                    ? Color.accentColor.opacity(0.55)
                    : Color.white.opacity(isHovering ? 0.28 : 0.08),
                    lineWidth: 1
                )
        )
#if os(macOS)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
#endif
    }
}

private func currentTitleStatic(for episode: Components.Schemas.LibraryBangumiEpisode) -> String {
    if let episodeTitle = episode.episodeTitle, !episodeTitle.isEmpty {
        return episodeTitle
    }
    if let displayTitle = episode.displayTitle, !displayTitle.isEmpty {
        return displayTitle
    }
    if let number = episode.episodeNumber, !number.isEmpty {
        return "第\(number)话"
    }
    return "未命名剧集"
}

#if os(macOS)
private struct PlayerWindowObserver: NSViewRepresentable {
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

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView(frame: .zero)
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: WindowObserverView, context: Context) {
        view.coordinator = context.coordinator
        context.coordinator.refresh(for: view.window)
    }

    static func dismantleNSView(_ view: WindowObserverView, coordinator: Coordinator) {
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

private final class WindowObserverView: NSView {
    weak var coordinator: PlayerWindowObserver.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.refresh(for: window)
    }
}
#endif

private func subtitleMenuTitle(
    externalSubtitle: String?,
    embeddedSubtitle: String?,
    isSuppressed: Bool
) -> String {
    if isSuppressed {
        return "字幕已关闭"
    }
    if let externalSubtitle, !externalSubtitle.isEmpty {
        return externalSubtitle
    }
    if let embeddedSubtitle, !embeddedSubtitle.isEmpty {
        return embeddedSubtitle
    }
    return "选择字幕"
}

@MainActor
private func selectedExternalSubtitleTitle(
    viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>
) -> String? {
    if viewStore.selectedEmbeddedSubtitleTrackID != nil {
        return nil
    }
    if let selectedSubtitle = viewStore.selectedSubtitle {
        return externalSubtitleDisplayTitle(selectedSubtitle)
    }
    return viewStore.activeSubtitle.flatMap { externalSubtitleDisplayTitle(fileName: $0.fileName) }
}

private func externalSubtitleDisplayTitle(_ subtitle: RemoteMediaLibraryClient.Subtitle) -> String {
    externalSubtitleDisplayTitle(fileName: subtitle.fileName) ?? subtitle.fileName
}

private func externalSubtitleDisplayTitle(fileName: String) -> String? {
    let trimmedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedFileName.isEmpty else { return nil }

    let withoutFragment = trimmedFileName
        .split(separator: "#", maxSplits: 1)
        .first
        .map(String.init) ?? trimmedFileName
    let withoutQuery = withoutFragment
        .split(separator: "?", maxSplits: 1)
        .first
        .map(String.init) ?? withoutFragment
    let normalizedPath = withoutQuery.replacingOccurrences(of: "\\", with: "/")
    let lastPathComponent = normalizedPath
        .split(separator: "/", omittingEmptySubsequences: true)
        .last
        .map(String.init) ?? normalizedPath
    let decodedComponent = lastPathComponent.removingPercentEncoding ?? lastPathComponent
    let cleanedComponent = decodedComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedComponent.isEmpty else { return nil }

    let displayName = (cleanedComponent as NSString).deletingPathExtension
    return displayName.isEmpty ? cleanedComponent : displayName
}

private func formattedSubtitleTimeOffset(_ offset: TimeInterval) -> String {
    let milliseconds = Int((offset * 1000).rounded())
    if milliseconds == 0 {
        return "0 ms"
    }
    let sign = milliseconds > 0 ? "+" : "-"
    return "\(sign)\(abs(milliseconds)) ms"
}

private func formattedShortcutMilliseconds(_ milliseconds: Double) -> String {
    "\(Int(milliseconds.rounded())) ms"
}

private func formattedVolumeStepPercent(_ percent: Double) -> String {
    "\(Int(percent.rounded()))%"
}

private func formattedVolumeValue(_ value: Double) -> String {
    "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
}

private func formattedSubtitleFontSize(_ fontSize: Double) -> String {
    "\(Int(fontSize.rounded())) pt"
}

private func hasVisibleSubtitleOffset(_ offset: TimeInterval) -> Bool {
    abs(offset) >= 0.05
}

private func subtitleOffsetStatusTitle(_ offset: TimeInterval) -> String {
    let seconds = abs(offset)
    let formatted = seconds >= 10
        ? String(format: "%.0fs", seconds)
        : String(format: "%.1fs", seconds)
    if offset < 0 {
        return "字幕提前 \(formatted)"
    }
    return "字幕推后 \(formatted)"
}

private enum PlaybackMode: String, CaseIterable, Identifiable {
    case sequential
    case singleRepeat
    case listRepeat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential:
            return "顺序播放"
        case .singleRepeat:
            return "单集循环"
        case .listRepeat:
            return "列表循环"
        }
    }

    var description: String {
        switch self {
        case .sequential:
            return "播放完成后自动进入下一集，最后一集结束后停止"
        case .singleRepeat:
            return "当前集播放完成后从头重新播放"
        case .listRepeat:
            return "播放完成后自动进入下一集，最后一集结束后回到第一集"
        }
    }
}

private struct PlayerShortcutHUDState: Equatable {
    let title: String
    let value: String
    let systemImage: String
}

private enum PlaybackControlDisplayMode {
    case expanded
    case compact
}

private enum SubtitleFontOption: String, CaseIterable, Identifiable {
    case systemDefault = ""
    case pingFangSC = "PingFang SC"
    case hiraginoSansGB = "Hiragino Sans GB"
    case songtiSC = "Songti SC"
    case helveticaNeue = "Helvetica Neue"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemDefault:
            return "系统默认"
        case .pingFangSC:
            return "苹方"
        case .hiraginoSansGB:
            return "冬青黑体"
        case .songtiSC:
            return "宋体"
        case .helveticaNeue:
            return "Helvetica Neue"
        }
    }

    var preview: String {
        switch self {
        case .systemDefault:
            return "跟随渲染器默认字体"
        case .pingFangSC, .hiraginoSansGB, .songtiSC, .helveticaNeue:
            return rawValue
        }
    }
}

private let subtitleFontOptions: [SubtitleFontOption] = SubtitleFontOption.allCases

private let supportedSubtitleContentTypes: [UTType] = {
    [
        UTType(filenameExtension: "ass"),
        UTType(filenameExtension: "ssa"),
        UTType(filenameExtension: "srt"),
        UTType(filenameExtension: "vtt"),
        .plainText,
    ].compactMap { $0 }
}()

private func makeCustomSubtitleDocument(
    from subtitle: PlayerPresenter.State.LoadedSubtitle?,
    isSuppressed: Bool
) -> SubtitleDocument? {
    guard !isSuppressed, let subtitle else { return nil }
#if os(macOS) && arch(arm64)
    guard LibassRenderer.isRuntimeAvailable else { return nil }
    return subtitle.document
#else
    return nil
#endif
}

private func debugLogSubtitleRenderer(_ message: @autoclosure () -> String) {
#if DEBUG
    print("[PlayerContentView][SubtitleRenderer] \(message())")
#endif
}

@ViewBuilder
private func playerBackgroundLayer(for url: URL?) -> some View {
    if let url {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 120, opaque: true)
                    .overlay(
                        ZStack {
                            Color.platformBackground.opacity(0.52)
                            LinearGradient(
                                colors: [
                                    Color.platformBackground.opacity(0.18),
                                    Color.platformBackground.opacity(0.72)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    )
                    .ignoresSafeArea()
            case .failure, .empty:
                Color.clear
            @unknown default:
                Color.clear
            }
        }
    } else {
        Color.clear
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Color {
    static var platformBackground: Color {
#if os(macOS)
        Color(NSColor.windowBackgroundColor)
#elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        Color(UIColor.systemBackground)
#else
        Color(.white)
#endif
    }
}
