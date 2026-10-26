import Foundation
import Testing
@testable import Shared

@MainActor
struct PlaybackProgressSessionTests {
    @Test func restoresAcrossSessionsWithoutOverwritingDuringSeek() {
        let suite = "PlaybackProgressTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = URL(string: "https://example.com/a.mkv")!
        let first = PlaybackProgressSession(url: url, defaults: defaults)
        _ = first.update(.init(currentTime: 125, duration: 300))
        let second = PlaybackProgressSession(url: url, defaults: defaults)
        #expect(second.update(.init(currentTime: 0, duration: nil)) == nil)
        #expect(second.update(.init(currentTime: 0, duration: 300)) == 125)
        _ = second.update(.init(currentTime: 0, duration: 300))
        second.flush()
        let third = PlaybackProgressSession(url: url, defaults: defaults)
        #expect(third.update(.init(currentTime: 0, duration: 300)) == 125)
    }

    @Test func distinctLinksStaySeparateAndCompletionClearsOnlyOne() {
        let suite = "PlaybackProgressTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = URL(string: "https://example.com/video?id=1")!
        let b = URL(string: "https://example.com/video?id=2")!
        let first = PlaybackProgressSession(url: a, defaults: defaults)
        let second = PlaybackProgressSession(url: b, defaults: defaults)
        _ = first.update(.init(currentTime: 30, duration: 100))
        _ = second.update(.init(currentTime: 60, duration: 100))
        first.finish()
        _ = first.update(.init(currentTime: 100, duration: 100))
        first.flush()
        #expect(PlaybackProgressSession(url: a, defaults: defaults).update(.init(currentTime: 0, duration: 100)) == nil)
        #expect(PlaybackProgressSession(url: b, defaults: defaults).update(.init(currentTime: 0, duration: 100)) == 60)
    }

    @Test func libraryTokenRotationKeepsProgressAndInvalidTimesAreIgnored() {
        let suite = "PlaybackProgressTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = PlaybackProgressSession(url: URL(string: "https://example.com/api/v1/stream/id/1?token=old")!, defaults: defaults)
        _ = first.update(.init(currentTime: 60, duration: 100))
        _ = first.update(.init(currentTime: .nan, duration: 100))
        first.flush()
        let next = PlaybackProgressSession(url: URL(string: "https://example.com/api/v1/stream/id/1?token=new")!, defaults: defaults)
        #expect(next.update(.init(currentTime: 0, duration: 100)) == 60)
    }
}
