/// Pins visible resources between frames even if the backing NSCache evicts them.
/// Accessed only while the renderer lock is held.
struct DanmakuFrameResourceCache<Key: Hashable, Resource> {
    private var resources: [Key: Resource] = [:]
    private var usedKeys: Set<Key> = []

    mutating func beginFrame() {
        usedKeys.removeAll(keepingCapacity: true)
    }

    mutating func resource(for key: Key, load: () -> Resource?) -> Resource? {
        guard let resource = resources[key] ?? load() else { return nil }
        resources[key] = resource
        usedKeys.insert(key)
        return resource
    }

    mutating func endFrame() {
        resources = resources.filter { usedKeys.contains($0.key) }
    }

    mutating func removeAll() {
        resources.removeAll()
        usedKeys.removeAll()
    }
}
