import ComposableArchitecture
import Foundation
import Testing
@testable import Shared

struct SubtitleLanguagePreferencesTests {
    @Test
    func persistedQueueSurvivesNewClientsAndSettingsEdits() {
        let suiteName = "CineFlow.SubtitlePreferencesTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = SubtitleLanguagePreferencesClient.persisted(suiteName: suiteName)
        client.remember("zh")
        client.remember("zh-cn")
        client.remember(" ZH ")
        #expect(SubtitleLanguagePreferencesClient.persisted(suiteName: suiteName).read() == ["zh", "zh-cn"])
        defaults.set(SubtitleLanguagePreferences.encode(["ja", "zh-cn"]), forKey: SubtitleLanguagePreferences.storageKey)
        #expect(client.read() == ["ja", "zh-cn"])
        client.remember("zh")
        #expect(client.read() == ["ja", "zh-cn", "zh"])
    }

    @Test
    func acceptsBothQueueFormatsWithoutMergingDistinctLanguageTags() throws {
        #expect(try SubtitleLanguagePreferences.parse("[zh, zh-cn, JA, zh]") == ["zh", "zh-cn", "ja"])
        #expect(try SubtitleLanguagePreferences.parse("[\"zh\", \"zh-cn\"]") == ["zh", "zh-cn"])
        #expect(try SubtitleLanguagePreferences.parse("[]").isEmpty)
        #expect(throws: SubtitleLanguagePreferences.InputError.self) { try SubtitleLanguagePreferences.parse("zh, ja") }
        #expect(throws: SubtitleLanguagePreferences.InputError.self) { try SubtitleLanguagePreferences.parse("[zh,,ja]") }
        #expect(throws: SubtitleLanguagePreferences.InputError.self) { try SubtitleLanguagePreferences.parse("[\"zh, ja]") }
        let names = ["zh", "简体中文, 双语"]
        #expect(SubtitleLanguagePreferences.decode(SubtitleLanguagePreferences.encode(names)) == names)
    }

    @Test
    func orderedMatchingUsesTagsAndFallsBackToUntypedTitles() {
        let tracks: [SubtitleTrack] = [
            .init(id: "en", displayName: "English", language: "en", kind: .embedded),
            .init(id: "cn", displayName: "简体中文", language: "zh-cn", kind: .embedded),
            .init(id: "zh", displayName: "Chinese", language: "ZH", kind: .embedded),
            .init(id: "title", displayName: "繁体中文", language: "und", kind: .embedded)
        ]
        #expect(SubtitleLanguagePreferences.preferredTrack(in: tracks, queue: ["zh", "zh-cn"])?.id == "zh")
        #expect(SubtitleLanguagePreferences.preferredTrack(in: Array(tracks.prefix(2)), queue: ["zh", "zh-cn"])?.id == "cn")
        #expect(SubtitleLanguagePreferences.preferredTrack(in: tracks, queue: ["繁体中文"])?.id == "title")
        #expect(SubtitleLanguagePreferences.preferredTrack(in: tracks, queue: ["简体中文"])?.id == "cn")
        #expect(SubtitleLanguagePreferences.preferredTrack(in: tracks, queue: ["ja"]) == nil)
    }
}

@MainActor
struct SubtitleLanguageSelectionTests {
    private var initialState: PlayerSubtitlesPresenter.State {
        let request = PlaybackTestFixtures.request()
        return .init(context: .init(id: request.id, configuration: request.configuration,
                                   item: request.playlist.first, capabilities: [.embeddedSubtitleTracks]))
    }

    private var tracks: [PlayerTrack] {
        [
            .init(id: "1", kind: .subtitle, displayName: "English", language: "en"),
            .init(id: "2", kind: .subtitle, displayName: "简体", language: "zh-cn"),
            .init(id: "3", kind: .subtitle, displayName: "中文", language: "zh")
        ]
    }

    @Test
    func onlyManualChoicesAppendWithoutReorderingAndNewFilesUseTheQueue() async {
        let queue = LockIsolated(["zh"])
        let client = SubtitleLanguagePreferencesClient(
            read: { queue.value },
            remember: { key in queue.withValue { $0 = SubtitleLanguagePreferences.unique($0 + [key]) } }
        )
        let store = TestStore(initialState: initialState) { PlayerSubtitlesPresenter() } withDependencies: {
            $0.subtitleLanguagePreferences = client
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.playerTracksChanged(tracks))
        await store.receive(.automaticallySelectEmbeddedSubtitle("3"))
        #expect(queue.value == ["zh"])
        await store.send(.embeddedSubtitleSelected("2"))
        await store.send(.embeddedSubtitleSelected("3"))
        #expect(queue.value == ["zh", "zh-cn"])
        await store.send(.automaticallySelectEmbeddedSubtitle("1"))
        #expect(store.state.selectedEmbeddedSubtitleTrackID == "3")

        let next = TestStore(initialState: initialState) { PlayerSubtitlesPresenter() } withDependencies: {
            $0.subtitleLanguagePreferences = client
        }
        next.exhaustivity = .off(showSkippedAssertions: false)
        await next.send(.playerTracksChanged(Array(tracks.prefix(2))))
        await next.receive(.automaticallySelectEmbeddedSubtitle("2"))
        #expect(queue.value == ["zh", "zh-cn"])
        await store.finish()
        await next.finish()
    }

    @Test
    func unmatchedQueueUsesExistingFallbackWithoutLearningIt() async {
        let learned = LockIsolated<[String]>([])
        let store = TestStore(initialState: initialState) { PlayerSubtitlesPresenter() } withDependencies: {
            $0.subtitleLanguagePreferences.read = { ["ja"] }
            $0.subtitleLanguagePreferences.remember = { key in learned.withValue { $0.append(key) } }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.playerTracksChanged(tracks))
        await store.receive(.automaticallySelectEmbeddedSubtitle("1"))
        #expect(learned.value.isEmpty)
        await store.finish()
    }

    @Test
    func externalListDoesNotBypassPendingEmbeddedPreferences() async {
        var state = initialState
        state.isLoadingEmbeddedSubtitles = true
        state.isLoadingSubtitles = true
        state.subtitleListRequest = .init(id: UUID(0))
        let store = TestStore(initialState: state) { PlayerSubtitlesPresenter() } withDependencies: {
            $0.subtitleLanguagePreferences.read = { ["zh"] }
        }
        await store.send(.subtitleListResponse(UUID(0), .success([.init(fileName: "en.srt", fileSize: nil)]))) {
            $0.isLoadingSubtitles = false
            $0.subtitleListRequest = nil
            $0.availableSubtitles = [.init(fileName: "en.srt", fileSize: nil)]
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.playerTracksChanged(tracks))
        await store.receive(.automaticallySelectEmbeddedSubtitle("3"))
        #expect(store.state.selectedSubtitle == nil)
        await store.finish()
    }
}
