import ComposableArchitecture
import Foundation
import Testing
@testable import Shared

@MainActor
struct HomePresenterTests {
    @Test
    func libraryChangesCancelOldHighlightsAndRejectTheirLateResponse() async {
        let clock = TestClock()
        let configuration = PlaybackTestFixtures.configuration
        let store = TestStore(initialState: HomePresenter.State()) { HomePresenter() } withDependencies: {
            $0.uuid = .incrementing
            $0.remoteLibraryConfigurationOperation.fetchDefault = {
                .init(id: configuration.id, name: configuration.name, url: configuration.url,
                      apiKey: nil, isDefault: true, createdAt: configuration.createdAt)
            }
            $0.remoteMediaLibraryClient.fetchBangumiList = { _, _, _ in
                try await clock.sleep(for: .seconds(60))
                return []
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        let first = await store.send(.remoteLibraryChanged)
        let firstID = store.state.remoteHighlightsRequestID!
        let second = await store.send(.remoteLibraryChanged)
        await first.finish()
        await store.send(.remoteHighlightsResponse(firstID, .failure(CancellationError())))
        #expect(store.state.quickStatusErrorMessage == nil)
        #expect(store.state.remoteHighlightsRequestID != firstID)
        await clock.advance(by: .seconds(60))
        await store.receive(\.remoteHighlightsResponse)
        #expect(store.state.remoteHighlightsRequestID == nil)
        await second.finish()
        await store.finish()
    }
}
