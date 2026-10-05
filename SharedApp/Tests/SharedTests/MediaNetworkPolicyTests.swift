import Foundation
import Testing
@testable import Shared

struct MediaNetworkPolicyTests {
    @Test(arguments: [
        "http://192.168.31.23:80/api/v1/stream/id/test",
        "https://10.0.0.1/video.mkv",
        "http://172.16.0.1/video.mkv",
        "http://172.31.255.255/video.mkv",
        "http://169.254.1.2/video.mkv",
        "http://127.0.0.1/video.mkv",
        "http://localhost/video.mkv",
        "http://media.local/video.mkv",
        "http://MEDIA.LOCAL./video.mkv",
        "http://[::1]/video.mkv",
        "http://[fd12:3456::1]/video.mkv",
        "http://[fe80::1%25en0]/video.mkv",
        "http://[::ffff:192.168.31.23]/video.mkv"
    ])
    func localMediaUsesDirectConnections(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(MediaNetworkPolicy.shouldBypassProxy(for: url))
    }

    @Test(arguments: [
        "https://media.example.com/video.mkv",
        "http://media.local.example.com/video.mkv",
        "http://172.15.255.255/video.mkv",
        "http://172.32.0.1/video.mkv",
        "http://192.169.1.1/video.mkv",
        "http://8.8.8.8/video.mkv",
        "http://[2001:4860:4860::8888]/video.mkv",
        "http://[::ffff:8.8.8.8]/video.mkv",
        "file:///tmp/video.mkv"
    ])
    func otherMediaPreservesProxyConfiguration(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(!MediaNetworkPolicy.shouldBypassProxy(for: url))
    }
}
