import Foundation
import ComposableArchitecture
import IdentifiedCollections
import RemoteMediaLibrary

@Reducer
struct PlayerPresenter {
    @Dependency(\.remoteMediaLibraryClient) var remoteClient
    @Dependency(\.uuid) var uuid

    private enum CancelID { case playbackSync }

    @ObservableState
    struct State: Equatable, Identifiable {
        typealias PlaylistItem = PlaybackItem
        struct FileSelection: Equatable, Identifiable {
            let id = UUID()
            let episode: Components.Schemas.LibraryBangumiEpisode
            let files: [Components.Schemas.LibraryBangumiMatchedFile]
        }

        let id: UUID
        let configuration: MediaLibraryConfiguration
        let seriesTitle: String?
        let coverURL: URL?
        var playlist: IdentifiedArrayOf<PlaybackItem>
        var currentIndex: Int
        let allEpisodeFiles: [Components.Schemas.LibraryBangumiEpisode: [Components.Schemas.LibraryBangumiMatchedFile]]
        var subtitles: PlayerSubtitlesPresenter.State
        var danmaku: PlayerDanmakuPresenter.State
        var availableAudioTracks: [PlayerTrack] = []
        var selectedAudioTrackID: PlayerTrack.ID?
        var fileSelection: FileSelection?
        var playbackError: String?
        var hasTriggeredPlaybackStartSync = false
        var shouldAutoPlayCurrentEntry = true
        var playbackContextID: UUID

        init(request: PlaybackRequest) {
            id = request.id
            playbackContextID = request.id
            configuration = request.configuration
            seriesTitle = request.seriesTitle
            coverURL = request.coverURL
            playlist = IdentifiedArray(uniqueElements: request.playlist)
            let initialIndex = request.playlist.indices.contains(request.currentIndex) ? request.currentIndex : 0
            currentIndex = initialIndex
            allEpisodeFiles = request.allEpisodeFiles
            let context = PlaybackAttachmentContext(
                id: request.id,
                configuration: request.configuration,
                item: request.playlist.indices.contains(initialIndex) ? request.playlist[initialIndex] : nil
            )
            subtitles = .init(context: context)
            danmaku = .init(context: context)
        }

        var currentItem: PlaybackItem? {
            guard playlist.indices.contains(currentIndex) else { return nil }
            return playlist[currentIndex]
        }
        var currentFileID: String? { currentItem?.file.id }
    }

