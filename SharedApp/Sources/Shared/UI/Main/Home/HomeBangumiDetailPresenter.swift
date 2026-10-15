//
//  HomeBangumiDetailPresenter.swift
//  CineFlowPackage
//
//  Created by Codex on 2026/4/9.
//

import Foundation
import ComposableArchitecture
import DandanApi
import RemoteMediaLibrary

typealias HomeDetailDandanSchemas = DandanApi.Components.Schemas
typealias HomeDetailRemoteSchemas = RemoteMediaLibrary.Components.Schemas

@Reducer
struct HomeBangumiDetailPresenter {

    @Dependency(\.dandanCachedService) var dandanService
    @Dependency(\.remoteLibraryConfigurationOperation) var configurationOperation
    @Dependency(\.remoteMediaLibraryClient) var remoteClient

    @ObservableState
    struct State: Equatable {
        struct Summary: Equatable, Identifiable {
            let animeId: Int
            let bangumiId: String?
            let title: String
            let imageURL: URL?
            let typeDescription: String?
            let rating: Double?
            let isFavorited: Bool

            var id: String {
                bangumiId ?? "anime-\(animeId)"
            }

            var requestIdentifier: String {
                bangumiId ?? String(animeId)
            }
        }

        struct Detail: Equatable {
            struct AlternativeTitle: Equatable, Identifiable {
                let language: String?
                let title: String

                var id: String {
                    "\(language ?? "unknown")-\(title)"
                }
            }

            struct SiteRating: Equatable, Identifiable {
                let source: String
                let value: Double

                var id: String { source }
            }

            struct SeasonInfo: Equatable, Identifiable {
                let id: String
                let name: String
                let airDate: Date?
                let episodeCount: Int?
                let summary: String?
            }

            struct Episode: Equatable, Identifiable {
                let id: String
                let title: String
                let number: String?
                let airDate: Date?
                let lastWatched: Date?
                let hasMatchedFile: Bool
                let isLatestWatched: Bool
                let remoteEpisode: HomeDetailRemoteSchemas.LibraryBangumiEpisode?
            }

            struct RelatedBangumi: Equatable, Identifiable {
                let animeId: Int
                let bangumiId: String?
                let title: String
                let imageURL: URL?
                let isOnAir: Bool
                let rating: Double?

                var id: String {
                    bangumiId ?? "anime-\(animeId)"
                }
            }

            struct ExternalLink: Equatable, Identifiable {
                let id: String
                let title: String
                let subtitle: String?
                let url: URL
                let imageURL: URL?
            }

            let title: String
            let coverURL: URL?
            let typeDescription: String?
            let rating: Double?
            let userRating: Int?
            let favoriteStatus: String?
            let comment: String?
            let summary: String?
            let intro: String?
            let aliases: [AlternativeTitle]
            let metadata: [String]
            let siteRatings: [SiteRating]
            let seasons: [SeasonInfo]
            let episodes: [Episode]
            let latestWatchedEpisodeTitle: String?
            let latestWatchedAt: Date?
            let tags: [String]
            let relateds: [RelatedBangumi]
            let similars: [RelatedBangumi]
            let onlineDatabases: [ExternalLink]
            let trailers: [ExternalLink]
            let bangumiURL: URL?
        }

        let summary: Summary
        var detail: Detail?
        var remoteConfiguration: MediaLibraryConfiguration?
        var remoteDetail: HomeDetailRemoteSchemas.LibraryBangumiDetailsResponse?
        var isLoading = false
        var errorMessage: String?
        var fileSelection: FileSelection?

        struct FileSelection: Equatable, Identifiable {
            let id = UUID()
            let episode: HomeDetailRemoteSchemas.LibraryBangumiEpisode
            let files: [HomeDetailRemoteSchemas.LibraryBangumiMatchedFile]
        }
    }

    struct DetailPayload {
        let detail: State.Detail
        let remoteConfiguration: MediaLibraryConfiguration?
        let remoteDetail: HomeDetailRemoteSchemas.LibraryBangumiDetailsResponse?
    }

    enum Action {
        case onAppear
        case loadCached
        case refresh
        case detailResponse(TaskResult<DetailPayload>)
        case episodeTapped(State.Detail.Episode)
        case fileSelectionDismissed
        case fileSelected(HomeDetailRemoteSchemas.LibraryBangumiMatchedFile)
        case delegate(DelegateAction)
    }

    enum DelegateAction: Equatable {
        case startPlayback(PlayerPresenter.State)
    }

