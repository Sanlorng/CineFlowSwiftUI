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
        WithViewStore(libraryStore, observe: \.requestedPlayerState) { viewStore in
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
            .onChange(of: viewStore.state) { _, requestedPlayerState in
                guard let requestedPlayerState else { return }
                playerStore = Store(initialState: requestedPlayerState) {
                    PlayerPresenter()
                }
                selectedTab = .Player
                viewStore.send(.playbackRequestHandled)
            }
        }
    }
}
