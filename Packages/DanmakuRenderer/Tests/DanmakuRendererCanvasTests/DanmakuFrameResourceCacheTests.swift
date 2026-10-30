import Testing
@testable import DanmakuRendererCanvas

struct DanmakuFrameResourceCacheTests {
    @Test func visibleResourceSurvivesBackingCacheEviction() {
        var cache = DanmakuFrameResourceCache<String, Int>()
        cache.beginFrame()
        #expect(cache.resource(for: "moving") { 42 } == 42)
        cache.endFrame()
        cache.beginFrame()
        #expect(cache.resource(for: "moving") { nil } == 42)
        cache.endFrame()
    }

    @Test func offscreenAndReplacedResourcesAreReleased() {
        var cache = DanmakuFrameResourceCache<String, Int>()
        cache.beginFrame()
        _ = cache.resource(for: "old") { 42 }
        cache.endFrame()
        cache.beginFrame()
        cache.endFrame()
        #expect(cache.resource(for: "old") { nil } == nil)
        _ = cache.resource(for: "new") { 7 }
        cache.removeAll()
        #expect(cache.resource(for: "new") { nil } == nil)
    }
}
