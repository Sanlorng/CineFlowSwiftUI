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

        struct LoadedSubtitle: Equatable {
            let fileName: String
            let content: String
        }
        
        let configuration: LibraryPresenter.State.Configuration
        var playlist: IdentifiedArrayOf<PlaylistItem>
        var currentIndex: Int
        let allEpisodeFiles: [Components.Schemas.LibraryBangumiEpisode: [Components.Schemas.LibraryBangumiMatchedFile]]
        
        var isLoadingSubtitles = false
        var availableSubtitles: [RemoteMediaLibraryClient.Subtitle] = []
        var selectedSubtitle: RemoteMediaLibraryClient.Subtitle?
        var subtitleError: String?
        var activeSubtitle: LoadedSubtitle?
        var currentSubtitleLayout: FSPlayerOptions.SubtitleLayout = .standard
        var isSubtitleLayoutAutoAdjustEnabled = true
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
    }
    
    enum Action: Equatable {
        case onAppear
        case playItem(PlayerPresenter.State.PlaylistItem.ID)
        case playNext
        case playPrevious
        case updateCurrentIndex(Int)
        case subtitleListResponse(TaskResult<[RemoteMediaLibraryClient.Subtitle]>)
        case subtitleSelected(RemoteMediaLibraryClient.Subtitle)
        case subtitleContentResponse(RemoteMediaLibraryClient.Subtitle, TaskResult<String>)
        case subtitleCleared
        case setSubtitlesSuppressed(Bool)
        case subtitleLayoutChanged(FSPlayerOptions.SubtitleLayout)
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
                
            case let .subtitleListResponse(.success(subtitles)):
                state.isLoadingSubtitles = false
                state.availableSubtitles = subtitles
                state.subtitleError = nil
                state.isSubtitleLayoutAutoAdjustEnabled = true
                state.activeSubtitle = nil
                state.selectedSubtitle = nil
                state.isLoadingSelectedSubtitle = false
                state.areSubtitlesSuppressed = false
                return .none
                
            case let .subtitleListResponse(.failure(error)):
                state.isLoadingSubtitles = false
                state.availableSubtitles = []
                state.selectedSubtitle = nil
                state.activeSubtitle = nil
                state.subtitleError = error.localizedDescription
                state.currentSubtitleLayout = .standard
                state.isSubtitleLayoutAutoAdjustEnabled = true
                state.isLoadingSelectedSubtitle = false
                state.areSubtitlesSuppressed = false
                return .none
                
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
                state.subtitleError = nil
                state.activeSubtitle = nil
                state.isLoadingSelectedSubtitle = true
                let token = state.configuration.apiToken
                return .run { [remoteClient] send in
                    await send(
                        .subtitleContentResponse(
                            subtitle,
                            TaskResult {
                                try await remoteClient.fetchSubtitleFile(baseURL, token, fileID, subtitle.fileName)
                            }
                        )
                    )
                }

            case let .subtitleContentResponse(subtitle, .success(content)):
                state.isLoadingSelectedSubtitle = false
                guard state.selectedSubtitle?.id == subtitle.id else {
                    return .none
                }
                state.activeSubtitle = .init(fileName: subtitle.fileName, content: content)
                state.subtitleError = nil
                if state.isSubtitleLayoutAutoAdjustEnabled {
                    state.currentSubtitleLayout = guessSubtitleLayout(for: subtitle.fileName)
                }
                return .none

            case let .subtitleContentResponse(subtitle, .failure(error)):
                state.isLoadingSelectedSubtitle = false
                if state.selectedSubtitle?.id == subtitle.id {
                    state.subtitleError = error.localizedDescription
                    state.activeSubtitle = nil
                }
                return .none
                
            case .subtitleCleared:
                state.selectedSubtitle = nil
                state.activeSubtitle = nil
                state.subtitleError = nil
                state.areSubtitlesSuppressed = true
                state.currentSubtitleLayout = .standard
                state.isSubtitleLayoutAutoAdjustEnabled = true
                state.isLoadingSelectedSubtitle = false
                return .none

            case let .setSubtitlesSuppressed(suppressed):
                state.areSubtitlesSuppressed = suppressed
                if suppressed {
                    state.selectedSubtitle = nil
                    state.activeSubtitle = nil
                    state.isLoadingSelectedSubtitle = false
                }
                state.subtitleError = nil
                return .none

            case let .subtitleLayoutChanged(layout):
                state.currentSubtitleLayout = layout
                state.isSubtitleLayoutAutoAdjustEnabled = false
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
                    state.activeSubtitle = nil
                    state.isLoadingSelectedSubtitle = false
                    state.currentSubtitleLayout = .standard
                    state.isSubtitleLayoutAutoAdjustEnabled = true
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
            state.selectedSubtitle = nil
            state.activeSubtitle = nil
            state.isLoadingSubtitles = false
            state.currentSubtitleLayout = .standard
            state.isSubtitleLayoutAutoAdjustEnabled = true
            state.areSubtitlesSuppressed = false
            state.isLoadingSelectedSubtitle = false
            return .none
        }
        guard let baseURL = state.configuration.baseURL else {
            state.subtitleError = "媒体库地址无效。"
            state.activeSubtitle = nil
            state.currentSubtitleLayout = .standard
            state.isSubtitleLayoutAutoAdjustEnabled = true
            state.areSubtitlesSuppressed = false
            state.isLoadingSelectedSubtitle = false
            return .none
        }
        state.isLoadingSubtitles = true
        state.availableSubtitles = []
        state.selectedSubtitle = nil
        state.activeSubtitle = nil
        state.subtitleError = nil
        state.currentSubtitleLayout = .standard
        state.isSubtitleLayoutAutoAdjustEnabled = true
        state.areSubtitlesSuppressed = false
        state.isLoadingSelectedSubtitle = false
        let token = state.configuration.apiToken
        return .run { [remoteClient] send in
            await send(
                .subtitleListResponse(
                    TaskResult {
                        try await remoteClient.fetchSubtitleInfo(baseURL, token, fileID)
                    }
                )
            )
        }
    }
}

private func guessSubtitleLayout(for fileName: String) -> FSPlayerOptions.SubtitleLayout {
    let lowercased = fileName.lowercased()
    let directKeywords = [
        "bilingual",
        "dual",
        "双语",
        "雙語",
        "双語",
        "中日",
        "日中",
        "中英",
        "英中"
    ]
    if directKeywords.contains(where: { lowercased.contains($0) }) {
        return .bilingual
    }
    
    let chineseTokens = ["chs", "chi", "zh", "cn", "sc", "tc", "gb", "big5", "繁", "简", "漢", "汉", "中"]
    let japaneseTokens = ["jp", "ja", "jpn", "jap", "日"]
    let englishTokens = ["eng", "en"]
    
    let containsChinese = chineseTokens.contains(where: { lowercased.contains($0) })
    let containsJapanese = japaneseTokens.contains(where: { lowercased.contains($0) })
    let containsEnglish = englishTokens.contains(where: { lowercased.contains($0) })
    
    if (containsChinese && containsJapanese) || (containsChinese && containsEnglish) {
        return .bilingual
    }
    
    return .standard
}
