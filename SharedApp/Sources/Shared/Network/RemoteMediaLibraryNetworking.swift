import Foundation

enum RemoteMediaLibraryNetworking {
    // Creating a session does not request permission. The user's welcome request triggers
    // the system prompt when it actually connects to a local media library.
    static let validationSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    static func validationErrorMessage(for error: any Error) -> String {
        guard let apiError = error as? APIError,
              case let .networkError(underlyingError) = apiError,
              underlyingError.domain == NSURLErrorDomain else {
            return error.localizedDescription
        }

        switch underlyingError.code {
        case NSURLErrorNotConnectedToInternet:
#if os(macOS)
            return "无法连接媒体库。请确认设备在同一局域网，并在“系统设置 → 隐私与安全性 → 本地网络”中允许 CineFlow 访问。"
#else
            return "无法连接媒体库。请确认设备在同一局域网，并在“设置 → 隐私与安全性 → 本地网络”中允许 CineFlow 访问。"
#endif
        case NSURLErrorTimedOut:
            return "连接媒体库超时。请确认已允许本地网络访问，并检查媒体库地址、端口和服务是否正常。"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "无法访问媒体库地址。请检查地址和端口，并确认媒体库服务正在运行。"
        default:
            return error.localizedDescription
        }
    }
}
