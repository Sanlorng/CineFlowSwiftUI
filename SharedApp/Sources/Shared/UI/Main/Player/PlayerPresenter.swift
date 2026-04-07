//
//  PlayerPresenter.swift
//  CineFlowPackage
//
//  Created by Codex on 2025/10/24.
//

import Foundation
import ComposableArchitecture
import IdentifiedCollections
import RemoteMediaLibrary
import SubtitleRendererCore

@Reducer
struct PlayerPresenter {
    
    @Dependency(\.remoteMediaLibraryClient) var remoteClient
    
    @ObservableState
    struct State: Equatable {
        
        struct PlaylistItem: Equatable, Identifiable {
            let id: UUID
            let episode: Components.Schemas.LibraryBangumiEpisode
            var file: Components.Schemas.LibraryBangumiMatchedFile
            var stream: RemoteMediaLibraryClient.StreamContext
            
            init(
                id: UUID = UUID(),
                episode: Components.Schemas.LibraryBangumiEpisode,
                file: Components.Schemas.LibraryBangumiMatchedFile,
                stream: RemoteMediaLibraryClient.StreamContext
            ) {
                self.id = id
                self.episode = episode
                self.file = file
                self.stream = stream
            }
        }
        
        struct FileSelection: Equatable, Identifiable {
            let id = UUID()
            let episode: Components.Schemas.LibraryBangumiEpisode
            let files: [Components.Schemas.LibraryBangumiMatchedFile]
        }

        struct LoadedSubtitle: Equatable, Sendable {
            let fileName: String
            let document: SubtitleDocument
        }

        struct LoadedDanmaku: Equatable, Sendable {
            let id = UUID()
            let payload: DanmakuPayload

            static func == (lhs: LoadedDanmaku, rhs: LoadedDanmaku) -> Bool {
                lhs.id == rhs.id
            }
        }

        struct EmbeddedSubtitleWindowRequest: Equatable {
            let requestID: UUID
            let trackID: SubtitleTrack.ID
            let window: ClosedRange<TimeInterval>
        }
        
        let configuration: LibraryPresenter.State.Configuration
        let seriesTitle: String?
        let coverURL: URL?
        var playlist: IdentifiedArrayOf<PlaylistItem>
        var currentIndex: Int
        let allEpisodeFiles: [Components.Schemas.LibraryBangumiEpisode: [Components.Schemas.LibraryBangumiMatchedFile]]
        
        var isLoadingSubtitles = false
        var isLoadingEmbeddedSubtitles = false
        var availableSubtitles: [RemoteMediaLibraryClient.Subtitle] = []
        var availableEmbeddedSubtitles: [SubtitleTrack] = []
        var availableAudioTracks: [PlayerTrack] = []
        var selectedAudioTrackID: PlayerTrack.ID?
        var selectedSubtitle: RemoteMediaLibraryClient.Subtitle?
        var selectedEmbeddedSubtitleTrackID: SubtitleTrack.ID?
        var subtitleError: String?
        var activeSubtitle: LoadedSubtitle?
        var fileSelection: FileSelection?
        var playbackError: String?
        var areSubtitlesSuppressed = false
        var isLoadingSelectedSubtitle = false
        var isLoadingDanmaku = false
        var danmakuError: String?
        var activeDanmaku: LoadedDanmaku?
        var hasTriggeredPlaybackStartSync = false
        var currentPlaybackTime: TimeInterval = 0
        var loadedEmbeddedSubtitleWindow: ClosedRange<TimeInterval>?
        var inFlightEmbeddedSubtitleWindowRequest: EmbeddedSubtitleWindowRequest?
        
        init(
            configuration: LibraryPresenter.State.Configuration,
            seriesTitle: String? = nil,
            coverURL: URL? = nil,
            playlist: [PlaylistItem],
            currentIndex: Int,
            allEpisodeFiles: [Components.Schemas.LibraryBangumiEpisode: [Components.Schemas.LibraryBangumiMatchedFile]]
        ) {
            self.configuration = configuration
            self.seriesTitle = seriesTitle
            self.coverURL = coverURL
            self.playlist = IdentifiedArray(uniqueElements: playlist)
            self.currentIndex = playlist.indices.contains(currentIndex) ? currentIndex : 0
            self.allEpisodeFiles = allEpisodeFiles
        }
        