    private enum CancelID {
        case detail
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.detail == nil, !state.isLoading else { return .none }
                return .send(.loadCached)

            case .loadCached:
                state.isLoading = true
                state.errorMessage = nil
                return .run { [summary = state.summary, dandanService, configurationOperation, remoteClient] send in
                    await send(
                        .detailResponse(
                            await TaskResult {
                                let response = try await dandanService.bangumiDetails(summary.requestIdentifier, .standard)
                                let remotePlayback = await fetchDefaultRemotePlaybackDetail(
                                    configurationOperation: configurationOperation,
                                    remoteClient: remoteClient,
                                    animeId: summary.animeId
                                )
                                let detail = try mapBangumiDetail(
                                    response,
                                    fallback: summary,
                                    remoteDetail: remotePlayback?.detail
                                )
                                return .init(
                                    detail: detail,
                                    remoteConfiguration: remotePlayback?.configuration,
                                    remoteDetail: remotePlayback?.detail
                                )
                            }
                        )
                    )
                }
                .cancellable(id: CancelID.detail, cancelInFlight: true)

            case .refresh:
                state.isLoading = true
                state.errorMessage = nil
                return .run { [summary = state.summary, dandanService, configurationOperation, remoteClient] send in
                    await send(
                        .detailResponse(
                            await TaskResult {
                                let response = try await dandanService.bangumiDetails(summary.requestIdentifier, .forceRefresh)
                                let remotePlayback = await fetchDefaultRemotePlaybackDetail(
                                    configurationOperation: configurationOperation,
                                    remoteClient: remoteClient,
                                    animeId: summary.animeId
                                )
                                let detail = try mapBangumiDetail(
                                    response,
                                    fallback: summary,
                                    remoteDetail: remotePlayback?.detail
                                )
                                return .init(
                                    detail: detail,
                                    remoteConfiguration: remotePlayback?.configuration,
                                    remoteDetail: remotePlayback?.detail
                                )
                            }
                        )
                    )
                }
                .cancellable(id: CancelID.detail, cancelInFlight: true)

            case let .detailResponse(.success(payload)):
                state.isLoading = false
                state.detail = payload.detail
                state.remoteConfiguration = payload.remoteConfiguration
                state.remoteDetail = payload.remoteDetail
                state.errorMessage = nil
                return .none

