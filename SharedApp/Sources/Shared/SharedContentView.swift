//  SharedContentView.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/28.
//

import SwiftUI
import SwiftData
import ComposableArchitecture

@MainActor
public struct SharedContentView: View {
    private let container: ModelContainer
    private let configurationOperation: RemoteLibraryConfigurationOperation
    
    public init() {
        do {
            let container = try ModelContainer(for: RemoteLibraryConfiguration.self)
            self.container = container
            self.configurationOperation = .live(container: container)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }
    
    public var body: some View {
        withDependencies {
            $0.remoteLibraryConfigurationOperation = configurationOperation
        } operation: {
            let homeStore = Store(initialState: HomePresenter.State()) {
                HomePresenter()
            }
            let libraryStore = Store(initialState: LibraryPresenter.State()) {
                LibraryPresenter()
            }
            return MainContentView(homeStore: homeStore, libraryStore: libraryStore)
                .modelContainer(container)
        }
    }
}
