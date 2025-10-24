//
//  File.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/28.
//

import SwiftUI
import ComposableArchitecture

struct HomeContentView: View {

    let store: StoreOf<HomePresenter>
    
    var body: some View {
        VStack {
            Text(store.state.homePage?.successModel?.value2.banners?.first?.title ?? "No Title")
            Button("Refresh") {
                store.send(.Refresh)
            }
        }
    }
}
