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

func makeRawDandanClient() throws -> DandanClient {
    DandanClient(
        serverURL: try Servers.Server1.url(),
        configuration: .init(
            dateTranscoder: LenientRFC3339Transcoder()
        ),
        transport: SignatureMiddleware(
            appId: Secrets.dandanAppId,
            appSecret: Secrets.dandanAppSecret,
            next: URLSessionTransport()
        )
    )
}

extension DandanClient: DependencyKey {
    public static let liveValue: Self = {
        do {
            return try makeRawDandanClient()
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

extension Operations.BangumiGetSeasonBangumiOfAnime.Output.Ok: SuccessfulResponse {}

extension Operations.BangumiGetSeasonBangumiOfAnime.Output.Ok.Body: SuccessResponseBody {
    public var model: Components.Schemas.BangumiListResponse? {
        return try? self.json
    }
}

extension Operations.BangumiGetSeasonBangumiOfAnime.Output: SuccessExtractable {
    public var successModel: Components.Schemas.BangumiListResponse? {
        guard case .ok(let response) = self else {
            return nil
        }
        return response.body.model
    }
}

extension Operations.BangumiGetSeasonBangumiOfAnime.Output: UndocumentedCase {
    var statusCode: Int {
        guard case .undocumented(let statusCode, _) = self else { return -1 }
        return statusCode
    }
}

extension Operations.SearchSearchAnime.Output.Ok: SuccessfulResponse {}

extension Operations.SearchSearchAnime.Output.Ok.Body: SuccessResponseBody {
    public var model: Components.Schemas.SearchAnimeResponse? {
        return try? self.json
    }
}

extension Operations.SearchSearchAnime.Output: SuccessExtractable {
    public var successModel: Components.Schemas.SearchAnimeResponse? {
        guard case .ok(let response) = self else {
            return nil
        }
        return response.body.model
    }
}

extension Operations.SearchSearchAnime.Output: UndocumentedCase {
    var statusCode: Int {
        guard case .undocumented(let statusCode, _) = self else { return -1 }
        return statusCode
    }
}

extension Operations.BangumiGetBangumiDetails.Output.Ok: SuccessfulResponse {}

extension Operations.BangumiGetBangumiDetails.Output.Ok.Body: SuccessResponseBody {
    public var model: Components.Schemas.BangumiDetailsResponse? {
        return try? self.json
    }
}

extension Operations.BangumiGetBangumiDetails.Output: SuccessExtractable {
    public var successModel: Components.Schemas.BangumiDetailsResponse? {
        guard case .ok(let response) = self else {
            return nil
        }
        return response.body.model
    }
}

extension Operations.BangumiGetBangumiDetails.Output: UndocumentedCase {
    var statusCode: Int {
        guard case .undocumented(let statusCode, _) = self else { return -1 }
        return statusCode
    }
}
