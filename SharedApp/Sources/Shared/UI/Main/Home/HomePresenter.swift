//
//  HomePresenter.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/28.
//

import Foundation
import ComposableArchitecture
import DandanApi
import DependenciesMacro
import RemoteMediaLibrary

private typealias DandanSchemas = DandanApi.Components.Schemas
private typealias RemoteLibrarySchemas = RemoteMediaLibrary.Components.Schemas

@Reducer
struct HomePresenter {

    @ObservableState
    struct State: Equatable {
        struct Banner: Equatable, Identifiable {
            let id: Int
            let title: String
            let description: String
            let imageURL: URL?
            let url: URL?
        }

        struct Season: Equatable, Identifiable {
            let year: Int
            let month: Int
            let name: String

            var id: String { "\(year)-\(month)" }
        }

        struct BangumiItem: Equatable, Identifiable {
            let animeId: Int
            let bangumiId: String?
            let title: String
            let imageURL: URL?
            let searchKeyword: String?
            let isOnAir: Bool
            let airDay: Int
            let isFavorited: Bool
            let rating: Double?

            var id: String {
                bangumiId ?? "anime-\(animeId)"
            }
        }

        struct QuickStatusItem: Equatable, Identifiable {
            let animeId: Int
            let title: String
            let imageURL: URL?
            let secondaryText: String
            let rating: Double?

            var id: String {
                "quick-\(animeId)"
            }

            var detailSummary: HomeBangumiDetailPresenter.State.Summary {
                .init(
                    animeId: animeId,
                    bangumiId: nil,
                    title: title,
                    imageURL: imageURL,
                    typeDescription: nil,
                    rating: rating,
                    isFavorited: false
                )
            }
        }

        struct SearchResult: Equatable, Identifiable {
            let animeId: Int
            let bangumiId: String?
            let title: String
            let typeDescription: String?
            let imageURL: URL?
            let startDate: Date?
            let episodeCount: Int?
            let rating: Double?
            let isFavorited: Bool

            var id: String {
                bangumiId ?? "search-\(animeId)"
            }
        }

        enum ScheduleDay: Int, CaseIterable, Equatable, Identifiable {
            case sunday = 0
            case monday = 1
            case tuesday = 2
            case wednesday = 3
            case thursday = 4
            case friday = 5
            case saturday = 6
            case all = 7

            var id: Int { rawValue }

            var title: String {
                switch self {
                case .sunday: "周日"
                case .monday: "周一"
                case .tuesday: "周二"
                case .wednesday: "周三"
                case .thursday: "周四"
                case .friday: "周五"
                case .saturday: "周六"
                case .all: "全部"
                }
            }

            static func today(calendar: Calendar = .autoupdatingCurrent) -> Self {
                let weekday = calendar.component(.weekday, from: .now)
                return Self(rawValue: max(weekday - 1, 0)) ?? .all
            }
        }

        var banners: [Banner] = []
        var unwatchedItems: [QuickStatusItem] = []
        var continueWatchingItems: [QuickStatusItem] = []
        var seasons: [Season] = []
        var selectedSeasonID: Season.ID?
        var seasonItems: [BangumiItem] = []
        var selectedScheduleDay: ScheduleDay = .today()
        var seasonFilterQuery = ""
        var homeSearchQuery = ""
        var homeSearchResults: [SearchResult] = []
        var path = StackState<Path.State>()
        var requestedPlayerState: PlaybackRequest?

        var isLoadingHomepage = false
        var isLoadingSeason = false
        var isSearching = false
        var hasLoadedOnce = false

        var homepageErrorMessage: String?
        var seasonErrorMessage: String?
        var searchErrorMessage: String?
        var quickStatusErrorMessage: String?

        var selectedSeason: Season? {
            guard let selectedSeasonID else { return nil }
            return seasons.first(where: { $0.id == selectedSeasonID })
        }

