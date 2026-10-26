import Combine
import CryptoKit
import Foundation

/// One instance per source, so late callbacks cannot save another video's position.
@MainActor
final class PlaybackProgressSession: ObservableObject {
    private let defaults: UserDefaults
    private let key: String
    private var resumeTime: TimeInterval?
    private var pendingSeek: TimeInterval?
    private var seekRequestedAt: Date?
    private var latest: TimeInterval?
    private var lastSavedAt = Date.distantPast
    private var completed = false

    init(url: URL, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Do not persist signed URLs or credentials as preference keys.
        var identity = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // Library credentials may rotate without changing the underlying file.
        if url.path.contains("/api/v1/stream/id/") {
            let items = identity?.queryItems?.filter { $0.name != "token" }
            identity?.queryItems = items
            if identity?.queryItems?.isEmpty == true { identity?.queryItems = nil }
        }
        let digest = SHA256.hash(data: Data((identity?.string ?? url.absoluteString).utf8))
        key = "player.progress." + digest.map { String(format: "%02x", $0) }.joined()
        let saved = defaults.double(forKey: key)
        resumeTime = saved.isFinite && saved > 0 ? saved : nil
    }

    func update(_ timeline: PlayerTimeline, now: Date = Date()) -> TimeInterval? {
        guard !completed, timeline.currentTime.isFinite,
              timeline.currentTime >= 0,
              let duration = timeline.duration, duration.isFinite, duration > 0 else { return nil }
        if let saved = resumeTime {
            resumeTime = nil
            // A changed/truncated source must not seek beyond its end.
            if saved < duration {
                pendingSeek = saved
                seekRequestedAt = now
                return saved
            }
        }
        if let target = pendingSeek {
            // Initial zero-time notifications must not erase the saved position
            // while the backend is still performing the resume seek.
            guard abs(timeline.currentTime - target) < 2 ||
                    now.timeIntervalSince(seekRequestedAt ?? now) >= 10 else { return nil }
            pendingSeek = nil
        }
        latest = min(timeline.currentTime, duration)
        if now.timeIntervalSince(lastSavedAt) >= 1 {
            flush()
            lastSavedAt = now
        }
        return nil
    }

    func flush() {
        guard !completed, pendingSeek == nil, let latest else { return }
        defaults.set(latest, forKey: key)
    }

    func finish() {
        completed = true
        latest = nil
        defaults.removeObject(forKey: key)
    }
}
