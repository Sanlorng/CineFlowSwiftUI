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
    @State private var observedWindow: NSWindow?
    @State private var isFullscreen = false
    @State private var isCursorHidden = false
    @State private var lastPointerLocation: CGPoint?
    @State private var isSubtitleRendererReady = false
    @State private var pointerSettleTask: Task<Void, Never>?
    @State private var hideControlsTask: Task<Void, Never>?
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: isFullscreen ? 0 : 16) {
                if let stream = viewStore.currentItem?.stream {
                    let options = makeOptions(
                        for: stream,
                        selectedAudioTrackID: viewStore.selectedAudioTrackID,
                        allowAutoPlay: shouldAllowAutoPlay(
                            viewStore: viewStore,
                            isSubtitleRendererReady: isSubtitleRendererReady
                        )
                    )
                    let customSubtitleDocument = makeCustomSubtitleDocument(
                        from: viewStore.activeSubtitle,
                        isSuppressed: viewStore.areSubtitlesSuppressed
                    )
                    if isFullscreen {
                        playerStage(
                            viewStore: viewStore,
                            stream: stream,
                            options: options,
                            customSubtitleDocument: customSubtitleDocument
                        )
                    } else {
                        HStack(alignment: .top, spacing: 18) {
                            playerStage(
                                viewStore: viewStore,
                                stream: stream,
                                options: options,
                                customSubtitleDocument: customSubtitleDocument
                            )
                            .frame(maxWidth: .infinity)

                            episodeSidebar(viewStore: viewStore)
                                .frame(width: 300)
                        }
                    }
                } else {
                    Text("暂无可播放内容。")
                        .foregroundStyle(.secondary)
                }
                
                if !isFullscreen, let error = viewStore.subtitleError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if !isFullscreen, let playbackError = viewStore.playbackError, !playbackError.isEmpty {
                    Text(playbackError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(isFullscreen ? 0 : 16)
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
                        case .playing, .completed:
                            viewStore.send(.setPlaybackError(nil))
                        case .buffering, .preparing, .paused, .stopped, .idle:
                            break
                        }
                    }
                    .onFinish { error in
                        if let error {
                            viewStore.send(.setPlaybackError(error.localizedDescription))
                        }
                    }
                    .onTracksChanged { tracks in
                        guard let fileID = viewStore.currentFileID else { return }
                        viewStore.send(.playerTracksChanged(fileID, tracks))
                    }
                SubtitleRendererOverlay(
                    document: customSubtitleDocument,
                    playbackTime: playerController.timeline.currentTime,
                    onReadinessChanged: { ready in
                        isSubtitleRendererReady = ready
                    }
                )
                .frame(width: subtitleViewportSize.width, height: subtitleViewportSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                playbackControlBar(viewStore: viewStore)
                    .opacity(isControlBarVisible ? 1 : 0)
                    .offset(y: isControlBarVisible ? 0 : 28)
                    .scaleEffect(isControlBarVisible ? 1 : 0.97, anchor: .bottom)
                    .allowsHitTesting(isControlBarVisible)
#if os(macOS)
                PlayerWindowObserver(
                    onWindowChanged: { window in
                        observedWindow = window
                        isFullscreen = window?.styleMask.contains(.fullScreen) ?? false
                        updateWindowToolbarVisibility()
                        scheduleControlBarVisibilityUpdate()
                    },
                    onFullscreenChanged: { fullscreen in
                        isFullscreen = fullscreen
                        updateWindowToolbarVisibility()
                        if !fullscreen {
                            cancelFullscreenPointerTasks()
                            showCursorIfNeeded()
                        }
                        revealControls()
                    }
                )
                .frame(width: 0, height: 0)
#endif
            }
        }
        .frame(minHeight: 240, maxHeight: isFullscreen ? .infinity : nil)
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
                if isFullscreen {
                    scheduleFullscreenHideCountdown()
                } else {
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
            scrubPosition = 0
            isScrubbing = false
            isSubtitleRendererReady = false
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
        .onDisappear {
            playerController.reset()
            scrubPosition = 0
            isScrubbing = false
            isSubtitleRendererReady = false
            lastPointerLocation = nil
            cancelFullscreenPointerTasks()
            isFullscreen = false
            updateWindowToolbarVisibility()
            showCursorIfNeeded()
        }
    }
    
    private func currentTitle(for episode: Components.Schemas.LibraryBangumiEpisode) -> String {
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
    
    @ViewBuilder
    private func playbackControlBar(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        let duration = max(playerController.timeline.duration ?? 0, 0)
        let effectiveDuration = max(duration, 1)
        let displayedTime = isScrubbing ? scrubPosition : min(playerController.timeline.currentTime, effectiveDuration)

        VStack(spacing: 10) {
            if let current = viewStore.currentItem {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentTitle(for: current.episode))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)
                    Text(current.file.name ?? "未知文件")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                    Text(current.stream.url.absoluteString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 52, alignment: .leading)

                HStack(spacing: 8) {
                    glassIconButton("backward.end.alt", isDisabled: viewStore.currentIndex == 0) {
                        viewStore.send(.playPrevious)
                    }
                    glassIconButton("gobackward.10") {
                        playerController.seekBy(-10)
                    }
                    glassIconButton(playerController.isPlaying ? "pause.fill" : "play.fill") {
                        playerController.togglePlayPause()
                    }
                    glassIconButton("goforward.10") {
                        playerController.seekBy(10)
                    }
                    glassIconButton("forward.end.alt", isDisabled: viewStore.currentIndex + 1 >= viewStore.playlist.count) {
                        viewStore.send(.playNext)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if isFullscreen {
                        episodeMenu(viewStore: viewStore)
                    }
                    speedMenu()
                    audioMenu(viewStore: viewStore)
                    subtitleMenu(viewStore: viewStore)
#if os(macOS)
                    glassIconButton(
                        isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                    ) {
                        observedWindow?.toggleFullScreen(nil)
                    }
#endif
                }

                Text(formatPlaybackTime(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 760)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
#if os(macOS)
        .onHover { inside in
            isPointerInsideControls = inside
            if isFullscreen {
                if inside {
                    cancelFullscreenPointerTasks()
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
    private func speedMenu() -> some View {
        Button {
            isSpeedPopoverPresented.toggle()
            revealControls()
        } label: {
            glassCapsuleLabel(
                title: playbackRateTitle(playerController.playbackRate),
                systemImage: "gauge.with.dots.needle.50percent"
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
                        if abs(playerController.playbackRate - rate) < 0.001 {
                            Label(playbackRateTitle(rate), systemImage: "checkmark")
                        } else {
                            Text(playbackRateTitle(rate))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(minWidth: 120, alignment: .leading)
        }
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(viewStore.playlist) { item in
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
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .frame(width: 280, height: min(CGFloat(max(viewStore.playlist.count, 1)) * 54, 320))
        }
    }

    @ViewBuilder
    private func episodeSidebar(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("选集")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewStore.playlist) { item in
                        Button {
                            viewStore.send(.playItem(item.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentTitle(for: item.episode))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(item.file.name ?? "未知文件")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        viewStore.currentItem?.id == item.id
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.white.opacity(0.06)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        viewStore.currentItem?.id == item.id
                                        ? Color.accentColor.opacity(0.6)
                                        : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func audioMenu(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        Button {
            isAudioPopoverPresented.toggle()
            revealControls()
        } label: {
            glassCapsuleLabel(
                title: selectedAudioTrackTitle(
                    tracks: viewStore.availableAudioTracks,
                    selectedAudioTrackID: viewStore.selectedAudioTrackID
                ),
                systemImage: "waveform"
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isAudioPopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: {
                    viewStore.send(.audioTrackSelected(nil))
                    isAudioPopoverPresented = false
                }) {
                    selectionRowLabel(title: "自动选择", subtitle: nil, isSelected: viewStore.selectedAudioTrackID == nil)
                }
                .buttonStyle(.plain)
                ForEach(viewStore.availableAudioTracks) { track in
                    Button {
                        viewStore.send(.audioTrackSelected(track.id))
                        isAudioPopoverPresented = false
                    } label: {
                        selectionRowLabel(title: track.displayName, subtitle: track.language, isSelected: viewStore.selectedAudioTrackID == track.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(minWidth: 180, alignment: .leading)
        }
    }

    @ViewBuilder
    private func subtitleMenu(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        Button {
            isSubtitlePopoverPresented.toggle()
            revealControls()
        } label: {
            glassCapsuleLabel(
                title: subtitleMenuTitle(
                    externalSubtitle: selectedExternalSubtitleTitle(viewStore: viewStore),
                    embeddedSubtitle: viewStore.selectedEmbeddedSubtitle?.displayName,
                    isSuppressed: viewStore.areSubtitlesSuppressed
                ),
                systemImage: "captions.bubble"
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isSubtitlePopoverPresented, arrowEdge: .bottom) {
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
                .buttonStyle(.plain)

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
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
            .frame(minWidth: 220, alignment: .leading)
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
        isAudioPopoverPresented || isSubtitlePopoverPresented || isSpeedPopoverPresented || isEpisodePopoverPresented
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
        defer { lastPointerLocation = location }
        guard let lastPointerLocation else { return true }
        return abs(location.x - lastPointerLocation.x) > 0.5
            || abs(location.y - lastPointerLocation.y) > 0.5
    }

    private func revealControls() {
        cancelControlBarAutoHide()
        showCursorIfNeeded()
        guard !isControlBarVisible else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            isControlBarVisible = true
        }
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
        if isFullscreen {
            if isAnyControlPopoverPresented || isPointerInsideControls {
                cancelPointerSettleTask()
                revealControlsIfNeeded()
                return
            }
            scheduleFullscreenHideCountdown()
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
            let delay: Duration = isFullscreen ? .seconds(3) : .seconds(2)
            try? await Task.sleep(for: delay)
#if os(macOS)
            let stillEligible: Bool
            if isFullscreen {
                stillEligible = !isPointerInsideControls && !isAnyControlPopoverPresented
            } else {
                stillEligible = !isPointerInsidePlayer && !isAnyControlPopoverPresented
            }
#else
            let stillEligible = false
#endif
            guard stillEligible else { return }
            if isFullscreen {
                hideCursorIfNeeded()
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                isControlBarVisible = false
            }
        }
    }

    private func handlePlayerPointerMovement() {
        if isFullscreen {
            if isCursorHidden {
                showCursorIfNeeded()
            }
            if !isControlBarVisible {
                revealControls()
            } else {
                cancelControlBarAutoHide()
            }
            cancelPointerSettleTask()
            pointerSettleTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                pointerSettleTask = nil
                guard isFullscreen,
                      !isPointerInsideControls,
                      !isAnyControlPopoverPresented else { return }
                scheduleFullscreenHideCountdown()
            }
            return
        }
        revealControlsIfNeeded()
        scheduleControlBarVisibilityUpdate()
    }

    private func cancelControlBarAutoHide() {
        hideControlsTask?.cancel()
        hideControlsTask = nil
    }

    private func cancelPointerSettleTask() {
        pointerSettleTask?.cancel()
        pointerSettleTask = nil
    }

    private func cancelFullscreenPointerTasks() {
        cancelPointerSettleTask()
        cancelControlBarAutoHide()
    }

    private func scheduleFullscreenHideCountdown() {
        cancelControlBarAutoHide()
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard isFullscreen,
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
        observedWindow?.toolbar?.isVisible = !isFullscreen
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

private func makeOptions(
    for stream: RemoteMediaLibraryClient.StreamContext,
    selectedAudioTrackID: String?,
    allowAutoPlay: Bool
) -> PlayerLoadOptions {
    PlayerLoadOptions(
        headers: stream.headers,
        enableHardwareDecoding: true,
        allowAutoPlay: allowAutoPlay,
        selectedAudioTrackID: selectedAudioTrackID
    )
}

@MainActor
private func shouldAllowAutoPlay(
    viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>,
    isSubtitleRendererReady: Bool
) -> Bool {
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
            .frame(width: 34, height: 34)
            .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .background(
        Circle()
            .fill(.white.opacity(0.14))
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
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
        Capsule(style: .continuous)
            .fill(.white.opacity(0.12))
    )
}

private func playbackRateTitle(_ rate: Double) -> String {
    if abs(rate.rounded() - rate) < 0.001 {
        return "\(Int(rate.rounded()))x"
    }
    return String(format: "%.2fx", rate)
}

@MainActor
@ViewBuilder
private func selectionRowLabel(title: String, subtitle: String?, isSelected: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 14)
            .opacity(isSelected ? 1 : 0)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
}

#if os(macOS)
private struct PlayerWindowObserver: NSViewRepresentable {
    let onWindowChanged: (NSWindow?) -> Void
    let onFullscreenChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowChanged: onWindowChanged, onFullscreenChanged: onFullscreenChanged)
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

    @MainActor
    final class Coordinator: NSObject {
        private let onWindowChanged: (NSWindow?) -> Void
        private let onFullscreenChanged: (Bool) -> Void
        private weak var observedWindow: NSWindow?
        private var notificationTokens: [NSObjectProtocol] = []

        init(
            onWindowChanged: @escaping (NSWindow?) -> Void,
            onFullscreenChanged: @escaping (Bool) -> Void
        ) {
            self.onWindowChanged = onWindowChanged
            self.onFullscreenChanged = onFullscreenChanged
        }

        @MainActor
        func refresh(for window: NSWindow?) {
            guard observedWindow !== window else { return }
            notificationTokens.forEach(NotificationCenter.default.removeObserver)
            notificationTokens.removeAll()
            observedWindow = window
            onWindowChanged(window)
            onFullscreenChanged(window?.styleMask.contains(.fullScreen) ?? false)

            guard let window else { return }
            notificationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didEnterFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.onFullscreenChanged(true)
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
                        self?.onFullscreenChanged(false)
                    }
                }
            )
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
