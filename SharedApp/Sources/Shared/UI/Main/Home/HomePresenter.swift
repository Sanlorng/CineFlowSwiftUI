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
        var unwatchedItems: [BangumiItem] = []
        var seasons: [Season] = []
        var selectedSeasonID: Season.ID?
        var seasonItems: [BangumiItem] = []
        var selectedScheduleDay: ScheduleDay = .today()
        var seasonFilterQuery = ""
        var homeSearchQuery = ""
        var homeSearchResults: [SearchResult] = []

        var isLoadingHomepage = false
        var isLoadingSeason = false
        var isSearching = false
        var hasLoadedOnce = false

        var homepageErrorMessage: String?
        var seasonErrorMessage: String?
        var searchErrorMessage: String?

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
        case refresh
        case homepageResponse(TaskResult<HomepagePayload>)
        case selectedSeasonChanged(State.Season.ID)
        case selectedScheduleDayChanged(State.ScheduleDay)
        case setSeasonFilterQuery(String)
        case loadSeason(State.Season)
        case seasonResponse(TaskResult<[State.BangumiItem]>)
        case setHomeSearchQuery(String)
        case performSearch(String)
        case searchResponse(String, TaskResult<[State.SearchResult]>)
    }

    @Dependency(\.dandanClient) var dandanClient
    @Dependency(\.continuousClock) var clock

    private enum CancelID {
        case homepage
        case season
        case search
    }

    struct HomepagePayload {
        let banners: [State.Banner]
        let unwatchedItems: [State.BangumiItem]
        let seasons: [State.Season]
    }

    var body: some ReducerOf<Self> {
        Reduce { (state: inout State, action: Action) -> Effect<Action> in
            switch action {
            case .onAppear:
                guard !state.hasLoadedOnce else { return .none }
                return .send(.refresh)

            case .refresh:
                state.isLoadingHomepage = true
                state.homepageErrorMessage = nil
                return .run { send in
                    await send(
                        .homepageResponse(
                            await TaskResult {
                                let response = try await dandanClient.fetch {
                                    try await dandanClient.homepageGetHomepage()
                                }
                                return mapHomepagePayload(response)
                            }
                        )
                    )
                }
                .cancellable(id: CancelID.homepage, cancelInFlight: true)

            case let .homepageResponse(.success(payload)):
                state.isLoadingHomepage = false
                state.hasLoadedOnce = true
                state.banners = payload.banners
                state.unwatchedItems = payload.unwatchedItems
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
                return .send(.loadSeason(season))

            case let .homepageResponse(.failure(error)):
                state.isLoadingHomepage = false
                state.homepageErrorMessage = error.localizedDescription
                return .none

            case let .selectedSeasonChanged(id):
                guard let season = state.seasons.first(where: { $0.id == id }) else {
                    return .none
                }
                state.selectedSeasonID = id
                return .send(.loadSeason(season))

            case let .selectedScheduleDayChanged(day):
                state.selectedScheduleDay = day
                return .none

            case let .setSeasonFilterQuery(query):
                state.seasonFilterQuery = query
                return .none

            case let .loadSeason(season):
                state.isLoadingSeason = true
                state.seasonErrorMessage = nil
                return .run { send in
                    await send(
                        .seasonResponse(
                            await TaskResult {
                                let response = try await dandanClient.fetch {
                                    try await dandanClient.bangumiGetSeasonBangumiOfAnime(
                                        .init(
                                            path: .init(year: Int32(season.year), month: Int32(season.month)),
                                            query: .init(filterAdultContent: false)
                                        )
                                    )
                                }
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
                return .run { send in
                    await send(
                        .searchResponse(
                            query,
                            await TaskResult {
                                let response = try await dandanClient.fetch {
                                    try await dandanClient.searchSearchAnime(
                                        .init(query: .init(keyword: query, _type: nil))
                                    )
                                }
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
    }
}

private func mapHomepagePayload(_ response: Components.Schemas.HomepageResponseV2) -> HomePresenter.HomepagePayload {
    .init(
        banners: mapBanners(response.value2.banners),
        unwatchedItems: mapBangumiItems(response.value2.bangumiQueueIntroList),
        seasons: mapSeasons(response.value2.bangumiSeasons)
    )
}

private func mapBanners(_ banners: [Components.Schemas.BannerPageItem]?) -> [HomePresenter.State.Banner] {
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

private func mapSeasons(_ seasons: [Components.Schemas.BangumiSeason]?) -> [HomePresenter.State.Season] {
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

private func mapBangumiItems(_ items: [Components.Schemas.BangumiIntro]?) -> [HomePresenter.State.BangumiItem] {
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

private func mapBangumiItems(_ items: [Components.Schemas.BangumiQueueIntroV2]?) -> [HomePresenter.State.BangumiItem] {
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

private func mapSearchResults(_ items: [Components.Schemas.SearchAnimeDetails]?) -> [HomePresenter.State.SearchResult] {
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
