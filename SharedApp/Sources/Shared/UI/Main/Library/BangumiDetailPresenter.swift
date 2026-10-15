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
        let configuration: MediaLibraryConfiguration
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
        case startPlayback(PlaybackRequest)
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
            let prepared = try PlaylistBuilder.build(
                detail: detail,
                baseURL: baseURL,
                token: token,
                configuration: configuration,
                seriesTitle: state.summary.title,
                coverURL: state.summary.coverURL,
                selectedEpisode: selectedEpisode,
                selectedFile: selectedFile,
                makeStream: remoteClient.makeDirectStreamContext
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


}