    enum Action: Equatable {
        case onAppear
        case stop
        case playItem(PlaybackItem.ID)
        case playNext
        case playPrevious
        case updateCurrentIndex(Int)
        case playbackStarted
        case playerTracksChanged([PlayerTrack])
        case audioTrackSelected(PlayerTrack.ID?)
        case showFilePicker
        case fileSelectionDismissed
        case fileSelected(Components.Schemas.LibraryBangumiMatchedFile)
        case streamContextResolved(Components.Schemas.LibraryBangumiMatchedFile, RemoteMediaLibraryClient.StreamContext)
        case setPlaybackError(String?)
        case setCurrentEntryAutoPlay(Bool)
        case subtitles(PlayerSubtitlesPresenter.Action)
        case danmaku(PlayerDanmakuPresenter.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.subtitles, action: \.subtitles) { PlayerSubtitlesPresenter() }
        Scope(state: \.danmaku, action: \.danmaku) { PlayerDanmakuPresenter() }
        Reduce { state, action in
            switch action {
            case .onAppear:
                return loadAttachments
            case .stop:
                return .concatenate(
                    .cancel(id: CancelID.playbackSync),
                    .send(.subtitles(.stop)),
                    .send(.danmaku(.stop))
                )
            case let .playerTracksChanged(tracks):
                let audioTracks = tracks.filter { $0.kind == .audio }
                state.availableAudioTracks = audioTracks
                if let selected = audioTracks.first(where: \.isSelected) {
                    state.selectedAudioTrackID = selected.id
                } else if let id = state.selectedAudioTrackID, !audioTracks.contains(where: { $0.id == id }) {
                    state.selectedAudioTrackID = nil
                }
                return .send(.subtitles(.playerTracksChanged(tracks)))
            case let .playItem(id):
                guard let index = state.playlist.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                debugLogPlayerFlow(
                    "playItem targetIndex=\(index) currentIndex=\(state.currentIndex) targetPlaylistItemID=\(id)"
                )
                state.currentIndex = index
                state.shouldAutoPlayCurrentEntry = true
                state.playbackError = nil
                return prepareAttachments(for: &state)

            case .playNext:
                guard !state.playlist.isEmpty else { return .none }
                guard state.currentIndex + 1 < state.playlist.count else { return .none }
                debugLogPlayerFlow(
                    "playNext fromIndex=\(state.currentIndex) toIndex=\(state.currentIndex + 1)"
                )
                state.currentIndex += 1
                state.shouldAutoPlayCurrentEntry = true
                state.playbackError = nil
                return prepareAttachments(for: &state)

            case .playPrevious:
                guard !state.playlist.isEmpty else { return .none }
                guard state.currentIndex > 0 else { return .none }
                debugLogPlayerFlow(
                    "playPrevious fromIndex=\(state.currentIndex) toIndex=\(state.currentIndex - 1)"
                )
                state.currentIndex -= 1
                state.shouldAutoPlayCurrentEntry = true
                state.playbackError = nil
                return prepareAttachments(for: &state)

            case let .updateCurrentIndex(index):
                guard state.playlist.indices.contains(index) else { return .none }
                if state.currentIndex == index {
                    state.shouldAutoPlayCurrentEntry = true
                    debugLogPlayerFlow(
                        "updateCurrentIndex unchanged index=\(index) fileID=\(state.currentFileID ?? "<none>")"
                    )
                    return .none
                }
                debugLogPlayerFlow(
                    "updateCurrentIndex from=\(state.currentIndex) to=\(index) currentFileID=\(state.currentFileID ?? "<none>") nextFileID=\(state.playlist[index].file.id ?? "<none>")"
                )
                state.currentIndex = index
                state.shouldAutoPlayCurrentEntry = true
                state.playbackError = nil
                return prepareAttachments(for: &state)

            case .playbackStarted:
                debugLogPlayerFlow(
                    "playbackStarted currentIndex=\(state.currentIndex) fileID=\(state.currentFileID ?? "<none>") hasTriggeredSync=\(state.hasTriggeredPlaybackStartSync)"
                )
                guard !state.hasTriggeredPlaybackStartSync,
                      let fileID = state.currentFileID,
                      let baseURL = state.configuration.baseURL else {
                    debugLogPlayerFlow(
                        "playbackStarted ignored fileID=\(state.currentFileID ?? "<none>") hasTriggeredSync=\(state.hasTriggeredPlaybackStartSync) hasBaseURL=\(state.configuration.baseURL != nil)"
                    )
                    return .none
                }
                state.hasTriggeredPlaybackStartSync = true
                let token = state.configuration.apiToken
                debugLogPlayerFlow(
                    "playbackStarted sync begin fileID=\(fileID) baseURL=\(baseURL.absoluteString)"
                )
                return .run { [remoteClient] _ in
                    do {
                        _ = try await remoteClient.makeStreamContext(baseURL, token, fileID)
                        debugLogPlayerFlow("playbackStarted sync success fileID=\(fileID)")
                    } catch {
#if DEBUG
                        print("[PlayerPresenter] Playback start sync failed for \(fileID): \(error)")
#endif
                    }
                }
                .cancellable(id: CancelID.playbackSync, cancelInFlight: true)

            case let .audioTrackSelected(trackID):
                state.selectedAudioTrackID = trackID
                return .none

            case .showFilePicker:
                guard let currentItem = state.currentItem,
                      let files = state.allEpisodeFiles[currentItem.episode],
                      !files.isEmpty else {
                    return .none
                }
                state.fileSelection = .init(episode: currentItem.episode, files: files)
                return .none

            case .fileSelectionDismissed:
                state.fileSelection = nil
                return .none

            case let .fileSelected(file):
                guard state.playlist.indices.contains(state.currentIndex) else {
                    return .none
                }
                guard let baseURL = state.configuration.baseURL else {
                    state.playbackError = "媒体库地址无效。"
                    return .none
                }
                guard let fileID = file.id, !fileID.isEmpty else {
                    state.playbackError = "选定的文件缺少标识符。"
                    return .none
                }
                let token = state.configuration.apiToken
                let stream = remoteClient.makeDirectStreamContext(baseURL, token, fileID)
                return .send(.streamContextResolved(file, stream))

            case let .streamContextResolved(file, stream):
                guard state.playlist.indices.contains(state.currentIndex) else {
                    return .none
                }
                state.playlist[state.currentIndex].file = file
                state.playlist[state.currentIndex].stream = stream
                state.shouldAutoPlayCurrentEntry = true
                state.fileSelection = nil
                state.playbackError = nil
                return prepareAttachments(for: &state)

            case let .setPlaybackError(message):
                state.playbackError = message
                return .none

            case let .setCurrentEntryAutoPlay(enabled):
                state.shouldAutoPlayCurrentEntry = enabled
                return .none
            case .subtitles, .danmaku:
                return .none
            }
        }
    }

    private var loadAttachments: Effect<Action> {
        .concatenate(.send(.subtitles(.load)), .send(.danmaku(.load)))
    }

    private func prepareAttachments(for state: inout State) -> Effect<Action> {
        state.playbackContextID = uuid()
        state.hasTriggeredPlaybackStartSync = false
        state.availableAudioTracks = []
        state.selectedAudioTrackID = nil
        let context = PlaybackAttachmentContext(
            id: state.playbackContextID, configuration: state.configuration, item: state.currentItem
        )
        state.subtitles = .init(context: context)
        state.danmaku = .init(context: context)
        return .concatenate(
            .cancel(id: CancelID.playbackSync),
            .send(.subtitles(.stop)),
            .send(.danmaku(.stop)),
            loadAttachments
        )
    }
}

private func debugLogPlayerFlow(_ message: @autoclosure () -> String) {
#if DEBUG
    print("[PlayerPresenter][Flow] \(message())")
#endif
}