        var currentItem: PlaylistItem? {
            guard playlist.indices.contains(currentIndex) else { return nil }
            return playlist[currentIndex]
        }

        var currentFileID: String? {
            currentItem?.file.id
        }

        var selectedEmbeddedSubtitle: SubtitleTrack? {
            guard let selectedEmbeddedSubtitleTrackID else { return nil }
            return availableEmbeddedSubtitles.first { $0.id == selectedEmbeddedSubtitleTrackID }
        }
    }
    
    enum Action: Equatable {
        case onAppear
        case playItem(PlayerPresenter.State.PlaylistItem.ID)
        case playNext
        case playPrevious
        case updateCurrentIndex(Int)
        case playbackStarted(String)
        case playbackTimeUpdated(String, TimeInterval)
        case playerTracksChanged(String, [PlayerTrack])
        case audioTrackSelected(PlayerTrack.ID?)
        case subtitleListResponse(String, TaskResult<[RemoteMediaLibraryClient.Subtitle]>)
        case embeddedSubtitleTracksResponse(String, TaskResult<[SubtitleTrack]>)
        case subtitleSelected(RemoteMediaLibraryClient.Subtitle)
        case subtitleContentResponse(String, RemoteMediaLibraryClient.Subtitle, TaskResult<State.LoadedSubtitle>)
        case localSubtitleLoaded(fileName: String, content: String)
        case localSubtitleLoadFailed(String)
        case embeddedSubtitleSelected(SubtitleTrack.ID)
        case embeddedSubtitleContentResponse(String, SubtitleTrack.ID, UUID, ClosedRange<TimeInterval>, TaskResult<State.LoadedSubtitle>)
        case danmakuResponse(String, TaskResult<State.LoadedDanmaku>)
        case subtitleCleared
        case setSubtitlesSuppressed(Bool)
        case showFilePicker
        case fileSelectionDismissed
        case fileSelected(Components.Schemas.LibraryBangumiMatchedFile)
        case streamContextResolved(Components.Schemas.LibraryBangumiMatchedFile, RemoteMediaLibraryClient.StreamContext)
        case setPlaybackError(String?)
        case delegate(DelegateAction)
    }
    
    enum DelegateAction: Equatable {}
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return loadSubtitles(for: &state)
                
            case let .playItem(id):
                guard let index = state.playlist.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                state.currentIndex = index
                state.playbackError = nil
                return loadSubtitles(for: &state)
                
            case .playNext:
                guard !state.playlist.isEmpty else { return .none }
                guard state.currentIndex + 1 < state.playlist.count else { return .none }
                state.currentIndex += 1
                state.playbackError = nil
                return loadSubtitles(for: &state)
                
            case .playPrevious:
                guard !state.playlist.isEmpty else { return .none }
                guard state.currentIndex > 0 else { return .none }
                state.currentIndex -= 1
                state.playbackError = nil
                return loadSubtitles(for: &state)
                
            case let .updateCurrentIndex(index):
                guard state.playlist.indices.contains(index) else { return .none }
                if state.currentIndex == index { return .none }
                state.currentIndex = index
                state.playbackError = nil
                return loadSubtitles(for: &state)

            case let .playbackStarted(fileID):
                guard state.currentFileID == fileID,
                      !state.hasTriggeredPlaybackStartSync,
                      let baseURL = state.configuration.baseURL else {
                    return .none
                }
                state.hasTriggeredPlaybackStartSync = true
                let token = state.configuration.apiToken
                return .run { [remoteClient] _ in
                    do {
                        _ = try await remoteClient.makeStreamContext(baseURL, token, fileID)
                    } catch {
#if DEBUG
                        print("[PlayerPresenter] Playback start sync failed for \(fileID): \(error)")
#endif
                    }
                }