            case let .detailResponse(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            case let .episodeTapped(episode):
                guard let remoteEpisode = episode.remoteEpisode else {
                    state.errorMessage = "当前未配置可用的远程媒体库，无法播放。"
                    return .none
                }
                guard let remoteDetail = state.remoteDetail else {
                    state.errorMessage = "尚未加载远程媒体库剧集详情。"
                    return .none
                }
                guard let matchedFiles = remoteEpisode.localMatchedFiles, !matchedFiles.isEmpty else {
                    state.errorMessage = "该剧集暂无匹配文件。"
                    return .none
                }
                if let file = matchedFiles.first, matchedFiles.count == 1 {
                    return startPlayback(
                        state: &state,
                        detail: remoteDetail,
                        selectedEpisode: remoteEpisode,
                        selectedFile: file
                    )
                } else {
                    state.fileSelection = .init(episode: remoteEpisode, files: matchedFiles)
                    return .none
                }

            case .fileSelectionDismissed:
                state.fileSelection = nil
                return .none

            case let .fileSelected(file):
                guard let remoteDetail = state.remoteDetail,
                      let selection = state.fileSelection else {
                    return .none
                }
                return startPlayback(
                    state: &state,
                    detail: remoteDetail,
                    selectedEpisode: selection.episode,
                    selectedFile: file
                )

            case .delegate:
                return .none
            }
        }
    }

    private func startPlayback(
        state: inout State,
        detail: HomeDetailRemoteSchemas.LibraryBangumiDetailsResponse,
        selectedEpisode: HomeDetailRemoteSchemas.LibraryBangumiEpisode,
        selectedFile: HomeDetailRemoteSchemas.LibraryBangumiMatchedFile
    ) -> Effect<Action> {
        guard let configuration = state.remoteConfiguration,
              let baseURL = configuration.baseURL else {
            state.errorMessage = "媒体库地址无效，无法播放。"
            return .none
        }
        state.fileSelection = nil
        state.errorMessage = nil
        let token = configuration.apiToken
        do {
            let prepared = try preparePlaylist(
                remoteClient: remoteClient,
                detail: detail,
                baseURL: baseURL,
                token: token,
                configuration: configuration,
                seriesTitle: state.detail?.title ?? state.summary.title,
                coverURL: state.detail?.coverURL ?? state.summary.imageURL,
                selectedEpisode: selectedEpisode,
                selectedFile: selectedFile
            )
            return .send(.delegate(.startPlayback(prepared)))
        } catch let error as PlaybackPreparationError {
            switch error {
            case .missingEpisodes:
                state.errorMessage = "无法构建播放列表。"
            case let .missingStream(reason):
                state.errorMessage = reason
            }
            return .none
        } catch {
            state.errorMessage = error.localizedDescription
            return .none
        }
    }

    private func preparePlaylist(
        remoteClient: RemoteMediaLibraryClient,
        detail: HomeDetailRemoteSchemas.LibraryBangumiDetailsResponse,
        baseURL: URL,
        token: String?,
        configuration: MediaLibraryConfiguration,
        seriesTitle: String?,
        coverURL: URL?,
        selectedEpisode: HomeDetailRemoteSchemas.LibraryBangumiEpisode,
        selectedFile: HomeDetailRemoteSchemas.LibraryBangumiMatchedFile
    ) throws -> PlayerPresenter.State {
        guard let episodes = detail.episodes, !episodes.isEmpty else {
            throw PlaybackPreparationError.missingEpisodes
        }

        let referenceName = selectedFile.name ?? selectedFile.path ?? ""
        let episodeFiles = Dictionary(
            uniqueKeysWithValues: episodes.compactMap { episode -> (HomeDetailRemoteSchemas.LibraryBangumiEpisode, [HomeDetailRemoteSchemas.LibraryBangumiMatchedFile])? in
                guard let files = episode.localMatchedFiles, !files.isEmpty else {
                    return nil
                }
                return (episode, files)
            }
        )

        var playlistItems: [PlayerPresenter.State.PlaylistItem] = []
        var currentIndex = 0

        for episode in episodes {
            guard let files = episodeFiles[episode] else { continue }

            let chosenFile: HomeDetailRemoteSchemas.LibraryBangumiMatchedFile
            if episode == selectedEpisode {
                chosenFile = selectedFile
            } else if files.count == 1 {
                chosenFile = files[0]
            } else {
                chosenFile = bestMatchingFile(
                    referenceName: referenceName,
                    files: files
                ) ?? files[0]
            }

            guard let fileID = chosenFile.id, !fileID.isEmpty else {
                throw PlaybackPreparationError.missingStream("文件 \(chosenFile.name ?? "未知") 缺少标识符。")
            }

            let stream = remoteClient.makeDirectStreamContext(baseURL, token, fileID)
            let item = PlayerPresenter.State.PlaylistItem(
                episode: episode,
                file: chosenFile,
                stream: stream
            )
            if episode == selectedEpisode {
                currentIndex = playlistItems.count
            }
            playlistItems.append(item)
        }

        guard !playlistItems.isEmpty else {
            throw PlaybackPreparationError.missingEpisodes
        }

        return PlayerPresenter.State(
            configuration: configuration,
            seriesTitle: seriesTitle,
            coverURL: coverURL,
            playlist: playlistItems,
            currentIndex: currentIndex,
            allEpisodeFiles: episodeFiles
        )
    }

    private func bestMatchingFile(
        referenceName: String,
        files: [HomeDetailRemoteSchemas.LibraryBangumiMatchedFile]
    ) -> HomeDetailRemoteSchemas.LibraryBangumiMatchedFile? {
        guard !referenceName.isEmpty else {
            return files.first
        }

        let loweredReference = referenceName.lowercased()
        return files.max { lhs, rhs in
            similarity(
                loweredReference,
                lhs.name?.lowercased() ?? lhs.path?.lowercased() ?? ""
            ) < similarity(
                loweredReference,
                rhs.name?.lowercased() ?? rhs.path?.lowercased() ?? ""
            )
        }
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let distance = levenshtein(lhs, rhs)
        let maxCount = max(lhs.count, rhs.count)
        if maxCount == 0 { return 1 }
        return 1 - (Double(distance) / Double(maxCount))
    }

    private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhsArray = Array(lhs)
        let rhsArray = Array(rhs)
        let lhsCount = lhsArray.count
        let rhsCount = rhsArray.count

        var distances = Array(repeating: Array(repeating: 0, count: rhsCount + 1), count: lhsCount + 1)

        for i in 0...lhsCount {
            distances[i][0] = i
        }
        for j in 0...rhsCount {
            distances[0][j] = j
        }

        for i in 1...lhsCount {
            for j in 1...rhsCount {
                let cost = lhsArray[i - 1] == rhsArray[j - 1] ? 0 : 1
                distances[i][j] = min(
                    distances[i - 1][j] + 1,
                    distances[i][j - 1] + 1,
                    distances[i - 1][j - 1] + cost
                )
            }
        }

        return distances[lhsCount][rhsCount]
    }

    private enum PlaybackPreparationError: Error {
        case missingEpisodes
        case missingStream(String)
    }
}

