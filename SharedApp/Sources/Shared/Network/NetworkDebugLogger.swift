import Foundation
import OpenAPIRuntime
import HTTPTypes

enum NetworkDebugLogger {
    static func logRequest(
        client: String,
        operationID: String,
        request: HTTPRequest,
        baseURL: URL
    ) {
#if DEBUG
        let url = resolvedURL(for: request, baseURL: baseURL)?.absoluteString ?? "<unresolved>"
        print("[Network][\(client)][\(operationID)] -> \(request.method.rawValue) \(url)")
        print("[Network][\(client)][\(operationID)] headers: \(headersDescription(request.headerFields))")
#endif
    }

    static func logResponse(
        client: String,
        operationID: String,
        request: HTTPRequest,
        baseURL: URL,
        response: HTTPResponse
    ) {
#if DEBUG
        let url = resolvedURL(for: request, baseURL: baseURL)?.absoluteString ?? "<unresolved>"
        print("[Network][\(client)][\(operationID)] <- \(response.status.code) \(request.method.rawValue) \(url)")
        print("[Network][\(client)][\(operationID)] response headers: \(headersDescription(response.headerFields))")
#endif
    }

    static func logError(
        client: String,
        operationID: String,
        request: HTTPRequest,
        baseURL: URL,
        error: Error
    ) {
#if DEBUG
        let url = resolvedURL(for: request, baseURL: baseURL)?.absoluteString ?? "<unresolved>"
        print("[Network][\(client)][\(operationID)] xx \(request.method.rawValue) \(url)")
        print("[Network][\(client)][\(operationID)] error: \(error)")
#endif
    }

    static func logURLRequest(_ request: URLRequest, label: String) {
#if DEBUG
        print("[Network][\(label)] -> \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<nil>")")
        print("[Network][\(label)] headers: \(request.allHTTPHeaderFields ?? [:])")
#endif
    }

    static func logURLResponse(
        _ response: HTTPURLResponse,
        request: URLRequest,
        label: String
    ) {
#if DEBUG
        print("[Network][\(label)] <- \(response.statusCode) \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<nil>")")
        print("[Network][\(label)] response headers: \(response.allHeaderFields)")
#endif
    }

    static func logURLRequestError(
        _ error: Error,
        request: URLRequest,
        label: String
    ) {
#if DEBUG
        print("[Network][\(label)] xx \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<nil>")")
        print("[Network][\(label)] error: \(error)")
#endif
    }

    private static func resolvedURL(for request: HTTPRequest, baseURL: URL) -> URL? {
        if let scheme = request.scheme,
           let authority = request.authority,
           let path = request.path,
           var components = URLComponents() as URLComponents? {
            components.scheme = scheme
            components.percentEncodedHost = authority
            components.percentEncodedPath = path
            if let url = components.url {
                return url
            }
        }
        guard let path = request.path else {
            return baseURL
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        if path.hasPrefix("/") {
            components.path = path
        } else {
            let suffix = components.path.hasSuffix("/") ? "" : "/"
            components.path += suffix + path
        }
        return components.url
    }

    private static func headersDescription(_ fields: HTTPFields) -> [String: String] {
        var dictionary: [String: String] = [:]
        for field in fields {
            dictionary[field.name.canonicalName] = field.value
        }
        return dictionary
    }
}
