import Darwin
import Foundation

enum MediaNetworkPolicy {
    static func shouldBypassProxy(for url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let urlHost = url.host(percentEncoded: false) else {
            return false
        }

        let host = urlHost.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        guard !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }

        var ipv4 = in_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            return isLocalIPv4(UInt32(bigEndian: ipv4.s_addr))
        }

        var ipv6 = in6_addr()
        let address = host.components(separatedBy: "%")[0]
        guard inet_pton(AF_INET6, address, &ipv6) == 1 else { return false }
        return withUnsafeBytes(of: ipv6) { bytes in
            if bytes.prefix(15).allSatisfy({ $0 == 0 }), bytes[15] <= 1 {
                return true
            }
            if bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) {
                return true
            }
            if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
                let mapped = UInt32(bytes[12]) << 24 | UInt32(bytes[13]) << 16
                    | UInt32(bytes[14]) << 8 | UInt32(bytes[15])
                return isLocalIPv4(mapped)
            }
            return false
        }
    }

    private static func isLocalIPv4(_ address: UInt32) -> Bool {
        let first = address >> 24
        let second = address >> 16 & 0xff
        return address == 0 || first == 10 || first == 127
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
            || (first == 169 && second == 254)
    }
}