private enum HomeBangumiDetailError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message):
            return message
        }
    }
}

private struct RemotePlaybackPayload {
    let configuration: MediaLibraryConfiguration
    let detail: HomeDetailRemoteSchemas.LibraryBangumiDetailsResponse
}

private func mapBangumiDetail(
    _ response: HomeDetailDandanSchemas.BangumiDetailsResponse,
    fallback: HomeBangumiDetailPresenter.State.Summary,
    remoteDetail: HomeDetailRemoteSchemas.LibraryBangumiDetailsResponse?
) throws -> HomeBangumiDetailPresenter.State.Detail {
    if response.value1.success == false || (response.value1.errorCode ?? 0) != 0 {
        throw HomeBangumiDetailError.message(
            response.value1.errorMessage ?? "获取番剧详情失败。"
        )
    }

    guard let bangumiPayload = response.value2.bangumi else {
        throw HomeBangumiDetailError.message("当前番剧没有可展示的详情。")
    }

    let bangumi: HomeDetailDandanSchemas.BangumiDetails
    switch bangumiPayload {
    case let .BangumiDetails(value):
        bangumi = value
    }

    let intro = bangumi.value1
    let detail = bangumi.value2
    let remoteEpisodes = remoteDetail?.episodes ?? []
    let latestWatchedRemoteEpisode = latestWatchedEpisode(in: remoteEpisodes)
    let mergedEpisodes = mapEpisodes(detail.episodes, remoteEpisodes: remoteEpisodes)

    return .init(
        title: nonEmpty(intro.animeTitle) ?? fallback.title,
        coverURL: intro.imageUrl.flatMap(URL.init(string:)) ?? fallback.imageURL,
        typeDescription: nonEmpty(detail.typeDescription) ?? fallback.typeDescription,
        rating: intro.rating ?? fallback.rating,
        userRating: detail.userRating.flatMap { $0 > 0 ? Int($0) : nil },
        favoriteStatus: mapFavoriteStatus(detail.favoriteStatus) ?? (fallback.isFavorited ? "已关注" : nil),
        comment: nonEmpty(detail.comment),
        summary: nonEmpty(detail.summary),
        intro: nonEmpty(detail.intro),
        aliases: mapAlternativeTitles(detail.titles, primaryTitle: intro.animeTitle ?? fallback.title),
        metadata: compactNonEmpty(detail.metadata),
        siteRatings: mapSiteRatings(detail.ratingDetails),
        seasons: mapSeasonInfos(detail.seasons),
        episodes: mergedEpisodes,
        latestWatchedEpisodeTitle: latestWatchedRemoteEpisode.flatMap { remoteEpisodeDisplayTitle($0) },
        latestWatchedAt: latestWatchedRemoteEpisode.flatMap(preferredLastWatchedDate(for:)),
        tags: mapTags(detail.tags),
        relateds: mapRelatedBangumi(detail.relateds),
        similars: mapRelatedBangumi(detail.similars),
        onlineDatabases: mapOnlineDatabases(detail.onlineDatabases),
        trailers: mapTrailers(detail.trailers),
        bangumiURL: detail.bangumiUrl.flatMap(URL.init(string:))
    )
}

private func mapAlternativeTitles(
    _ titles: [HomeDetailDandanSchemas.BangumiTitle]?,
    primaryTitle: String
) -> [HomeBangumiDetailPresenter.State.Detail.AlternativeTitle] {
    var seen = Set<String>()
    var mapped: [HomeBangumiDetailPresenter.State.Detail.AlternativeTitle] = []

    for item in titles ?? [] {
        guard let title = nonEmpty(item.title), title != primaryTitle else { continue }
        let key = "\(item.language ?? "")::\(title)"
        guard seen.insert(key).inserted else { continue }
        mapped.append(.init(language: nonEmpty(item.language), title: title))
    }

    return mapped
}

