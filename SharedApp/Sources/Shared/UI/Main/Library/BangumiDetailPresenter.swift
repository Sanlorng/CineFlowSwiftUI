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
    }
    
    enum Action: Equatable {
        case onAppear
        case detailResponse(Components.Schemas.LibraryBangumiDetailsResponse)
        case detailFailed(String)
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
            }
        }
    }
}