            case let .playbackTimeUpdated(fileID, playbackTime):
                guard state.currentFileID == fileID else { return .none }
                state.currentPlaybackTime = max(playbackTime, 0)
                return refreshEmbeddedSubtitleWindowIfNeeded(for: &state, fileID: fileID, force: false)

            case let .playerTracksChanged(fileID, tracks):
                guard state.currentFileID == fileID else { return .none }
                state.isLoadingEmbeddedSubtitles = false
                let audioTracks = tracks.filter { $0.kind == .audio }
                state.availableAudioTracks = audioTracks
                if let selectedAudioTrack = audioTracks.first(where: \.isSelected) {
                    state.selectedAudioTrackID = selectedAudioTrack.id
                } else if let selectedAudioTrackID = state.selectedAudioTrackID,
                          audioTracks.contains(where: { $0.id == selectedAudioTrackID }) == false {
                    state.selectedAudioTrackID = nil
                }
                let backendSubtitleTracks = tracks
                    .filter { $0.kind == .subtitle && !$0.isExternal }
                    .compactMap(makeEmbeddedSubtitleTrack(from:))
                state.availableEmbeddedSubtitles = mergeEmbeddedSubtitleTracks(
                    existing: state.availableEmbeddedSubtitles,
                    incoming: backendSubtitleTracks,
                    preferIncoming: false
                )
                if !backendSubtitleTracks.isEmpty {
                    debugLogEmbeddedSubtitlePlayback(
                        "backend track list updated fileID=\(fileID) count=\(backendSubtitleTracks.count) tracks=[\(describeEmbeddedSubtitleTracks(backendSubtitleTracks))]"
                    )
                }
                if let selectedEmbeddedSubtitleTrackID = state.selectedEmbeddedSubtitleTrackID,
                   state.availableEmbeddedSubtitles.contains(where: { $0.id == selectedEmbeddedSubtitleTrackID }) == false {
                    state.selectedEmbeddedSubtitleTrackID = nil
                }
                return autoSelectSubtitleIfNeeded(for: &state)

            case let .audioTrackSelected(trackID):
                state.selectedAudioTrackID = trackID
                return .none
                
            case let .subtitleListResponse(fileID, .success(subtitles)):
                guard state.currentFileID == fileID else { return .none }
                state.isLoadingSubtitles = false
                state.availableSubtitles = subtitles
                state.subtitleError = nil
                return autoSelectSubtitleIfNeeded(for: &state)
                
            case let .subtitleListResponse(fileID, .failure(error)):
                guard state.currentFileID == fileID else { return .none }
                state.isLoadingSubtitles = false
                state.availableSubtitles = []
                state.subtitleError = error.localizedDescription
                return autoSelectSubtitleIfNeeded(for: &state)

            case let .embeddedSubtitleTracksResponse(fileID, .success(tracks)):
                guard state.currentFileID == fileID else { return .none }
                state.isLoadingEmbeddedSubtitles = false
                state.availableEmbeddedSubtitles = mergeEmbeddedSubtitleTracks(
                    existing: state.availableEmbeddedSubtitles,
                    incoming: tracks,
                    preferIncoming: true
                )
                debugLogEmbeddedSubtitlePlayback(
                    "extractor track list loaded fileID=\(fileID) count=\(tracks.count) tracks=[\(describeEmbeddedSubtitleTracks(tracks))]"
                )
                if let selectedEmbeddedSubtitleTrackID = state.selectedEmbeddedSubtitleTrackID,
                   state.availableEmbeddedSubtitles.contains(where: { $0.id == selectedEmbeddedSubtitleTrackID }) == false {
                    state.selectedEmbeddedSubtitleTrackID = nil
                }
                state.subtitleError = nil
                return autoSelectSubtitleIfNeeded(for: &state)

