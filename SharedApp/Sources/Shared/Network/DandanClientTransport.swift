import Foundation
import OpenAPIRuntime
import CryptoKit // 导入 CryptoKit 用于 SHA256 哈希
import HTTPTypes

/// 一个 ClientTransport 中间件，用于为每个请求添加签名认证 Header。
///
/// 签名算法: base64(sha256(AppId + Timestamp + Path + AppSecret))
struct SignatureMiddleware: ClientTransport {

    private let appId: String
    private let appSecret: String
    private let next: ClientTransport

    /// 初始化方法
    /// - Parameters:
    ///   - appId: 你的应用程序 ID
    ///   - appSecret: 你的应用程序密钥
    ///   - next: 链路中的下一个 ClientTransport
    init(appId: String, appSecret: String, next: ClientTransport) {
        self.appId = appId
        self.appSecret = appSecret
        self.next = next
    }

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        
        // 1. 获取动态参数
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let path = request.path?.lowercased() ?? ""// 根据要求，路径使用小写

        // 2. 计算签名
        let signature = calculateSignature(
            appId: self.appId,
            appSecret: self.appSecret,
            timestamp: timestamp,
            path: path
        )

        // 3. 创建请求的可变副本以添加 Header
        var mutableRequest = request
        
        // 4. 添加必要的 Header
        mutableRequest.headerFields.append(.init(name: .init("X-AppId")!, value: self.appId))
        mutableRequest.headerFields.append(.init(name: .init("X-Timestamp")!, value: timestamp))
        mutableRequest.headerFields.append(.init(name: .init("X-Signature")!, value: signature))
        
        // 5. 将带有签名的请求传递给下一个 Transport
        return try await next.send(
            mutableRequest,
            body: body,
            baseURL: baseURL,
            operationID: operationID
        )
    }
    
    /// 私有辅助方法，用于计算签名
    private func calculateSignature(appId: String, appSecret: String, timestamp: String, path: String) -> String {
        // 步骤 a: 按顺序拼接字符串
        let stringToSign = "\(appId)\(timestamp)\(path)\(appSecret)"
        
        // 步骤 b: 使用 SHA256 哈希
        // 将字符串转换为 Data
        guard let dataToHash = stringToSign.data(using: .utf8) else {
            // 在实际应用中，这里应该有更健壮的错误处理
            fatalError("Failed to convert string to data for hashing.")
        }
        // 计算 SHA256 哈希值
        let digest = SHA256.hash(data: dataToHash)
        
        // 步骤 c: 将哈希结果转换为 Base64 编码
        let signature = Data(digest).base64EncodedString()
        
        return signature
    }
}