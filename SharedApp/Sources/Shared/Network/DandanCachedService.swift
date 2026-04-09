import Foundation
import ComposableArchitecture
import DandanApi

typealias DandanCacheSchemas = DandanApi.Components.Schemas

struct DandanCachedService {
    var homepage: @Sendable (_ mode: DandanCacheMode) async throws -> DandanCacheSchemas.HomepageResponseV2
    var seasonBangumi: @Sendable (_ year: Int, _ month: Int, _ mode: DandanCacheMode) async throws -> DandanCacheSchemas.BangumiListResponse
    var searchAnime: @Sendable (_ keyword: String, _ mode: DandanCacheMode) async throws -> DandanCacheSchemas.SearchAnimeResponse
    var bangumiDetails: @Sendable (_ bangumiId: String, _ mode: DandanCacheMode) async throws -> DandanCacheSchemas.BangumiDetailsResponse
}

extension DandanCachedService: DependencyKey {
    static let liveValue: Self = {
        do {
            let client = try makeRawDandanClient()
            let store = DandanCacheStore()

            return Self(
                homepage: { mode in
                    let data = try await store.data(
                        for: "homepage",
                        policy: .homepage,
                        mode: mode
                    ) {
                        let response = try await client.fetch {
                            try await client.homepageGetHomepage()
                        }
                        return .init(
                            data: try JSONEncoder().encode(response),
                            policy: .homepage
                        )
                    }
                    return try JSONDecoder().decode(DandanCacheSchemas.HomepageResponseV2.self, from: data)
                },
                seasonBangumi: { year, month, mode in
                    let data = try await store.data(
                        for: "season::\(year)-\(month)",
                        policy: .season(year: year, month: month),
                        mode: mode
                    ) {
                        let response = try await client.fetch {
                            try await client.bangumiGetSeasonBangumiOfAnime(
                                .init(
                                    path: .init(year: Int32(year), month: Int32(month)),
                                    query: .init(filterAdultContent: false)
                                )
                            )
                        }
                        return .init(
                            data: try JSONEncoder().encode(response),
                            policy: .season(year: year, month: month)
                        )
                    }
                    return try JSONDecoder().decode(DandanCacheSchemas.BangumiListResponse.self, from: data)
                },
                searchAnime: { keyword, mode in
                    let normalizedKeyword = normalizedCacheKeyword(keyword)
                    let data = try await store.data(
                        for: "search::\(normalizedKeyword)",
                        policy: .search(hasResults: true),
                        mode: mode
                    ) {
                        let response = try await client.fetch {
                            try await client.searchSearchAnime(
                                .init(query: .init(keyword: normalizedKeyword, _type: nil))
                            )
                        }
                        let hasResults = !(response.value2.animes ?? []).isEmpty
                        return .init(
                            data: try JSONEncoder().encode(response),
                            policy: .search(hasResults: hasResults)
                        )
                    }
                    return try JSONDecoder().decode(DandanCacheSchemas.SearchAnimeResponse.self, from: data)
                },
                bangumiDetails: { bangumiId, mode in
                    let data = try await store.data(
                        for: "detail::\(bangumiId)",
                        policy: .details,
                        mode: mode
                    ) {
                        let response = try await client.fetch {
                            try await client.bangumiGetBangumiDetails(
                                .init(path: .init(bangumiId: bangumiId))
                            )
                        }
                        return .init(
                            data: try JSONEncoder().encode(response),
                            policy: .details(for: response)
                        )
                    }
                    return try JSONDecoder().decode(DandanCacheSchemas.BangumiDetailsResponse.self, from: data)
                }
            )
        } catch {
            fatalError("Failed to create DandanCachedService: \(error)")
        }
    }()

    static let previewValue = liveValue

    static let testValue = Self(
        homepage: { _ in
            throw APIError.unexpectedResponse("Unimplemented DandanCachedService.homepage")
        },
        seasonBangumi: { _, _, _ in
            throw APIError.unexpectedResponse("Unimplemented DandanCachedService.seasonBangumi")
        },
        searchAnime: { _, _ in
            throw APIError.unexpectedResponse("Unimplemented DandanCachedService.searchAnime")
        },
        bangumiDetails: { _, _ in
            throw APIError.unexpectedResponse("Unimplemented DandanCachedService.bangumiDetails")
        }
    )
}

extension DependencyValues {
    var dandanCachedService: DandanCachedService {
        get { self[DandanCachedService.self] }
        set { self[DandanCachedService.self] = newValue }
    }
}

private func normalizedCacheKeyword(_ keyword: String) -> String {
    keyword
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
}