        var trimmedSeasonFilterQuery: String {
            seasonFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var trimmedHomeSearchQuery: String {
            homeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var filteredSeasonItems: [BangumiItem] {
            let terms = normalizedSearchTerms(from: trimmedSeasonFilterQuery)
            let dayFiltered: [BangumiItem]
            if selectedScheduleDay == .all {
                dayFiltered = seasonItems
            } else {
                dayFiltered = seasonItems.filter { $0.airDay == selectedScheduleDay.rawValue }
            }
            guard !terms.isEmpty else {
                return dayFiltered
            }
            return dayFiltered.filter { item in
                let haystacks = [
                    item.title,
                    item.searchKeyword ?? "",
                    item.bangumiId ?? ""
                ]
                .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .autoupdatingCurrent) }

                return terms.allSatisfy { term in
                    haystacks.contains(where: { $0.contains(term) })
                }
            }
        }
    }

    enum Action {
        case onAppear
        case loadCached
        case refresh
        case homepageResponse(DandanCacheMode, TaskResult<HomepagePayload>)
        case selectedSeasonChanged(State.Season.ID)
        case selectedScheduleDayChanged(State.ScheduleDay)
        case setSeasonFilterQuery(String)
        case loadSeason(State.Season, DandanCacheMode)
        case seasonResponse(TaskResult<[State.BangumiItem]>)
        case setHomeSearchQuery(String)
        case performSearch(String)
        case searchResponse(String, TaskResult<[State.SearchResult]>)
        case remoteHighlightsResponse(TaskResult<RemoteHighlightsPayload>)
        case showBangumiDetail(HomeBangumiDetailPresenter.State.Summary)
        case playbackRequestHandled
        case path(StackAction<Path.State, Path.Action>)
    }

    @Dependency(\.dandanCachedService) var dandanService
    @Dependency(\.continuousClock) var clock
    @Dependency(\.remoteLibraryConfigurationOperation) var configurationOperation
    @Dependency(\.remoteMediaLibraryClient) var remoteClient

    private enum CancelID {
        case homepage
        case season
        case search
        case remoteHighlights
    }

    @Reducer
    struct Path {
        enum State: Equatable {
            case bangumiDetail(HomeBangumiDetailPresenter.State)
        }

        enum Action {
            case bangumiDetail(HomeBangumiDetailPresenter.Action)
        }

        var body: some ReducerOf<Self> {
            Scope(state: /State.bangumiDetail, action: /Action.bangumiDetail) {
                HomeBangumiDetailPresenter()
            }
        }
    }

    struct HomepagePayload {
        let banners: [State.Banner]
        let seasons: [State.Season]
    }

    struct RemoteHighlightsPayload {
        let unwatchedItems: [State.QuickStatusItem]
        let continueWatchingItems: [State.QuickStatusItem]
    }

