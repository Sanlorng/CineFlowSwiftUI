//
//  HomePresenter.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/28.
//

import SwiftUI
import ComposableArchitecture
import DandanApi
import DependenciesMacro

@Reducer
@WithDependencies(\.dandanClient)
struct HomePresenter {
    
    @ObservableState
    struct State: Equatable {
        var homePage: Operations.HomepageGetHomepage.Output? = nil
    }
    enum Action {
        case Refresh
        case didFetchHomepage(Operations.HomepageGetHomepage.Output)
    }
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
                case .Refresh:
                    return .run { send in
                        let homepage = try await dandanClient.homepageGetHomepage()
                        await send(.didFetchHomepage(homepage))
                    }
                case .didFetchHomepage(let homepage):
                    state.homePage = homepage
                    return .none
            }
        }
    }
}