private func mapSiteRatings(
    _ payload: HomeDetailDandanSchemas.BangumiDetails.Value2Payload.RatingDetailsPayload?
) -> [HomeBangumiDetailPresenter.State.Detail.SiteRating] {
    (payload?.additionalProperties ?? [:])
        .map { key, value in
            HomeBangumiDetailPresenter.State.Detail.SiteRating(
                source: key,
                value: value
            )
        }
        .sorted {
            if $0.value == $1.value {
                return $0.source.localizedStandardCompare($1.source) == .orderedAscending
            }
            return $0.value > $1.value
        }
}

private func mapSeasonInfos(
    _ seasons: [HomeDetailDandanSchemas.BangumiEpisodeSeason]?
) -> [HomeBangumiDetailPresenter.State.Detail.SeasonInfo] {
    (seasons ?? []).compactMap { season in
        let title = nonEmpty(season.name) ?? "未命名季度"
        let identifier = nonEmpty(season.id) ?? "\(title)-\(season.airDate?.timeIntervalSince1970 ?? 0)"
        return .init(
            id: identifier,
            name: title,
            airDate: season.airDate,
            episodeCount: season.episodeCount.map(Int.init),
            summary: nonEmpty(season.summary)
        )
    }
}

private func mapEpisodes(
    _ episodes: [HomeDetailDandanSchemas.BangumiEpisode]?,
    remoteEpisodes: [HomeDetailRemoteSchemas.LibraryBangumiEpisode]
) -> [HomeBangumiDetailPresenter.State.Detail.Episode] {
    let remoteEpisodesByID = Dictionary(
        uniqueKeysWithValues: remoteEpisodes.compactMap { episode -> (Int, HomeDetailRemoteSchemas.LibraryBangumiEpisode)? in
            guard let episodeId = episode.episodeId else { return nil }
            return (episodeId, episode)
        }
    )
    let remoteEpisodesByNumber = Dictionary(
        uniqueKeysWithValues: remoteEpisodes.compactMap { episode -> (String, HomeDetailRemoteSchemas.LibraryBangumiEpisode)? in
            guard let number = normalizedEpisodeNumber(episode.episodeNumber) else { return nil }
            return (number, episode)
        }
    )

    let dandanEpisodes: [HomeDetailDandanSchemas.BangumiEpisode] = episodes ?? []

    return dandanEpisodes.compactMap { episode -> HomeBangumiDetailPresenter.State.Detail.Episode? in
        let title = nonEmpty(episode.episodeTitle) ?? nonEmpty(episode.episodeNumber) ?? "未命名剧集"
        let identifier = episode.episodeId.map(String.init)
            ?? "\(episode.seasonId ?? "season")-\(episode.episodeNumber ?? title)"
        let matchedRemoteEpisode = matchRemoteEpisode(
            dandanEpisode: episode,
            remoteEpisodesByID: remoteEpisodesByID,
            remoteEpisodesByNumber: remoteEpisodesByNumber
        )
        return .init(
            id: identifier,
            title: title,
            number: nonEmpty(episode.episodeNumber),
            airDate: episode.airDate,
            lastWatched: matchedRemoteEpisode.flatMap(preferredLastWatchedDate(for:)) ?? episode.lastWatched,
            hasMatchedFile: matchedRemoteEpisode?.localMatchedExists ?? false,
            isLatestWatched: matchedRemoteEpisode?.isLatestWatched ?? false,
            remoteEpisode: matchedRemoteEpisode
        )
    }
}

private func mapTags(_ tags: [HomeDetailDandanSchemas.BangumiTag]?) -> [String] {
    uniquedPreservingOrder(
        (tags ?? []).compactMap { nonEmpty($0.name) }
    )
}

private func mapRelatedBangumi(
    _ items: [HomeDetailDandanSchemas.BangumiIntro]?
) -> [HomeBangumiDetailPresenter.State.Detail.RelatedBangumi] {
    (items ?? []).compactMap { item in
        guard let animeId = item.animeId else { return nil }
        return .init(
            animeId: Int(animeId),
            bangumiId: item.bangumiId,
            title: nonEmpty(item.animeTitle) ?? "未命名番剧",
            imageURL: item.imageUrl.flatMap(URL.init(string:)),
            isOnAir: item.isOnAir ?? false,
            rating: item.rating
        )
    }
}

