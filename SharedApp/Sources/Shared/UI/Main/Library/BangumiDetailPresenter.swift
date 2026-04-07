//
//  BangumiDetailPresenter.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/10/19.
//

import Foundation
import ComposableArchitecture
import RemoteMediaLibrary

@Reducer
struct BangumiDetailPresenter {
    
    @Dependency(\.remoteMediaLibraryClient) var remoteClient
    
    @ObservableState
    struct State: Equatable {
        let summary: LibraryPresenter.State.BangumiItem
        let configuration: LibraryPresenter.State.Configuration
        var detail: Components.Schemas.LibraryBangumiDetailsResponse?
        var isLoading = false
        var errorMessage: String?
        var fileSelection: FileSelection?

        struct FileSelection: Equatable, Identifiable {
            let id = UUID()
            let episode: Components.Schemas.LibraryBangumiEpisode
            let files: [Components.Schemas.LibraryBangumiMatchedFile]
        }
    }
    
    enum Action: Equatable {
        case onAppear
        case detailResponse(Components.Schemas.LibraryBangumiDetailsResponse)
        case detailFailed(String)
        case episodeTapped(Components.Schemas.LibraryBangumiEpisode)
        case fileSelectionDismissed
        case fileSelected(Components.Schemas.LibraryBangumiMatchedFile)
        case delegate(DelegateAction)
    }

    enum DelegateAction: Equatable {
        case startPlayback(PlayerPresenter.State)
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.detail == nil, state.isLoading == false else { return .none }
                guard let animeId = state.summary.animeId else {
                    state.errorMessage = "缺少番剧编号，无法获取详情。"
                    return .none
                }
                guard let baseURL = state.configuration.baseURL else {
                    state.errorMessage = "媒体库地址无效。"
                    return .none
                }
                state.isLoading = true
                state.errorMessage = nil
                let token = state.configuration.apiToken
                return .run { [remoteClient] send in
                    do {
                        let detail = try await remoteClient.fetchBangumiDetail(baseURL, token, animeId)
                        await send(.detailResponse(detail))
                    } catch {
                        await send(.detailFailed(error.localizedDescription))
                    }
                }
                
            case let .detailResponse(detail):
                state.isLoading = false
                state.detail = detail
                return .none
                
            case let .detailFailed(message):
                state.isLoading = false
                state.errorMessage = message
                return .none

            case let .episodeTapped(episode):
                guard let detail = state.detail else {
                    state.errorMessage = "尚未加载剧集详情。"
                    return .none
                }
                guard let matchedFiles = episode.localMatchedFiles, !matchedFiles.isEmpty else {
                    state.errorMessage = "该剧集暂无匹配文件。"
                    return .none
                }
                if let file = matchedFiles.first, matchedFiles.count == 1 {
                    return startPlayback(
                        state: &state,
                        detail: detail,
                        selectedEpisode: episode,
                        selectedFile: file
                    )
                } else {
                    state.fileSelection = .init(episode: episode, files: matchedFiles)
                    return .none
                }

            case .fileSelectionDismissed:
                state.fileSelection = nil
                return .none

            case let .fileSelected(file):
                guard let detail = state.detail,
                      let selection = state.fileSelection else {
                    return .none
                }
                return startPlayback(
                    state: &state,
                    detail: detail,
                    selectedEpisode: selection.episode,
                    selectedFile: file
                )