    var body: some ReducerOf<Self> {
        Reduce { (state: inout State, action: Action) -> Effect<Action> in
            switch action {
            case let .showBangumiDetail(summary):
                state.path.append(.bangumiDetail(.init(summary: summary)))
                return .none

            case let .path(.element(id: _, action: .bangumiDetail(.delegate(.startPlayback(playerState))))):
                state.requestedPlayerState = playerState
                return .none

            case .path:
                return .none

            case .playbackRequestHandled:
                state.requestedPlayerState = nil
                return .none

            case .onAppear:
                guard !state.hasLoadedOnce else { return .none }
                return .send(.loadCached)

            case .loadCached:
                state.isLoadingHomepage = true
                state.homepageErrorMessage = nil
                state.quickStatusErrorMessage = nil
                return .merge(
                    .run { [dandanService] send in
                        await send(
                            .homepageResponse(
                                .standard,
                                await TaskResult {
                                    let response = try await dandanService.homepage(.standard)
                                    return mapHomepagePayload(response)
                                }
                            )
                        )
                    }
                    .cancellable(id: CancelID.homepage, cancelInFlight: true),
                    .run { [configurationOperation, remoteClient] send in
                        await send(
                            .remoteHighlightsResponse(
                                await TaskResult {
                                    try await fetchRemoteHighlights(
                                        configurationOperation: configurationOperation,
                                        remoteClient: remoteClient
                                    )
                                }
                            )
                        )
                    }
                    .cancellable(id: CancelID.remoteHighlights, cancelInFlight: true)
                )

            case .refresh:
                state.isLoadingHomepage = true
                state.homepageErrorMessage = nil
                state.quickStatusErrorMessage = nil
                return .merge(
                    .run { [dandanService] send in
                        await send(
                            .homepageResponse(
                                .forceRefresh,
                                await TaskResult {
                                    let response = try await dandanService.homepage(.forceRefresh)
                                    return mapHomepagePayload(response)
                                }
                            )
                        )
                    }
                    .cancellable(id: CancelID.homepage, cancelInFlight: true),
                    .run { [configurationOperation, remoteClient] send in
                        await send(
                            .remoteHighlightsResponse(
                                await TaskResult {
                                    try await fetchRemoteHighlights(
                                        configurationOperation: configurationOperation,
                                        remoteClient: remoteClient
                                    )
                                }
                            )
                        )
                    }
                    .cancellable(id: CancelID.remoteHighlights, cancelInFlight: true)
                )

            case let .homepageResponse(mode, .success(payload)):
                state.isLoadingHomepage = false
                state.hasLoadedOnce = true
                state.banners = payload.banners
                state.seasons = payload.seasons
                state.homepageErrorMessage = nil

                let preferredSeasonID = resolvePreferredSeasonID(
                    seasons: payload.seasons,
                    currentSelection: state.selectedSeasonID
                )
                state.selectedSeasonID = preferredSeasonID

                guard let season = state.selectedSeason else {
                    state.seasonItems = []
                    return .none
                }
                return .send(.loadSeason(season, mode))

            case let .homepageResponse(_, .failure(error)):
                state.isLoadingHomepage = false
                state.homepageErrorMessage = error.localizedDescription
                return .none

            case let .remoteHighlightsResponse(.success(payload)):
                state.unwatchedItems = payload.unwatchedItems
                state.continueWatchingItems = payload.continueWatchingItems
                state.quickStatusErrorMessage = nil
                return .none

            case let .remoteHighlightsResponse(.failure(error)):
                state.unwatchedItems = []
                state.continueWatchingItems = []
                state.quickStatusErrorMessage = error.localizedDescription
                return .none

            case let .selectedSeasonChanged(id):
                guard let season = state.seasons.first(where: { $0.id == id }) else {
                    return .none
                }
                state.selectedSeasonID = id
                return .send(.loadSeason(season, .standard))

            case let .selectedScheduleDayChanged(day):
                state.selectedScheduleDay = day
                return .none

            case let .setSeasonFilterQuery(query):
                state.seasonFilterQuery = query
                return .none

            case let .loadSeason(season, mode):
                state.isLoadingSeason = true
                state.seasonErrorMessage = nil
                return .run { [dandanService] send in
                    await send(
                        .seasonResponse(
                            await TaskResult {
                                let response = try await dandanService.seasonBangumi(season.year, season.month, mode)
                                return mapBangumiItems(response.value2.bangumiList)
                            }
                        )
                    )
                }
                .cancellable(id: CancelID.season, cancelInFlight: true)

            case let .seasonResponse(.success(items)):
                state.isLoadingSeason = false
                state.seasonItems = items
                state.seasonErrorMessage = nil
                return .none

            case let .seasonResponse(.failure(error)):
                state.isLoadingSeason = false
                state.seasonItems = []
                state.seasonErrorMessage = error.localizedDescription
                return .none

            case let .setHomeSearchQuery(query):
                state.homeSearchQuery = query
                state.searchErrorMessage = nil

                let trimmed = state.trimmedHomeSearchQuery
                guard trimmed.count >= 2 else {
                    state.isSearching = false
                    state.homeSearchResults = []
                    return .cancel(id: CancelID.search)
                }

                state.isSearching = true
                return .run { send in
                    try await clock.sleep(for: .milliseconds(350))
                    await send(.performSearch(trimmed))
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .performSearch(query):
                guard !query.isEmpty else { return .none }
                return .run { [dandanService] send in
                    await send(
                        .searchResponse(
                            query,
                            await TaskResult {
                                let response = try await dandanService.searchAnime(query, .standard)
                                return mapSearchResults(response.value2.animes)
                            }
                        )
                    )
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .searchResponse(query, .success(results)):
                guard query == state.trimmedHomeSearchQuery else { return .none }
                state.isSearching = false
                state.homeSearchResults = results
                state.searchErrorMessage = nil
                return .none

            case let .searchResponse(query, .failure(error)):
                guard query == state.trimmedHomeSearchQuery else { return .none }
                state.isSearching = false
                state.homeSearchResults = []
                state.searchErrorMessage = error.localizedDescription
                return .none
            }
        }
        .forEach(\.path, action: /Action.path) {
            Path()
        }
    }
}

private func mapHomepagePayload(_ response: DandanSchemas.HomepageResponseV2) -> HomePresenter.HomepagePayload {
    .init(
        banners: mapBanners(response.value2.banners),
        seasons: mapSeasons(response.value2.bangumiSeasons)
    )
}

private func mapBanners(_ banners: [DandanSchemas.BannerPageItem]?) -> [HomePresenter.State.Banner] {
    (banners ?? []).compactMap { item -> HomePresenter.State.Banner? in
        guard let id = item.id else { return nil }
        return .init(
            id: Int(id),
            title: item.title ?? "弹弹公告",
            description: item.description ?? "",
            imageURL: item.imageUrl.flatMap(URL.init(string:)),
            url: item.url.flatMap(URL.init(string:))
        )
    }
}

private func mapSeasons(_ seasons: [DandanSchemas.BangumiSeason]?) -> [HomePresenter.State.Season] {
    (seasons ?? [])
        .compactMap { season -> HomePresenter.State.Season? in
            guard let year = season.year, let month = season.month else { return nil }
            let resolvedYear = Int(year)
            let resolvedMonth = Int(month)
            return HomePresenter.State.Season(
                year: resolvedYear,
                month: resolvedMonth,
                name: season.seasonName ?? formattedSeasonName(year: resolvedYear, month: resolvedMonth)
            )
        }
        .sorted {
            if $0.year == $1.year {
                return $0.month > $1.month
            }
            return $0.year > $1.year
        }
}

private func mapBangumiItems(_ items: [DandanSchemas.BangumiIntro]?) -> [HomePresenter.State.BangumiItem] {
    var mapped: [HomePresenter.State.BangumiItem] = []
    for item in items ?? [] {
        guard let animeId = item.animeId else { continue }
        let resolvedRating = item.rating
        mapped.append(
            .init(
                animeId: Int(animeId),
                bangumiId: item.bangumiId,
                title: item.animeTitle ?? "未命名番剧",
                imageURL: item.imageUrl.flatMap(URL.init(string:)),
                searchKeyword: item.searchKeyword,
                isOnAir: item.isOnAir ?? false,
                airDay: Int(item.airDay ?? -1),
                isFavorited: item.isFavorited ?? false,
                rating: resolvedRating
            )
        )
    }
    return mapped
}

private func mapBangumiItems(_ items: [DandanSchemas.BangumiQueueIntroV2]?) -> [HomePresenter.State.BangumiItem] {
    (items ?? []).compactMap { item -> HomePresenter.State.BangumiItem? in
        guard let animeId = item.animeId else { return nil }
        return .init(
            animeId: Int(animeId),
            bangumiId: nil,
            title: item.animeTitle ?? "未命名番剧",
            imageURL: item.imageUrl.flatMap(URL.init(string:)),
            searchKeyword: item.episodeTitle,
            isOnAir: item.isOnAir ?? false,
            airDay: dayOfWeek(from: item.airDate),
            isFavorited: false,
            rating: nil
        )
    }
}

private func mapSearchResults(_ items: [DandanSchemas.SearchAnimeDetails]?) -> [HomePresenter.State.SearchResult] {
    (items ?? []).compactMap { item -> HomePresenter.State.SearchResult? in
        guard let animeId = item.animeId else { return nil }
        return .init(
            animeId: Int(animeId),
            bangumiId: item.bangumiId,
            title: item.animeTitle ?? "未命名番剧",
            typeDescription: item.typeDescription,
            imageURL: item.imageUrl.flatMap(URL.init(string:)),
            startDate: item.startDate,
            episodeCount: item.episodeCount.map(Int.init),
            rating: item.rating,
            isFavorited: item.isFavorited ?? false
        )
    }
}

private func resolvePreferredSeasonID(
    seasons: [HomePresenter.State.Season],
    currentSelection: HomePresenter.State.Season.ID?
) -> HomePresenter.State.Season.ID? {
    if let currentSelection, seasons.contains(where: { $0.id == currentSelection }) {
        return currentSelection
    }

    let currentDate = Date()
    let calendar = Calendar.autoupdatingCurrent
    let currentYear = calendar.component(.year, from: currentDate)
    let currentMonth = normalizedSeasonMonth(for: calendar.component(.month, from: currentDate))
    if let currentSeason = seasons.first(where: { $0.year == currentYear && $0.month == currentMonth }) {
        return currentSeason.id
    }
    return seasons.first?.id
}

private func normalizedSeasonMonth(for month: Int) -> Int {
    switch month {
    case 1...3: 1
    case 4...6: 4
    case 7...9: 7
    default: 10
    }
}

private func formattedSeasonName(year: Int, month: Int) -> String {
    let season: String
    switch month {
    case 1: season = "冬季"
    case 4: season = "春季"
    case 7: season = "夏季"
    case 10: season = "秋季"
    default: season = "\(month)月"
    }
    return "\(year) \(season)"
}

private func dayOfWeek(from date: Date?) -> Int {
    guard let date else { return -1 }
    return max(Calendar.autoupdatingCurrent.component(.weekday, from: date) - 1, 0)
}

private func normalizedSearchTerms(from query: String) -> [String] {
    query
        .split(whereSeparator: \.isWhitespace)
        .map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .autoupdatingCurrent)
        }
        .filter { !$0.isEmpty }
}

