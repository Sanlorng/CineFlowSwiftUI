//
//  OpenApi.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/29.
//


import Foundation
import OpenAPIRuntime

/// A protocol that represents the content of a successful API response body.
/// The `swift-openapi-generator`'s `body.json` properties will conform to this.
public protocol SuccessResponseBody {
    /// The specific, decoded model type (e.g., Components.Schemas.User).
    associatedtype Model
    
    /// A property to access the decoded model.
    var model: Model? { get }
}

/// A protocol that represents a successful API response case (e.g., `Output.Ok`).
/// It must contain a body that conforms to `SuccessResponseBody`.
public protocol SuccessfulResponse {
    associatedtype Body: SuccessResponseBody
    var body: Body { get }
}

/// A protocol that the top-level `Output` enum will conform to.
/// It provides a single computed property to extract the successful model, if it exists.
public protocol SuccessExtractable {
    associatedtype Model
    
    /// Returns the final, decoded model if the response was a success, otherwise nil.
    var successModel: Model? { get }
}

public protocol BaseAPIProtocol: Sendable {}

extension BaseAPIProtocol {
    
    func fetch<Output: SuccessExtractable>(
        _ apiCall: @escaping () async throws -> Output
    ) async throws -> Output.Model {
        
        let output: Output
        do {
            output = try await apiCall()
        } catch {
            // 将底层的网络错误包装成我们的 APIError
            throw APIError.networkError(underlyingError: error as NSError)
        }
        
        // 成功提取模型
        if let model = output.successModel {
            return model
        }
        
        // --- 错误转换逻辑 ---
        // 如果提取失败，我们在这里将 OpenAPI 的 Output 转换为具体的 APIError
        // 这是一个简化的示例，你可以根据需要扩展它
        
        // 尝试从 `undocumented` case 中获取状态码
        if let undocumentedOutput = output as? UndocumentedCase {
            switch undocumentedOutput.statusCode {
            case 401: throw APIError.unauthorized
            case 403: throw APIError.forbidden
            case 404: throw APIError.notFound
            case 500...599: throw APIError.serverError(statusCode: undocumentedOutput.statusCode)
            default: break
            }
        }
        
        // 最终的兜底错误
        throw APIError.unexpectedResponse("The response was not a known success or handled error case.")
    }
}

protocol UndocumentedCase {
    var statusCode: Int { get }
}
