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
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: .Home) {
                HomeContentView(store: homeStore)
            }
            Tab("Library", systemImage: "rectangle.stack", value: .Library) {
                LibraryContentView(store: libraryStore)
            }
        }.tabViewStyle(.automatic)
    }
}
