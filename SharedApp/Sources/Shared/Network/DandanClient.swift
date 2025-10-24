//
//  DandanClient.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/29.
//

import ComposableArchitecture
import DandanApi
import OpenAPIURLSession

typealias DandanClient = DandanApi.Client

extension DandanClient: DependencyKey {
    public static let liveValue: Self = {
        do {
            return Self(
                serverURL: try Servers.Server1.url(),
                transport: SignatureMiddleware(
                    appId: Secrets.dandanAppId, appSecret: Secrets.dandanAppSecret, next: URLSessionTransport()
                )
            )
        } catch {
            fatalError("Failed to create DandanClient: \(error)")
        }
    }()
}

extension DependencyValues {
        var dandanClient: DandanClient {
        get { self[DandanClient.self] }
        set { self[DandanClient.self] = newValue }
    }
}

extension DandanClient: BaseAPIProtocol {}

extension Operations.HomepageGetHomepage.Output.Ok: SuccessfulResponse {}

extension Operations.HomepageGetHomepage.Output.Ok.Body: SuccessResponseBody {
    public var model: Components.Schemas.HomepageResponseV2? {
        return try? self.json
    }
}

extension Operations.HomepageGetHomepage.Output: SuccessExtractable {
    public var successModel: Components.Schemas.HomepageResponseV2? {
        guard case .ok(let response) = self else {
            return nil
        }
        return response.body.model
    }
}

extension Operations.HomepageGetHomepage.Output: UndocumentedCase {
    var statusCode: Int {
        guard case .undocumented(let statusCode, _) = self else { return -1 }
        return statusCode
    }
}
