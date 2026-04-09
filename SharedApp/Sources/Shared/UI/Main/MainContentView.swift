//
//  File.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/28.
//

import SwiftUI
import ComposableArchitecture

struct MainContentView: View {
    let homeStore: StoreOf<HomePresenter>
    let libraryStore: StoreOf<LibraryPresenter>
    @State private var selectedTab: MainTabs = .Home
    @State private var playerStore: StoreOf<PlayerPresenter>?
    
    var body: some View {
        WithViewStore(homeStore, observe: \.requestedPlayerState) { homeViewStore in
            WithViewStore(libraryStore, observe: \.requestedPlayerState) { libraryViewStore in
                TabView(selection: $selectedTab) {
                    Tab("Home", systemImage: "house", value: .Home) {
                        HomeContentView(store: homeStore)
                    }
                    Tab("Library", systemImage: "rectangle.stack", value: .Library) {
                        LibraryContentView(store: libraryStore)
                    }
                    Tab("Player", systemImage: "play.rectangle.on.rectangle", value: .Player) {
                        PlayerContentView(store: playerStore)
                    }
                }
                .tabViewStyle(.automatic)
                .onChange(of: homeViewStore.state) { _, requestedPlayerState in
                    guard let requestedPlayerState else { return }
                    playerStore = Store(initialState: requestedPlayerState) {
                        PlayerPresenter()
                    }
                    selectedTab = .Player
                    homeViewStore.send(.playbackRequestHandled)
                }
                .onChange(of: libraryViewStore.state) { _, requestedPlayerState in
                    guard let requestedPlayerState else { return }
                    playerStore = Store(initialState: requestedPlayerState) {
                        PlayerPresenter()
                    }
                    selectedTab = .Player
                    libraryViewStore.send(.playbackRequestHandled)
                }
            }
        }
    }
}
