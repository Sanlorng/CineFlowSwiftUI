import Foundation

public enum APIError: Error, LocalizedError, Equatable {
    
    // MARK: - Specific API Business Errors
    
    /// 401 未授权 - 例如 token 过期或无效
    case unauthorized
    
    /// 403 禁止访问 - 用户权限不足
    case forbidden
    
    /// 404 未找到 - 请求的资源不存在
    case notFound
    
    // MARK: - Generic Server & Network Errors
    
    /// 服务器端错误 (5xx)
    case serverError(statusCode: Int)
    
    /// 底层网络错误 (例如，无网络连接)
    case networkError(underlyingError: NSError)
    
    /// 解码失败 - 服务器返回的数据格式不正确
    case decodingError(underlyingError: Error)
    
    /// 预期之外的响应
    case unexpectedResponse(String)
    
    // MARK: - User-Facing Error Descriptions
    
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Authentication failed. Please log in again."
        case .forbidden:
            return "You do not have permission to access this resource."
        case .notFound:
            return "The requested resource could not be found."
        case .serverError(let statusCode):
            return "The server encountered an error (Status Code: \(statusCode)). Please try again later."
        case .networkError(let nsError):
            // 提供对常见网络错误的更友好提示
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet:
                    return "No internet connection. Please check your connection and try again."
                case NSURLErrorTimedOut:
                    return "The request timed out. Please try again."
                default:
                    break
                }
            }
            return "A network error occurred: \(nsError.localizedDescription)"
        case .decodingError:
            return "Failed to process data from the server. Please try again."
        case .unexpectedResponse(let reason):
            return "An unexpected error occurred: \(reason)"
        }
    }
    
    // Equatable conformance for testing
    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.forbidden, .forbidden): return true
        case (.notFound, .notFound): return true
        case (.serverError(let l), .serverError(let r)): return l == r
        case (.networkError(let l), .networkError(let r)): return l.domain == r.domain && l.code == r.code
        case (.decodingError, .decodingError): return true // Simplified for example
        case (.unexpectedResponse(let l), .unexpectedResponse(let r)): return l == r
        default: return false
        }
    }
}