            case let .embeddedSubtitleTracksResponse(fileID, .failure(error)):
                guard state.currentFileID == fileID else { return .none }
                state.isLoadingEmbeddedSubtitles = false
                state.availableEmbeddedSubtitles = []
                debugLogEmbeddedSubtitlePlayback(
                    "extractor track list failed fileID=\(fileID) error=\(error.localizedDescription)"
                )
                state.subtitleError = error.localizedDescription
                return autoSelectSubtitleIfNeeded(for: &state)
                
            case let .subtitleSelected(subtitle):
                guard let currentItem = state.currentItem,
                      let fileID = currentItem.file.id,
                      !fileID.isEmpty else {
                    return .none
                }
                guard let baseURL = state.configuration.baseURL else {
                    state.subtitleError = "媒体库地址无效。"
                    return .none
                }
                state.areSubtitlesSuppressed = false
                state.selectedSubtitle = subtitle
                state.selectedEmbeddedSubtitleTrackID = nil
                state.subtitleError = nil
                state.activeSubtitle = nil
                state.isLoadingSelectedSubtitle = true
                state.loadedEmbeddedSubtitleWindow = nil
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                let token = state.configuration.apiToken
                return .run { [remoteClient] send in
                    await send(
                        .subtitleContentResponse(
                            fileID,
                            subtitle,
                            TaskResult {
                                let content = try await remoteClient.fetchSubtitleFile(baseURL, token, fileID, subtitle.fileName)
                                return try makeLoadedSubtitle(rawText: content, fileName: subtitle.fileName)
                            }
                        )
                    )
                }

            case let .subtitleContentResponse(fileID, subtitle, .success(loadedSubtitle)):
                guard state.currentFileID == fileID else { return .none }
                state.isLoadingSelectedSubtitle = false
                guard state.selectedSubtitle?.id == subtitle.id else {
                    return .none
                }
                state.subtitleError = nil
                state.activeSubtitle = loadedSubtitle
                return .none

            case let .subtitleContentResponse(fileID, subtitle, .failure(error)):
                guard state.currentFileID == fileID else { return .none }
                state.isLoadingSelectedSubtitle = false
                if state.selectedSubtitle?.id == subtitle.id {
                    state.subtitleError = error.localizedDescription
                    state.activeSubtitle = nil
                }
                return .none

            case let .localSubtitleLoaded(fileName, content):
                state.areSubtitlesSuppressed = false
                state.selectedSubtitle = nil
                state.selectedEmbeddedSubtitleTrackID = nil
                state.subtitleError = nil
                state.isLoadingSelectedSubtitle = false
                state.loadedEmbeddedSubtitleWindow = nil
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                do {
                    state.activeSubtitle = try makeLoadedSubtitle(rawText: content, fileName: fileName)
                } catch {
                    state.activeSubtitle = nil
                    state.subtitleError = error.localizedDescription
                }
                return .none

            case let .localSubtitleLoadFailed(message):
                state.subtitleError = message
                return .none

            case let .embeddedSubtitleSelected(trackID):
                guard state.availableEmbeddedSubtitles.contains(where: { $0.id == trackID }),
                      let currentItem = state.currentItem,
                      let fileID = currentItem.file.id,
                      !fileID.isEmpty else {
                    return .none
                }
                let selectedTrack = state.availableEmbeddedSubtitles.first { $0.id == trackID }
                state.areSubtitlesSuppressed = false
                state.selectedSubtitle = nil
                state.selectedEmbeddedSubtitleTrackID = trackID
                state.subtitleError = nil
                state.activeSubtitle = nil
                state.loadedEmbeddedSubtitleWindow = nil
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                let usesNativeEmbeddedSubtitleSelection =
                    PlayerBackendKind.defaultDistributable.capabilities.contains(.embeddedSubtitleTracks)
                    && selectedTrack?.backendTrackID != nil
                state.isLoadingSelectedSubtitle = !usesNativeEmbeddedSubtitleSelection

