import ComposableArchitecture
import Foundation
import Testing
@testable import Shared

@MainActor
struct LibraryPresenterTests {
    @Test
    func failedDefaultWritePreservesTheCurrentSelection() async {
        let original = PlaybackTestFixtures.configuration
        let other = MediaLibraryConfiguration(
            id: UUID(1), name: "Other", url: original.url, apiToken: nil,
            isDefault: false, createdAt: original.createdAt
        )
        var state = LibraryPresenter.State()
        state.configurations = [original, other]
        state.selectedConfigurationID = original.id
        let store = TestStore(initialState: state) { LibraryPresenter() } withDependencies: {
            $0.remoteLibraryConfigurationOperation.setDefault = { _ in
                throw RemoteLibraryConfigurationOperation.OperationError.missingRecord
            }
        }

        await store.send(.selectConfiguration(other.id)) { $0.pendingDefaultConfigurationID = other.id }
        let message = RemoteLibraryConfigurationOperation.OperationError.missingRecord.localizedDescription
        await store.receive(.defaultConfigurationUpdateFailed(other.id, message)) {
            $0.pendingDefaultConfigurationID = nil
            $0.infoMessage = message
        }
        #expect(store.state.selectedConfigurationID == original.id)
        #expect(store.state.configurations.filter(\.isDefault).map(\.id) == [original.id])
    }

    @Test
    func sameLibraryRefreshCancelsThePreviousRequest() async {
        let clock = TestClock()
        let configuration = PlaybackTestFixtures.configuration
        var state = LibraryPresenter.State()
        state.configurations = [configuration]
        state.selectedConfigurationID = configuration.id
        let store = TestStore(initialState: state) { LibraryPresenter() } withDependencies: {
            $0.uuid = .incrementing
            $0.remoteMediaLibraryClient.fetchBangumiList = { _, _, _ in
                try await clock.sleep(for: .seconds(1))
                return []
            }
        }

        let first = await store.send(.fetchLibrary(configuration.id)) {
            $0.libraryRequestID = UUID(0)
            $0.isLoadingLibrary = true
        }
        await store.send(.fetchLibrary(configuration.id)) {
            $0.libraryRequestID = UUID(1)
        }
        await first.finish()
        await clock.advance(by: .seconds(1))
        await store.receive(.libraryLoaded(UUID(1), configuration.id, .lastPlay, [])) {
            $0.libraryRequestID = nil
            $0.isLoadingLibrary = false
            $0.infoMessage = "媒体库为空。"
        }
    }

    @Test
    func ignoresAnOlderResponseEvenWhenConfigurationAndSortMatch() async {
        let configuration = PlaybackTestFixtures.configuration
        var state = LibraryPresenter.State()
        state.selectedConfigurationID = configuration.id
        state.libraryRequestID = UUID(1)
        state.isLoadingLibrary = true
        let store = TestStore(initialState: state) { LibraryPresenter() }

        await store.send(.libraryLoaded(UUID(0), configuration.id, .lastPlay, []))
        await store.send(.libraryFailed(UUID(0), configuration.id, .lastPlay, "Old failure"))
        await store.send(.libraryLoaded(UUID(1), configuration.id, .lastPlay, [])) {
            $0.libraryRequestID = nil
            $0.isLoadingLibrary = false
            $0.infoMessage = "媒体库为空。"
        }
    }
}
