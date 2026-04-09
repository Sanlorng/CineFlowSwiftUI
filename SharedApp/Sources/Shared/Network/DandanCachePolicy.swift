import Foundation
import DandanApi

enum DandanCacheMode: Sendable {
    case standard
    case forceRefresh
}

enum DandanCacheBehavior: Sendable {
    case staleWhileRevalidate
    case cacheFirst
}

struct DandanCachePolicy: Sendable {
    let behavior: DandanCacheBehavior
    let freshTTL: TimeInterval
    let staleGraceTTL: TimeInterval

    static let homepage = Self(
        behavior: .staleWhileRevalidate,
        freshTTL: 30 * 60,
        staleGraceTTL: 5.5 * 60 * 60
    )

    static func season(
        year: Int,
        month: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Self {
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = normalizedSeasonMonth(for: calendar.component(.month, from: now))
        let isCurrentSeason = year == currentYear && month == currentMonth

        return Self(
            behavior: .staleWhileRevalidate,
            freshTTL: isCurrentSeason ? 60 * 60 : 24 * 60 * 60,
            staleGraceTTL: isCurrentSeason ? 11 * 60 * 60 : 6 * 24 * 60 * 60
        )
    }

    static func search(hasResults: Bool) -> Self {
        Self(
            behavior: .cacheFirst,
            freshTTL: hasResults ? 6 * 60 * 60 : 30 * 60,
            staleGraceTTL: hasResults ? 18 * 60 * 60 : 5.5 * 60 * 60
        )
    }

    static let details = Self(
        behavior: .staleWhileRevalidate,
        freshTTL: 12 * 60 * 60,
        staleGraceTTL: 60 * 60 * 60
    )

    static func details(
        for response: DandanApi.Components.Schemas.BangumiDetailsResponse,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Self {
        guard response.value1.success != false,
              (response.value1.errorCode ?? 0) == 0,
              let bangumiPayload = response.value2.bangumi else {
            return .details
        }

        let bangumi: DandanApi.Components.Schemas.BangumiDetails
        switch bangumiPayload {
        case let .BangumiDetails(value):
            bangumi = value
        }

        let detail = bangumi.value2
        let currentSeason = (
            year: calendar.component(.year, from: now),
            month: normalizedSeasonMonth(for: calendar.component(.month, from: now))
        )

        let seasonAirDates = (detail.seasons ?? []).compactMap { $0.airDate }
        let episodeAirDates = (detail.episodes ?? []).compactMap { $0.airDate }
        let allAirDates = seasonAirDates + episodeAirDates

        let hasCurrentSeason = allAirDates.contains { airDate in
            calendar.component(.year, from: airDate) == currentSeason.year
                && normalizedSeasonMonth(for: calendar.component(.month, from: airDate)) == currentSeason.month
        }

        let latestAirDate = allAirDates.max()
        let isRecentUpdateDay: Bool
        if let latestAirDate, latestAirDate <= now {
            isRecentUpdateDay = now.timeIntervalSince(latestAirDate) <= 48 * 60 * 60
        } else {
            isRecentUpdateDay = false
        }

        if hasCurrentSeason || isRecentUpdateDay {
            return Self(
                behavior: .staleWhileRevalidate,
                freshTTL: 60 * 60,
                staleGraceTTL: 23 * 60 * 60
            )
        }

        if let latestAirDate, latestAirDate <= now {
            let age = now.timeIntervalSince(latestAirDate)
            if age <= 365 * 24 * 60 * 60 {
                return Self(
                    behavior: .staleWhileRevalidate,
                    freshTTL: 24 * 60 * 60,
                    staleGraceTTL: 2 * 24 * 60 * 60
                )
            }
        }

        return Self(
            behavior: .staleWhileRevalidate,
            freshTTL: 3 * 24 * 60 * 60,
            staleGraceTTL: 4 * 24 * 60 * 60
        )
    }
}

private func normalizedSeasonMonth(for month: Int) -> Int {
    switch month {
    case 1...3: 1
    case 4...6: 4
    case 7...9: 7
    default: 10
    }
}
