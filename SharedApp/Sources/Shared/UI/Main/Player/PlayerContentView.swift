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
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: 16) {
                if let stream = viewStore.currentItem?.stream {
                    let options = makeOptions(
                        for: stream,
                        selectedAudioTrackID: viewStore.selectedAudioTrackID
                    )
                    let customSubtitleDocument = makeCustomSubtitleDocument(
                        from: viewStore.activeSubtitle,
                        isSuppressed: viewStore.areSubtitlesSuppressed
                    )
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
                            playbackTime: playerController.timeline.currentTime
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                        playbackControlBar(viewStore: viewStore)
                    }
                        .frame(minHeight: 240)
                        .onAppear {
                            viewStore.send(.onAppear)
                            viewStore.send(.setPlaybackError(nil))
                        }
                        .onChange(of: viewStore.currentItem?.stream) { _, newStream in
                            guard newStream != nil else { return }
                            playerController.reset()
                            scrubPosition = 0
                            isScrubbing = false
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
                        }
                } else {
                    Text("暂无可播放内容。")
                        .foregroundStyle(.secondary)
                }
                
                metadataSection(viewStore: viewStore)
                controlsSection(viewStore: viewStore)
                playlistSection(viewStore: viewStore)
                
                if let error = viewStore.subtitleError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if let playbackError = viewStore.playbackError, !playbackError.isEmpty {
                    Text(playbackError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
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
    }
    
    @ViewBuilder
    private func metadataSection(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        if let current = viewStore.currentItem {
            VStack(alignment: .leading, spacing: 6) {
                Text(currentTitle(for: current.episode))
                    .font(.title3)
                    .bold()
                Text(current.stream.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(current.file.name ?? "未知文件")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func currentTitle(for episode: Components.Schemas.LibraryBangumiEpisode) -> String {
        if let number = episode.episodeNumber, let title = episode.displayTitle ?? episode.episodeTitle {
            return "#\(number) \(title)"
        }
        if let title = episode.displayTitle ?? episode.episodeTitle {
            return title
        }
        return "未命名剧集"
    }
    
    @ViewBuilder
    private func controlsSection(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        HStack(spacing: 16) {
            Button {
                viewStore.send(.playPrevious)
            } label: {
                Label("上一集", systemImage: "backward.end.alt")
            }
            .disabled(viewStore.currentIndex == 0)
            
            Button {
                viewStore.send(.showFilePicker)
            } label: {
                Label("切换匹配文件", systemImage: "rectangle.stack.badge.play")
            }
            .disabled(viewStore.currentItem == nil)
            
            Button {
                viewStore.send(.playNext)
            } label: {
                Label("下一集", systemImage: "forward.end.alt")
            }
            .disabled(viewStore.currentIndex + 1 >= viewStore.playlist.count)
        }
    }
    
    @ViewBuilder
    private func playbackControlBar(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        let duration = max(playerController.timeline.duration ?? 0, 0)
        let effectiveDuration = max(duration, 1)
        let displayedTime = isScrubbing ? scrubPosition : min(playerController.timeline.currentTime, effectiveDuration)

        VStack(spacing: 10) {
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
                    glassIconButton("gobackward.10") {
                        playerController.seekBy(-10)
                    }
                    glassIconButton(playerController.isPlaying ? "pause.fill" : "play.fill") {
                        playerController.togglePlayPause()
                    }
                    glassIconButton("goforward.10") {
                        playerController.seekBy(10)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    audioMenu(viewStore: viewStore)
                    subtitleMenu(viewStore: viewStore)
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
    }

    @ViewBuilder
    private func audioMenu(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        Menu {
            Button("自动选择") {
                viewStore.send(.audioTrackSelected(nil))
            }
            ForEach(viewStore.availableAudioTracks) { track in
                Button {
                    viewStore.send(.audioTrackSelected(track.id))
                } label: {
                    if viewStore.selectedAudioTrackID == track.id {
                        Label(track.displayName, systemImage: "checkmark")
                    } else {
                        Text(track.displayName)
                    }
                }
            }
        } label: {
            glassCapsuleLabel(
                title: selectedAudioTrackTitle(
                    tracks: viewStore.availableAudioTracks,
                    selectedAudioTrackID: viewStore.selectedAudioTrackID
                ),
                systemImage: "waveform"
            )
        }
    }

    @ViewBuilder
    private func subtitleMenu(viewStore: ViewStore<PlayerPresenter.State, PlayerPresenter.Action>) -> some View {
        Menu {
            Button(viewStore.areSubtitlesSuppressed ? "开启字幕" : "关闭字幕") {
                viewStore.send(.setSubtitlesSuppressed(!viewStore.areSubtitlesSuppressed))
            }
            Button("导入本地字幕…") {
                isImportingLocalSubtitle = true
            }
            if !viewStore.areSubtitlesSuppressed,
               (viewStore.availableSubtitles.isEmpty == false || viewStore.availableEmbeddedSubtitles.isEmpty == false) {
                Divider()
            }
            if viewStore.availableSubtitles.isEmpty,
               viewStore.availableEmbeddedSubtitles.isEmpty {
                Text("暂无字幕").disabled(true)
            } else if !viewStore.areSubtitlesSuppressed {
                if !viewStore.availableSubtitles.isEmpty {
                    if !viewStore.availableEmbeddedSubtitles.isEmpty {
                        Text("外挂字幕").disabled(true)
                    }
                    ForEach(viewStore.availableSubtitles) { subtitle in
                        Button {
                            viewStore.send(.subtitleSelected(subtitle))
                        } label: {
                            if viewStore.selectedSubtitle?.id == subtitle.id {
                                Label(subtitle.fileName, systemImage: "checkmark")
                            } else {
                                Text(subtitle.fileName)
                            }
                        }
                    }
                }
                if !viewStore.availableEmbeddedSubtitles.isEmpty {
                    if !viewStore.availableSubtitles.isEmpty {
                        Divider()
                    }
                    if !viewStore.availableSubtitles.isEmpty {
                        Text("内嵌字幕").disabled(true)
                    }
                    ForEach(viewStore.availableEmbeddedSubtitles) { subtitle in
                        Button {
                            viewStore.send(.embeddedSubtitleSelected(subtitle.id))
                        } label: {
                            if viewStore.selectedEmbeddedSubtitleTrackID == subtitle.id,
                               viewStore.selectedSubtitle == nil {
                                Label(subtitle.displayName, systemImage: "checkmark")
                            } else {
                                Text(subtitle.displayName)
                            }
                        }
                    }
                }
            }
        } label: {
            glassCapsuleLabel(
                title: subtitleMenuTitle(
                    externalSubtitle: viewStore.selectedSubtitle?.fileName ?? viewStore.activeSubtitle?.fileName,
                    embeddedSubtitle: viewStore.selectedEmbeddedSubtitle?.displayName,
                    isSuppressed: viewStore.areSubtitlesSuppressed
                ),
                systemImage: "captions.bubble"
            )
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
    selectedAudioTrackID: String?
) -> PlayerLoadOptions {
    PlayerLoadOptions(
        headers: stream.headers,
        enableHardwareDecoding: true,
        allowAutoPlay: true,
        selectedAudioTrackID: selectedAudioTrackID
    )
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

@ViewBuilder
private func glassIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
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
}

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