private func fetchRemoteHighlights(
    configurationOperation: RemoteLibraryConfigurationOperation,
    remoteClient: RemoteMediaLibraryClient
) async throws -> HomePresenter.RemoteHighlightsPayload {
    let configurationRecord = try await MainActor.run {
        try configurationOperation.fetchDefault()
    }
    guard let configurationRecord,
          let baseURL = URL(string: configurationRecord.url) else {
        return .init(unwatchedItems: [], continueWatchingItems: [])
    }

    let token = configurationRecord.apiKey
    async let continueWatchingResponse = remoteClient.fetchBangumiList(baseURL, token, .lastPlay)
    async let recentlyUpdatedResponse = remoteClient.fetchBangumiList(baseURL, token, .lastUpdate)

    let continueWatching = try await continueWatchingResponse
    let recentlyUpdated = try await recentlyUpdatedResponse

    return .init(
        unwatchedItems: mapQuickStatusItems(
            recentlyUpdated.filter { $0.allEpisodesWatched != true },
            baseURL: baseURL,
            fallbackText: "最近更新"
        ),
        continueWatchingItems: mapQuickStatusItems(
            continueWatching,
            baseURL: baseURL,
            fallbackText: "最近播放"
        )
    )
}

private func mapQuickStatusItems(
    _ items: [RemoteLibrarySchemas.LibraryBangumiSummary],
    baseURL: URL,
    fallbackText: String
) -> [HomePresenter.State.QuickStatusItem] {
    items.compactMap { item in
        guard let animeId = item.animeId else { return nil }
        return .init(
            animeId: Int(animeId),
            title: item.title ?? "未知动画",
            imageURL: makeRemoteCoverURL(baseURL: baseURL, path: item.cover),
            secondaryText: quickStatusSecondaryText(item, fallbackText: fallbackText),
            rating: item.rating.map(Double.init)
        )
    }
}

private func quickStatusSecondaryText(
    _ item: RemoteLibrarySchemas.LibraryBangumiSummary,
    fallbackText: String
) -> String {
    if let watched = item.episodeWatched,
       let total = item.episodeTotal,
       total > 0 {
        return "进度 \(watched)/\(total)"
    }
    return fallbackText
}

private func makeRemoteCoverURL(baseURL: URL, path: String?) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    if let url = URL(string: path), url.scheme != nil {
        return url
    }
    return URL(string: path, relativeTo: baseURL)?.absoluteURL
}

extension HomePresenter.State.BangumiItem {
    var detailSummary: HomeBangumiDetailPresenter.State.Summary {
        .init(
            animeId: animeId,
            bangumiId: bangumiId,
            title: title,
            imageURL: imageURL,
            typeDescription: nil,
            rating: rating,
            isFavorited: isFavorited
        )
    }
}

extension HomePresenter.State.SearchResult {
    var detailSummary: HomeBangumiDetailPresenter.State.Summary {
        .init(
            animeId: animeId,
            bangumiId: bangumiId,
            title: title,
            imageURL: imageURL,
            typeDescription: typeDescription,
            rating: rating,
            isFavorited: isFavorited
        )
    }
}