                if usesNativeEmbeddedSubtitleSelection {
                    debugLogEmbeddedSubtitlePlayback(
                        "embedded subtitle selected for native backend fileID=\(fileID) trackID=\(trackID) backendTrackID=\(selectedTrack?.backendTrackID ?? "<none>")"
                    )
                    return .none
                }

                debugLogEmbeddedSubtitlePlayback(
                    "embedded subtitle selected fileID=\(fileID) trackID=\(trackID) streamURL=\(currentItem.stream.url.absoluteString)"
                )
                return refreshEmbeddedSubtitleWindowIfNeeded(for: &state, fileID: fileID, force: true)

            case let .embeddedSubtitleContentResponse(fileID, trackID, requestID, window, .success(loadedSubtitle)):
                guard state.currentFileID == fileID else { return .none }
                guard state.selectedEmbeddedSubtitleTrackID == trackID,
                      state.inFlightEmbeddedSubtitleWindowRequest?.requestID == requestID else {
                    return .none
                }
                state.isLoadingSelectedSubtitle = false
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                state.loadedEmbeddedSubtitleWindow = window
                debugLogEmbeddedSubtitlePlayback(
                    "embedded subtitle render attached fileID=\(fileID) trackID=\(trackID) window=\(describeEmbeddedSubtitleWindow(window)) fileName=\(loadedSubtitle.fileName)"
                )
                state.subtitleError = nil
                state.activeSubtitle = loadedSubtitle
                return .none

            case let .embeddedSubtitleContentResponse(fileID, trackID, requestID, window, .failure(error)):
                guard state.currentFileID == fileID else { return .none }
                guard state.selectedEmbeddedSubtitleTrackID == trackID,
                      state.inFlightEmbeddedSubtitleWindowRequest?.requestID == requestID else {
                    return .none
                }
                state.isLoadingSelectedSubtitle = false
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                debugLogEmbeddedSubtitlePlayback(
                    "embedded subtitle render failed fileID=\(fileID) trackID=\(trackID) window=\(describeEmbeddedSubtitleWindow(window)) error=\(error.localizedDescription)"
                )
                state.subtitleError = error.localizedDescription
                state.activeSubtitle = nil
                return .none

            case let .danmakuResponse(fileID, .success(loadedDanmaku)):
                guard state.currentFileID == fileID else { return .none }
                state.isLoadingDanmaku = false
                state.danmakuError = nil
                state.activeDanmaku = loadedDanmaku
                return .none

            case let .danmakuResponse(fileID, .failure(error)):
                guard state.currentFileID == fileID else { return .none }
                state.isLoadingDanmaku = false
                state.danmakuError = error.localizedDescription
                state.activeDanmaku = nil
                return .none
                
            case .subtitleCleared:
                state.selectedSubtitle = nil
                state.selectedEmbeddedSubtitleTrackID = nil
                state.activeSubtitle = nil
                state.subtitleError = nil
                state.areSubtitlesSuppressed = true
                state.isLoadingSelectedSubtitle = false
                state.loadedEmbeddedSubtitleWindow = nil
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                return .none