private func mapOnlineDatabases(
    _ items: [HomeDetailDandanSchemas.BangumiOnlineDatabase]?
) -> [HomeBangumiDetailPresenter.State.Detail.ExternalLink] {
    (items ?? []).compactMap { item in
        guard let title = nonEmpty(item.name),
              let urlString = nonEmpty(item.url),
              let url = URL(string: urlString) else {
            return nil
        }
        return .init(
            id: "online-\(title)-\(url.absoluteString)",
            title: title,
            subtitle: nil,
            url: url,
            imageURL: nil
        )
    }
}

private func mapTrailers(
    _ items: [HomeDetailDandanSchemas.BangumiTrailer]?
) -> [HomeBangumiDetailPresenter.State.Detail.ExternalLink] {
    (items ?? []).compactMap { item in
        guard let urlString = nonEmpty(item.url),
              let url = URL(string: urlString) else {
            return nil
        }
        let title = nonEmpty(item.title) ?? "预告片"
        return .init(
            id: "trailer-\(item.id ?? 0)-\(url.absoluteString)",
            title: title,
            subtitle: "预告片",
            url: url,
            imageURL: item.imageUrl.flatMap(URL.init(string:))
        )
    }
}

private func mapFavoriteStatus(
    _ payload: HomeDetailDandanSchemas.BangumiDetails.Value2Payload.FavoriteStatusPayload?
) -> String? {
    guard let payload else { return nil }
    switch payload {
    case let .FavoriteStatus(status):
        switch status {
        case .favorited:
            return "在看"
        case .finished:
            return "看过"
        case .abandoned:
            return "弃番"
        }
    }
}

private func fetchDefaultRemotePlaybackDetail(
    configurationOperation: RemoteLibraryConfigurationOperation,
    remoteClient: RemoteMediaLibraryClient,
    animeId: Int
) async -> RemotePlaybackPayload? {
    do {
        let configurationRecord = try await MainActor.run {
            try configurationOperation.fetchDefault()
        }
        guard let configurationRecord,
              let baseURL = URL(string: configurationRecord.url) else {
            return nil
        }
        let detail = try await remoteClient.fetchBangumiDetail(baseURL, configurationRecord.apiKey, animeId)
        return .init(
            configuration: .init(record: configurationRecord),
            detail: detail
        )
    } catch {
        return nil
    }
}

private func latestWatchedEpisode(
    in episodes: [HomeDetailRemoteSchemas.LibraryBangumiEpisode]
) -> HomeDetailRemoteSchemas.LibraryBangumiEpisode? {
    if let marked = episodes.first(where: { $0.isLatestWatched == true }) {
        return marked
    }
    return episodes.max {
        (preferredLastWatchedDate(for: $0) ?? .distantPast)
        < (preferredLastWatchedDate(for: $1) ?? .distantPast)
    }
}

private func preferredLastWatchedDate(
    for episode: HomeDetailRemoteSchemas.LibraryBangumiEpisode
) -> Date? {
    episode.lastWatched ?? episode.lastWatchedCloud
}

private func remoteEpisodeDisplayTitle(
    _ episode: HomeDetailRemoteSchemas.LibraryBangumiEpisode
) -> String? {
    nonEmpty(episode.episodeTitle)
        ?? nonEmpty(episode.displayTitle)
        ?? nonEmpty(episode.episodeNumber)
}

private func normalizedEpisodeNumber(_ value: String?) -> String? {
    nonEmpty(value)?
        .replacingOccurrences(of: "第", with: "")
        .replacingOccurrences(of: "集", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

private func matchRemoteEpisode(
    dandanEpisode: HomeDetailDandanSchemas.BangumiEpisode,
    remoteEpisodesByID: [Int: HomeDetailRemoteSchemas.LibraryBangumiEpisode],
    remoteEpisodesByNumber: [String: HomeDetailRemoteSchemas.LibraryBangumiEpisode]
) -> HomeDetailRemoteSchemas.LibraryBangumiEpisode? {
    if let dandanEpisodeId = dandanEpisode.episodeId,
       let matchedByID = remoteEpisodesByID[Int(dandanEpisodeId)] {
        return matchedByID
    }

    if let episodeNumber = normalizedEpisodeNumber(dandanEpisode.episodeNumber),
       let matchedByNumber = remoteEpisodesByNumber[episodeNumber] {
        return matchedByNumber
    }

    return nil
}

private func compactNonEmpty(_ values: [String]?) -> [String] {
    uniquedPreservingOrder(
        (values ?? []).compactMap(nonEmpty)
    )
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func uniquedPreservingOrder<T: Hashable>(_ values: [T]) -> [T] {
    var seen = Set<T>()
    return values.filter { seen.insert($0).inserted }
}
