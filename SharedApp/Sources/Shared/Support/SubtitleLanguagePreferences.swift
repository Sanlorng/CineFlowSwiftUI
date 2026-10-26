import Dependencies
import Foundation

enum SubtitleLanguagePreferences {
    static let storageKey = "player.subtitle.languagePriority"

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map(normalized).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func decode(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return unique(values)
    }

    static func encode(_ values: [String]) -> String {
        let data = try! JSONEncoder().encode(unique(values))
        return String(decoding: data, as: UTF8.self)
    }

    enum InputError: LocalizedError {
        case invalidQueue
        var errorDescription: String? { "请输入 [zh, zh-cn, ja] 格式的队列；清空请使用 []。" }
    }

    static func parse(_ text: String) throws -> [String] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("["), text.hasSuffix("]") else { throw InputError.invalidQueue }
        if let data = text.data(using: .utf8),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            return unique(values)
        }
        let body = text.dropFirst().dropLast()
        guard !body.contains(where: { "[]\"'".contains($0) }) else { throw InputError.invalidQueue }
        let values = body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        guard values.allSatisfy({ !normalized($0).isEmpty }) else { throw InputError.invalidQueue }
        return unique(values)
    }

    // Prefer language metadata. Titles are a fallback for tracks without a tag.
    static func key(for track: SubtitleTrack) -> String? {
        if let language = track.language.map(normalized), !language.isEmpty, language != "und" {
            return language
        }
        let name = normalized(track.displayName)
        return name.isEmpty ? nil : name
    }

    static func preferredTrack(in tracks: [SubtitleTrack], queue: [String]) -> SubtitleTrack? {
        for entry in unique(queue) {
            if let track = tracks.first(where: { key(for: $0) == entry || normalized($0.displayName) == entry }) {
                return track
            }
        }
        return nil
    }
}

struct SubtitleLanguagePreferencesClient: Sendable {
    var read: @Sendable () -> [String]
    var remember: @Sendable (String) -> Void
}

extension SubtitleLanguagePreferencesClient: DependencyKey {
    static let liveValue = persisted()
    static let testValue = Self(read: { [] }, remember: { _ in })

    static func persisted(suiteName: String? = nil) -> Self {
        Self(
            read: {
                let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
                return SubtitleLanguagePreferences.decode(defaults.string(forKey: SubtitleLanguagePreferences.storageKey) ?? "[]")
            },
            remember: { key in
                let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
                let values = SubtitleLanguagePreferences.decode(defaults.string(forKey: SubtitleLanguagePreferences.storageKey) ?? "[]")
                defaults.set(SubtitleLanguagePreferences.encode(values + [key]), forKey: SubtitleLanguagePreferences.storageKey)
            }
        )
    }
}

extension DependencyValues {
    var subtitleLanguagePreferences: SubtitleLanguagePreferencesClient {
        get { self[SubtitleLanguagePreferencesClient.self] }
        set { self[SubtitleLanguagePreferencesClient.self] = newValue }
    }
}