            case let .setSubtitlesSuppressed(suppressed):
                state.areSubtitlesSuppressed = suppressed
                if suppressed {
                    state.selectedSubtitle = nil
                    state.selectedEmbeddedSubtitleTrackID = nil
                    state.activeSubtitle = nil
                    state.isLoadingSelectedSubtitle = false
                    state.loadedEmbeddedSubtitleWindow = nil
                    state.inFlightEmbeddedSubtitleWindowRequest = nil
                }
                state.subtitleError = nil
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
                    state.subtitleError = "媒体库地址无效。"
                    return .none
                }
                guard let fileID = file.id, !fileID.isEmpty else {
                    state.subtitleError = "选定的文件缺少标识符。"
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
                state.fileSelection = nil
                state.playbackError = nil
                state.selectedSubtitle = nil
                state.selectedEmbeddedSubtitleTrackID = nil
                state.activeSubtitle = nil
                state.isLoadingSelectedSubtitle = false
                state.loadedEmbeddedSubtitleWindow = nil
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                return loadSubtitles(for: &state)

            case let .setPlaybackError(message):
                state.playbackError = message
                return .none
                
            case .delegate:
                return .none
            }
        }
    }
    
    private func loadSubtitles(for state: inout State) -> Effect<Action> {
        guard let currentItem = state.currentItem,
              let fileID = currentItem.file.id,
              !fileID.isEmpty else {
            state.availableSubtitles = []
            state.availableEmbeddedSubtitles = []
            state.availableAudioTracks = []
            state.selectedAudioTrackID = nil
            state.selectedSubtitle = nil
            state.selectedEmbeddedSubtitleTrackID = nil
            state.activeSubtitle = nil
            state.isLoadingSubtitles = false
            state.isLoadingEmbeddedSubtitles = false
            state.areSubtitlesSuppressed = false
            state.isLoadingSelectedSubtitle = false
            state.isLoadingDanmaku = false
            state.danmakuError = nil
            state.activeDanmaku = nil
            state.hasTriggeredPlaybackStartSync = false
            state.currentPlaybackTime = 0
            state.loadedEmbeddedSubtitleWindow = nil
            state.inFlightEmbeddedSubtitleWindowRequest = nil
            return .none
        }
        let stream = currentItem.stream
        let prefersBackendEmbeddedTracks = PlayerBackendKind.defaultDistributable.capabilities.contains(.embeddedSubtitleTracks)
        state.isLoadingSubtitles = state.configuration.baseURL != nil
        state.isLoadingEmbeddedSubtitles = prefersBackendEmbeddedTracks
        state.availableSubtitles = []
        state.availableEmbeddedSubtitles = []
        state.availableAudioTracks = []
        state.selectedAudioTrackID = nil
        state.selectedSubtitle = nil
        state.selectedEmbeddedSubtitleTrackID = nil
        state.activeSubtitle = nil
        state.subtitleError = nil
        state.areSubtitlesSuppressed = false
        state.isLoadingSelectedSubtitle = false
        state.isLoadingDanmaku = state.configuration.baseURL != nil
        state.danmakuError = nil
        state.activeDanmaku = nil
        state.hasTriggeredPlaybackStartSync = false
        state.currentPlaybackTime = 0
        state.loadedEmbeddedSubtitleWindow = nil
        state.inFlightEmbeddedSubtitleWindowRequest = nil

        let subtitleListEffect: Effect<Action>
        if let baseURL = state.configuration.baseURL {
            let token = state.configuration.apiToken
            subtitleListEffect = .run { [remoteClient] send in
                await send(
                    .subtitleListResponse(
                        fileID,
                        TaskResult {
                            try await remoteClient.fetchSubtitleInfo(baseURL, token, fileID)
                        }
                    )
                )
            }
        } else {
            subtitleListEffect = .none
        }

        let danmakuEffect: Effect<Action>
        if let baseURL = state.configuration.baseURL {
            let token = state.configuration.apiToken
            danmakuEffect = .run { [remoteClient] send in
                await send(
                    .danmakuResponse(
                        fileID,
                        TaskResult {
                            let xml = try await remoteClient.fetchDanmakuXML(baseURL, token, fileID)
                            return .init(payload: try BilibiliDanmakuParser.parse(xml: xml))
                        }
                    )
                )
            }
        } else {
            danmakuEffect = .none
        }

        let embeddedTracksEffect: Effect<Action>
        if prefersBackendEmbeddedTracks {
            embeddedTracksEffect = .none
        } else {
            state.isLoadingEmbeddedSubtitles = true
            embeddedTracksEffect = .run { send in
                let extractor = EmbeddedSubtitleExtractor()
                debugLogEmbeddedSubtitlePlayback(
                    "extractor track scan start fileID=\(fileID) streamURL=\(stream.url.absoluteString)"
                )
                await send(
                    .embeddedSubtitleTracksResponse(
                        fileID,
                        TaskResult {
                            try await extractor.availableTracks(for: stream.url, headers: stream.headers)
                        }
                    )
                )
            }
        }

        return .merge(subtitleListEffect, embeddedTracksEffect, danmakuEffect)
    }

    private func refreshEmbeddedSubtitleWindowIfNeeded(
        for state: inout State,
        fileID: String,
        force: Bool
    ) -> Effect<Action> {
        guard let currentItem = state.currentItem,
              currentItem.file.id == fileID,
              let selectedTrackID = state.selectedEmbeddedSubtitleTrackID,
              let selectedTrack = state.availableEmbeddedSubtitles.first(where: { $0.id == selectedTrackID }),
              !state.areSubtitlesSuppressed,
              state.selectedSubtitle == nil else {
            return .none
        }

        let usesNativeEmbeddedSubtitleSelection =
            PlayerBackendKind.defaultDistributable.capabilities.contains(.embeddedSubtitleTracks)
            && selectedTrack.backendTrackID != nil
        guard !usesNativeEmbeddedSubtitleSelection else {
            return .none
        }

        let targetWindow = embeddedSubtitleWindow(around: state.currentPlaybackTime)

        if !force {
            if let inFlightRequest = state.inFlightEmbeddedSubtitleWindowRequest,
               inFlightRequest.trackID == selectedTrackID,
               inFlightRequest.window.contains(state.currentPlaybackTime) {
                return .none
            }

            if let loadedWindow = state.loadedEmbeddedSubtitleWindow,
               state.activeSubtitle != nil,
               embeddedSubtitleWindowStillValid(loadedWindow, for: state.currentPlaybackTime) {
                return .none
            }
        }

        let requestID = UUID()
        state.isLoadingSelectedSubtitle = true
        state.subtitleError = nil
        state.inFlightEmbeddedSubtitleWindowRequest = .init(
            requestID: requestID,
            trackID: selectedTrackID,
            window: targetWindow
        )

        let extractor = EmbeddedSubtitleExtractor()
        let stream = currentItem.stream
        debugLogEmbeddedSubtitlePlayback(
            "load embedded subtitle window start fileID=\(fileID) trackID=\(selectedTrackID) window=\(describeEmbeddedSubtitleWindow(targetWindow)) streamURL=\(stream.url.absoluteString)"
        )
        return .run { send in
            await send(
                .embeddedSubtitleContentResponse(
                    fileID,
                    selectedTrackID,
                    requestID,
                    targetWindow,
                    TaskResult {
                        let document = try await extractor.loadDocument(
                            for: selectedTrackID,
                            from: stream.url,
                            headers: stream.headers,
                            window: targetWindow
                        )
                        debugLogEmbeddedSubtitlePlayback(
                            "embedded subtitle window document ready fileID=\(fileID) trackID=\(selectedTrackID) window=\(describeEmbeddedSubtitleWindow(targetWindow)) fileName=\(document.fileName ?? "embedded-\(selectedTrackID).ass")"
                        )
                        let loadedSubtitle = makeLoadedSubtitle(
                            document: document,
                            fallbackFileName: "embedded-\(selectedTrackID).ass"
                        )
                        debugLogEmbeddedSubtitlePlayback(
                            "embedded subtitle render payload ready fileID=\(fileID) trackID=\(selectedTrackID) window=\(describeEmbeddedSubtitleWindow(targetWindow)) fileName=\(loadedSubtitle.fileName)"
                        )
                        return loadedSubtitle
                    }
                )
            )
        }
    }

    private func autoSelectSubtitleIfNeeded(for state: inout State) -> Effect<Action> {
        guard !state.areSubtitlesSuppressed,
              !state.isLoadingSelectedSubtitle,
              state.selectedSubtitle == nil,
              state.selectedEmbeddedSubtitleTrackID == nil,
              state.activeSubtitle == nil else {
            return .none
        }

        if !state.isLoadingEmbeddedSubtitles,
           let embeddedSubtitle = state.availableEmbeddedSubtitles.first {
            return .send(.embeddedSubtitleSelected(embeddedSubtitle.id))
        }

        if !state.isLoadingSubtitles,
           let externalSubtitle = state.availableSubtitles.first {
            return .send(.subtitleSelected(externalSubtitle))
        }

        return .none
    }
}