            case .delegate:
                return .none
            }
        }
    }

    private func startPlayback(
        state: inout State,
        detail: Components.Schemas.LibraryBangumiDetailsResponse,
        selectedEpisode: Components.Schemas.LibraryBangumiEpisode,
        selectedFile: Components.Schemas.LibraryBangumiMatchedFile
    ) -> Effect<Action> {
        guard let baseURL = state.configuration.baseURL else {
            state.errorMessage = "媒体库地址无效，无法播放。"
            return .none
        }
        state.fileSelection = nil
        state.errorMessage = nil
        let token = state.configuration.apiToken
        let configuration = state.configuration
        do {
            let prepared = try preparePlaylist(
                remoteClient: remoteClient,
                detail: detail,
                baseURL: baseURL,
                token: token,
                configuration: configuration,
                seriesTitle: state.summary.title,
                coverURL: state.summary.coverURL,
                selectedEpisode: selectedEpisode,
                selectedFile: selectedFile
            )
            return .send(.delegate(.startPlayback(prepared)))
        } catch let error as PlaybackPreparationError {
            switch error {
            case .missingEpisodes:
                state.errorMessage = "无法构建播放列表。"
            case .missingStream(let reason):
                state.errorMessage = reason
            }
            return .none
        } catch {
            state.errorMessage = error.localizedDescription
            return .none
        }
    }

    private func preparePlaylist(
        remoteClient: RemoteMediaLibraryClient,
        detail: Components.Schemas.LibraryBangumiDetailsResponse,
        baseURL: URL,
        token: String?,
        configuration: LibraryPresenter.State.Configuration,
        seriesTitle: String?,
        coverURL: URL?,
        selectedEpisode: Components.Schemas.LibraryBangumiEpisode,
        selectedFile: Components.Schemas.LibraryBangumiMatchedFile
    ) throws -> PlayerPresenter.State {
        guard let episodes = detail.episodes, !episodes.isEmpty else {
            throw PlaybackPreparationError.missingEpisodes
        }

        let referenceName = selectedFile.name ?? selectedFile.path ?? ""

        let episodeFiles = Dictionary(
            uniqueKeysWithValues: episodes.compactMap { episode -> (Components.Schemas.LibraryBangumiEpisode, [Components.Schemas.LibraryBangumiMatchedFile])? in
                guard let files = episode.localMatchedFiles, !files.isEmpty else {
                    return nil
                }
                return (episode, files)
            }
        )

        var playlistItems: [PlayerPresenter.State.PlaylistItem] = []
        var currentIndex = 0

        for episode in episodes {
            guard let files = episodeFiles[episode] else { continue }

            let chosenFile: Components.Schemas.LibraryBangumiMatchedFile
            if episode == selectedEpisode {
                chosenFile = selectedFile
            } else if files.count == 1 {
                chosenFile = files[0]
            } else {
                chosenFile = bestMatchingFile(
                    referenceName: referenceName,
                    files: files
                ) ?? files[0]
            }

            guard let fileID = chosenFile.id, !fileID.isEmpty else {
                throw PlaybackPreparationError.missingStream("文件 \(chosenFile.name ?? "未知") 缺少标识符。")
            }

            let stream = remoteClient.makeDirectStreamContext(baseURL, token, fileID)
            let item = PlayerPresenter.State.PlaylistItem(
                episode: episode,
                file: chosenFile,
                stream: stream
            )
            if episode == selectedEpisode {
                currentIndex = playlistItems.count
            }
            playlistItems.append(item)
        }

        guard !playlistItems.isEmpty else {
            throw PlaybackPreparationError.missingEpisodes
        }

        return PlayerPresenter.State(
            configuration: configuration,
            seriesTitle: seriesTitle,
            coverURL: coverURL,
            playlist: playlistItems,
            currentIndex: currentIndex,
            allEpisodeFiles: episodeFiles
        )
    }

    private func bestMatchingFile(
        referenceName: String,
        files: [Components.Schemas.LibraryBangumiMatchedFile]
    ) -> Components.Schemas.LibraryBangumiMatchedFile? {
        guard !referenceName.isEmpty else {
            return files.first
        }

        let loweredReference = referenceName.lowercased()
        return files.max { lhs, rhs in
            similarity(
                loweredReference,
                lhs.name?.lowercased() ?? lhs.path?.lowercased() ?? ""
            ) < similarity(
                loweredReference,
                rhs.name?.lowercased() ?? rhs.path?.lowercased() ?? ""
            )
        }
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let distance = levenshtein(lhs, rhs)
        let maxCount = max(lhs.count, rhs.count)
        if maxCount == 0 { return 1 }
        return 1 - (Double(distance) / Double(maxCount))
    }

    private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhsArray = Array(lhs)
        let rhsArray = Array(rhs)
        let lhsCount = lhsArray.count
        let rhsCount = rhsArray.count

        var distances = Array(repeating: Array(repeating: 0, count: rhsCount + 1), count: lhsCount + 1)

        for i in 0...lhsCount {
            distances[i][0] = i
        }
        for j in 0...rhsCount {
            distances[0][j] = j
        }

        for i in 1...lhsCount {
            for j in 1...rhsCount {
                let cost = lhsArray[i - 1] == rhsArray[j - 1] ? 0 : 1
                distances[i][j] = min(
                    distances[i - 1][j] + 1,
                    distances[i][j - 1] + 1,
                    distances[i - 1][j - 1] + cost
                )
            }
        }

        return distances[lhsCount][rhsCount]
    }

    private enum PlaybackPreparationError: Error {
        case missingEpisodes
        case missingStream(String)
    }
}
