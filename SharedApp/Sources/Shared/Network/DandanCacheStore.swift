import Foundation
import CryptoKit

actor DandanCacheStore {
    struct LoadedValue: Sendable {
        let data: Data
        let policy: DandanCachePolicy
    }

    private struct Entry: Codable, Sendable {
        let createdAt: Date
        let freshUntil: Date
        let staleUntil: Date
        let payload: Data
    }

    private static let namespace = "dandan-v1"

    private let fileManager: FileManager
    private let directoryURL: URL
    private let maxMemoryEntries: Int

    private var memory: [String: Entry] = [:]
    private var accessOrder: [String] = []
    private var inFlight: [String: Task<Entry, Error>] = [:]

    init(
        fileManager: FileManager = .default,
        maxMemoryEntries: Int = 192
    ) {
        self.fileManager = fileManager
        self.maxMemoryEntries = maxMemoryEntries

        let baseDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directoryURL = baseDirectory
            .appendingPathComponent("CineFlow", isDirectory: true)
            .appendingPathComponent(Self.namespace, isDirectory: true)

        try? fileManager.createDirectory(
            at: self.directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func data(
        for key: String,
        policy: DandanCachePolicy,
        mode: DandanCacheMode,
        load: @escaping @Sendable () async throws -> LoadedValue
    ) async throws -> Data {
        switch mode {
        case .forceRefresh:
            return try await fetchAndStore(key: key, load: load)

        case .standard:
            if let entry = readEntry(for: key) {
                let now = Date()
                if entry.freshUntil > now {
                    promoteToMemory(entry, for: key)
                    return entry.payload
                }

                if entry.staleUntil > now {
                    switch policy.behavior {
                    case .staleWhileRevalidate:
                        startBackgroundRefreshIfNeeded(key: key, load: load)
                        promoteToMemory(entry, for: key)
                        return entry.payload

                    case .cacheFirst:
                        do {
                            return try await fetchAndStore(key: key, load: load)
                        } catch {
                            promoteToMemory(entry, for: key)
                            return entry.payload
                        }
                    }
                }

                removeEntry(for: key)
            }

            return try await fetchAndStore(key: key, load: load)
        }
    }

    private func fetchAndStore(
        key: String,
        load: @escaping @Sendable () async throws -> LoadedValue
    ) async throws -> Data {
        if let task = inFlight[key] {
            return try await task.value.payload
        }

        let task = Task<Entry, Error> {
            let loaded = try await load()
            let now = Date()
            let entry = Entry(
                createdAt: now,
                freshUntil: now.addingTimeInterval(loaded.policy.freshTTL),
                staleUntil: now
                    .addingTimeInterval(loaded.policy.freshTTL)
                    .addingTimeInterval(loaded.policy.staleGraceTTL),
                payload: loaded.data
            )
            await self.persist(entry, for: key)
            return entry
        }

        inFlight[key] = task
        defer { inFlight[key] = nil }

        let entry = try await task.value
        return entry.payload
    }

    private func startBackgroundRefreshIfNeeded(
        key: String,
        load: @escaping @Sendable () async throws -> LoadedValue
    ) {
        guard inFlight[key] == nil else { return }

        let task = Task<Entry, Error> {
            let loaded = try await load()
            let now = Date()
            let entry = Entry(
                createdAt: now,
                freshUntil: now.addingTimeInterval(loaded.policy.freshTTL),
                staleUntil: now
                    .addingTimeInterval(loaded.policy.freshTTL)
                    .addingTimeInterval(loaded.policy.staleGraceTTL),
                payload: loaded.data
            )
            await self.persist(entry, for: key)
            return entry
        }

        inFlight[key] = task

        Task {
            _ = try? await task.value
            await self.clearInFlightTask(for: key)
        }
    }

    private func clearInFlightTask(for key: String) {
        inFlight[key] = nil
    }

    private func readEntry(for key: String) -> Entry? {
        if let entry = memory[key] {
            return entry
        }

        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }

        if entry.staleUntil <= Date() {
            try? fileManager.removeItem(at: url)
            return nil
        }

        promoteToMemory(entry, for: key)
        return entry
    }

    private func persist(_ entry: Entry, for key: String) {
        promoteToMemory(entry, for: key)

        let url = fileURL(for: key)
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func removeEntry(for key: String) {
        memory.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
        try? fileManager.removeItem(at: fileURL(for: key))
    }

    private func promoteToMemory(_ entry: Entry, for key: String) {
        memory[key] = entry
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)

        while accessOrder.count > maxMemoryEntries {
            let removedKey = accessOrder.removeFirst()
            memory.removeValue(forKey: removedKey)
        }
    }

    private func fileURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(cacheFileName(for: key), isDirectory: false)
    }

    private func cacheFileName(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).json"
    }
}