private enum PlayerSubtitleLoadError: LocalizedError {
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(fileName):
            return "暂不支持渲染字幕文件：\(fileName)"
        }
    }
}

private func makeLoadedSubtitle(rawText: String, fileName: String) throws -> PlayerPresenter.State.LoadedSubtitle {
    guard let document = SubtitleDocument.detecting(rawText: rawText, fileName: fileName) else {
        throw PlayerSubtitleLoadError.unsupportedFormat(fileName)
    }
    return .init(fileName: fileName, document: document)
}

private func makeLoadedSubtitle(
    document: SubtitleDocument,
    fallbackFileName: String
) -> PlayerPresenter.State.LoadedSubtitle {
    .init(
        fileName: document.fileName ?? fallbackFileName,
        document: document
    )
}

private func makeEmbeddedSubtitleTrack(from track: PlayerTrack) -> SubtitleTrack? {
    let trackID: String
    if let streamIndex = track.streamIndex {
        trackID = String(streamIndex)
    } else if Int(track.id) != nil {
        trackID = track.id
    } else {
        return nil
    }

    return SubtitleTrack(
        id: trackID,
        displayName: track.displayName,
        language: track.language,
        formatHint: subtitleFormatHint(for: track.codec),
        kind: .embedded,
        backendTrackID: track.id
    )
}

