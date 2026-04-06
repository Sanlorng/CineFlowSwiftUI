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
        
        let configuration: LibraryPresenter.State.Configuration
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
        
        init(
            configuration: LibraryPresenter.State.Configuration,
            playlist: [PlaylistItem],
            currentIndex: Int,
            allEpisodeFiles: [Components.Schemas.LibraryBangumiEpisode: [Components.Schemas.LibraryBangumiMatchedFile]]
        ) {
            self.configuration = configuration
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
        case playerTracksChanged(String, [PlayerTrack])
        case audioTrackSelected(PlayerTrack.ID?)
        case subtitleListResponse(String, TaskResult<[RemoteMediaLibraryClient.Subtitle]>)
        case embeddedSubtitleTracksResponse(String, TaskResult<[SubtitleTrack]>)
        case subtitleSelected(RemoteMediaLibraryClient.Subtitle)
        case subtitleContentResponse(String, RemoteMediaLibraryClient.Subtitle, TaskResult<State.LoadedSubtitle>)
        case localSubtitleLoaded(fileName: String, content: String)
        case localSubtitleLoadFailed(String)
        case embeddedSubtitleSelected(SubtitleTrack.ID)
        case embeddedSubtitleContentResponse(String, SubtitleTrack.ID, TaskResult<State.LoadedSubtitle>)
        case subtitleCleared
        case setSubtitlesSuppressed(Bool)
        case showFilePicker
        case fileSelectionDismissed
        case fileSelected(Components.Schemas.LibraryBangumiMatchedFile)
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
                state.areSubtitlesSuppressed = false
                state.selectedSubtitle = nil
                state.selectedEmbeddedSubtitleTrackID = trackID
                state.subtitleError = nil
                state.activeSubtitle = nil
                state.isLoadingSelectedSubtitle = true

                let extractor = EmbeddedSubtitleExtractor()
                let stream = currentItem.stream
                return .run { send in
                    await send(
                        .embeddedSubtitleContentResponse(
                            fileID,
                            trackID,
                            TaskResult {
                                let document = try await extractor.loadDocument(
                                    for: trackID,
                                    from: stream.url,
                                    headers: stream.headers
                                )
                                return makeLoadedSubtitle(document: document, fallbackFileName: "embedded-\(trackID).ass")
                            }
                        )
                    )
                }

            case let .embeddedSubtitleContentResponse(fileID, trackID, .success(loadedSubtitle)):
                guard state.currentFileID == fileID else { return .none }
                state.isLoadingSelectedSubtitle = false
                guard state.selectedEmbeddedSubtitleTrackID == trackID else {
                    return .none
                }
                state.subtitleError = nil
                state.activeSubtitle = loadedSubtitle
                return .none

            case let .embeddedSubtitleContentResponse(fileID, trackID, .failure(error)):
                guard state.currentFileID == fileID else { return .none }
                state.isLoadingSelectedSubtitle = false
                guard state.selectedEmbeddedSubtitleTrackID == trackID else {
                    return .none
                }
                state.subtitleError = error.localizedDescription
                state.activeSubtitle = nil
                return .none
                
            case .subtitleCleared:
                state.selectedSubtitle = nil
                state.selectedEmbeddedSubtitleTrackID = nil
                state.activeSubtitle = nil
                state.subtitleError = nil
                state.areSubtitlesSuppressed = true
                state.isLoadingSelectedSubtitle = false
                return .none

            case let .setSubtitlesSuppressed(suppressed):
                state.areSubtitlesSuppressed = suppressed
                if suppressed {
                    state.selectedSubtitle = nil
                    state.selectedEmbeddedSubtitleTrackID = nil
                    state.activeSubtitle = nil
                    state.isLoadingSelectedSubtitle = false
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
                do {
                    guard let baseURL = state.configuration.baseURL else {
                        state.subtitleError = "媒体库地址无效。"
                        return .none
                    }
                    guard let fileID = file.id, !fileID.isEmpty else {
                        state.subtitleError = "选定的文件缺少标识符。"
                        return .none
                    }

                    let stream = try remoteClient.makeStreamContext(baseURL, state.configuration.apiToken, fileID)
                    state.playlist[state.currentIndex].file = file
                    state.playlist[state.currentIndex].stream = stream
                    state.fileSelection = nil
                    state.playbackError = nil
                    state.selectedSubtitle = nil
                    state.selectedEmbeddedSubtitleTrackID = nil
                    state.activeSubtitle = nil
                    state.isLoadingSelectedSubtitle = false
                    return loadSubtitles(for: &state)
                } catch {
                    state.subtitleError = error.localizedDescription
                    return .none
                }
                
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

        let embeddedTracksEffect: Effect<Action>
        if prefersBackendEmbeddedTracks {
            embeddedTracksEffect = .none
        } else {
            state.isLoadingEmbeddedSubtitles = true
            embeddedTracksEffect = .run { send in
                let extractor = EmbeddedSubtitleExtractor()
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

        return .merge(subtitleListEffect, embeddedTracksEffect)
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
        kind: .embedded
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
