import SwiftUI
import SwiftData
import ComposableArchitecture

@MainActor
public struct SharedContentView: View {
    @StateObject private var runtime = SharedAppRuntime()

    public init() {}

    public var body: some View {
        MainContentView(store: runtime.store)
            .modelContainer(runtime.container)
    }
}

/// Owns the persistence container and root store for the lifetime of one window.
@MainActor
private final class SharedAppRuntime: ObservableObject {
    let container: ModelContainer
    let store: StoreOf<AppPresenter>

    init() {
        do {
            let container = try ModelContainer(for: RemoteLibraryConfiguration.self)
            self.container = container
            self.store = Store(initialState: AppPresenter.State()) {
                AppPresenter()
            } withDependencies: {
                $0.remoteLibraryConfigurationOperation = .live(container: container)
            }
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }
}