private func subtitleFormatHint(for codec: String?) -> SubtitleFormat? {
    guard let codec = codec?.lowercased() else { return nil }
    switch codec {
    case "ass", "ssa":
        return .ass
    case "subrip", "srt", "mov_text", "text":
        return .srt
    case "webvtt":
        return .webvtt
    default:
        return nil
    }
}

private func mergeEmbeddedSubtitleTracks(
    existing: [SubtitleTrack],
    incoming: [SubtitleTrack],
    preferIncoming: Bool
) -> [SubtitleTrack] {
    var merged: [String: SubtitleTrack] = [:]

    for track in preferIncoming ? existing : incoming {
        merged[track.id] = track
    }
    for track in preferIncoming ? incoming : existing {
        merged[track.id] = track
    }

    return merged.values.sorted { lhs, rhs in
        let lhsID = Int(lhs.id) ?? .max
        let rhsID = Int(rhs.id) ?? .max
        if lhsID != rhsID {
            return lhsID < rhsID
        }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}

private func debugLogEmbeddedSubtitlePlayback(_ message: @autoclosure () -> String) {
#if DEBUG
    print("[PlayerPresenter][EmbeddedSubtitle] \(message())")
#endif
}

private func describeEmbeddedSubtitleTracks(_ tracks: [SubtitleTrack]) -> String {
    guard !tracks.isEmpty else { return "<empty>" }
    return tracks.map { "\($0.id):\($0.displayName)" }.joined(separator: ", ")
}

private func embeddedSubtitleWindow(around playbackTime: TimeInterval) -> ClosedRange<TimeInterval> {
    let lookBehind: TimeInterval = 20
    let lookAhead: TimeInterval = 180
    let lowerBound = max(playbackTime - lookBehind, 0)
    let upperBound = max(playbackTime + lookAhead, lowerBound + 30)
    return lowerBound...upperBound
}

private func embeddedSubtitleWindowStillValid(
    _ window: ClosedRange<TimeInterval>,
    for playbackTime: TimeInterval
) -> Bool {
    let safeLeadingPadding: TimeInterval = 10
    let safeTrailingPadding: TimeInterval = 45
    return playbackTime >= window.lowerBound + safeLeadingPadding
        && playbackTime <= window.upperBound - safeTrailingPadding
}

private func describeEmbeddedSubtitleWindow(_ window: ClosedRange<TimeInterval>) -> String {
    "\(Int((window.lowerBound * 1000).rounded(.down)))...\(Int((window.upperBound * 1000).rounded(.up)))"
}
