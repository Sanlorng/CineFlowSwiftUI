//
//  LibraryPresenter.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/10/14.
//

import Foundation
import ComposableArchitecture
import IdentifiedCollections
import RemoteMediaLibrary
import OpenAPIURLSession
import OpenAPIRuntime
import HTTPTypes

@Reducer
struct LibraryPresenter {
    
    @ObservableState
    struct State: Equatable {

        struct BangumiItem: Equatable, Identifiable {
            let id: String
            let animeId: Int?
            let title: String
            let onAirDate: Date?
            let groupName: String?
            let rating: Float?
            let userRating: Float?
            let episodeProgress: String?
            let videoFileCount: Int?
            let lastPlay: Date?
            let lastUpdate: Date?
            let coverURL: URL?
            
            init(id: String,
                 animeId: Int?,
                 title: String,
                 onAirDate: Date?,
                 groupName: String?,
                 rating: Float?,
                 userRating: Float?,
                 episodeProgress: String?,
                 videoFileCount: Int?,
                 lastPlay: Date?,
                 lastUpdate: Date?,
                 coverURL: URL?) {
                self.id = id
                self.animeId = animeId
                self.title = title
                self.onAirDate = onAirDate
                self.groupName = groupName
                self.rating = rating
                self.userRating = userRating
                self.episodeProgress = episodeProgress
                self.videoFileCount = videoFileCount
                self.lastPlay = lastPlay
                self.lastUpdate = lastUpdate
                self.coverURL = coverURL
            }
        }
        
        struct Configuration: Equatable, Identifiable {
            let id: UUID
            var name: String
            var url: String
            var apiToken: String?
            var isDefault: Bool
            var createdAt: Date
            
            var baseURL: URL? { URL(string: url) }
            
            init(
                id: UUID,
                name: String,
                url: String,
                apiToken: String?,
                isDefault: Bool,
                createdAt: Date
            ) {
                self.id = id
                self.name = name
                self.url = url
                self.apiToken = apiToken
                self.isDefault = isDefault
                self.createdAt = createdAt
            }
            
            init(record: RemoteLibraryConfigurationOperation.Record) {
                self.init(
                    id: record.id,
                    name: record.name,
                    url: record.url,
                    apiToken: record.apiKey,
                    isDefault: record.isDefault,
                    createdAt: record.createdAt
                )
            }
            
        }
        
        var configurations: IdentifiedArrayOf<Configuration> = []
        var path = StackState<Path.State>()
        var selectedConfigurationID: UUID?
        var bangumiItems: IdentifiedArrayOf<BangumiItem> = []
        var selectedSort: SortOption = .lastPlay
        var searchQuery: String = ""
        
        var isLoadingLibrary = false
        var isCheckingWelcome = false
        var formError: String?
        var infoMessage: String?
        
        var isShowingForm = false
        var formRequiresToken: Bool?
        
        var formName: String = ""
        var formIP: String = ""
        var formPort: String = "9999"
        var formToken: String = ""
        
        fileprivate var hasLoaded = false
        
        mutating func resetForm() {
            formName = ""
            formIP = ""
            formPort = "9999"
            formToken = ""
            formRequiresToken = nil
            formError = nil
            isCheckingWelcome = false
        }
    }
    
    struct ConfigurationDraft: Equatable {
        let name: String
        let baseURLString: String
        let token: String?
    }
    
    struct WelcomePayload: Equatable {
        let draft: ConfigurationDraft
        let welcome: RemoteMediaLibraryClient.Welcome
    }
    
    enum SortOption: String, CaseIterable, Equatable, Sendable {
        case lastPlay
        case lastUpdate
        case lastAdd
        case season
        case name
        case category
        case rating
        
        var displayName: String {
            switch self {
            case .lastPlay: return "最近播放"
            case .lastUpdate: return "最近更新"
            case .lastAdd: return "最近关注"
            case .season: return "季度番剧"
            case .name: return "按名称"
            case .category: return "按分类"
            case .rating: return "按评分"
            }
        }
    }
    
    enum Action: Equatable {
        case onAppear
        case configurationsLoaded([State.Configuration])
        case configurationsFailed(String)
        case selectConfiguration(UUID)
        case refresh
        case fetchLibrary(UUID)
        case libraryLoaded(UUID, SortOption, [State.BangumiItem])
        case libraryFailed(UUID, SortOption, String)
        case setIsShowingForm(Bool)
        case saveNewConfiguration
        case welcomeChecked(WelcomePayload)
        case welcomeCheckFailed(String)
        case configurationSaved(State.Configuration)
        case configurationSaveFailed(String)
        case setFormName(String)
        case setFormIP(String)
        case setFormPort(String)
        case setFormToken(String)
        case setSort(SortOption)
        case setSearchQuery(String)
        case bangumiTapped(State.BangumiItem)
        case path(StackAction<Path.State, Path.Action>)
    }
    
    @Dependency(\.remoteLibraryConfigurationOperation) var configurationOperation
    @Dependency(\.remoteMediaLibraryClient) var remoteClient

    @Reducer
    struct Path {
        enum State: Equatable {
            case bangumiDetail(BangumiDetailPresenter.State)
            case player(PlayerPresenter.State)
        }

        enum Action: Equatable {
            case bangumiDetail(BangumiDetailPresenter.Action)
            case player(PlayerPresenter.Action)
        }

        var body: some ReducerOf<Self> {
            Scope(state: /State.bangumiDetail, action: /Action.bangumiDetail) {
                BangumiDetailPresenter()
            }
            Scope(state: /State.player, action: /Action.player) {
                PlayerPresenter()
            }
        }
    }
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .bangumiTapped(item):
                guard let configurationID = state.selectedConfigurationID,
                      let configuration = state.configurations[id: configurationID] else {
                    return .none
                }
                state.path.append(.bangumiDetail(.init(summary: item, configuration: configuration)))
                return .none

            case let .path(.element(id: _, action: .bangumiDetail(.delegate(.startPlayback(playerState))))):
                state.path.append(.player(playerState))
                return .none

            case .path:
                return .none

            case let .setFormName(name):
                state.formName = name
                state.formError = nil
                return .none
                
            case let .setFormIP(ip):
                state.formIP = ip
                state.formError = nil
                return .none
                
            case let .setFormPort(port):
                state.formPort = port
                state.formError = nil
                return .none
                
            case let .setFormToken(token):
                state.formToken = token
                state.formError = nil
                return .none
                
            case .onAppear:
                guard state.hasLoaded == false else { return .none }
                state.hasLoaded = true
                return loadConfigurationsEffect()
                
            case let .configurationsLoaded(configurations):
                state.configurations = IdentifiedArray(uniqueElements: configurations.sorted { $0.createdAt < $1.createdAt })
                if let defaultConfig = state.configurations.first(where: \.isDefault) ?? state.configurations.first {
                    state.selectedConfigurationID = defaultConfig.id
                    state.infoMessage = nil
                    return .merge(
                        updateDefaultConfigurationEffect(defaultID: defaultConfig.id),
                        triggerFetchLibraryEffect(defaultConfig.id)
                    )
                } else {
                    state.selectedConfigurationID = nil
                    state.infoMessage = "尚未配置远程媒体库，请创建一个新配置。"
                    state.isShowingForm = true
                    return .none
                }
                
            case let .configurationsFailed(message):
                state.infoMessage = message
                return .none
                
            case let .selectConfiguration(id):
                guard state.configurations[id: id] != nil else { return .none }
                state.selectedConfigurationID = id
                state.configurations = IdentifiedArray(uniqueElements: state.configurations.map { config in
                    var mutable = config
                    mutable.isDefault = (config.id == id)
                    return mutable
                })
                return .merge(
                    updateDefaultConfigurationEffect(defaultID: id),
                    triggerFetchLibraryEffect(id)
                )
                
            case .refresh:
                guard let id = state.selectedConfigurationID else { return .none }
                return triggerFetchLibraryEffect(id)
                
            case let .fetchLibrary(id):
                guard let configuration = state.configurations[id: id],
                      let baseURL = configuration.baseURL else {
                    state.infoMessage = "选中的媒体库配置无效。"
                    return .none
                }
                let sort = state.selectedSort
                state.isLoadingLibrary = true
                state.infoMessage = nil
                return .run { [token = configuration.apiToken, remoteClient, sort] send in
                    do {
                        let items = try await remoteClient.fetchBangumiList(baseURL, token, sort)
                        let mapped = items.map { State.BangumiItem($0, baseURL: baseURL) }
                        await send(.libraryLoaded(id, sort, mapped))
                    } catch {
                        debugPrint(error)
                        await send(.libraryFailed(id, sort, error.localizedDescription))
                    }
                }
                
            case let .libraryLoaded(id, sort, items):
                guard state.selectedConfigurationID == id,
                      state.selectedSort == sort else { return .none }
                state.isLoadingLibrary = false
                state.bangumiItems = IdentifiedArray(uniqueElements: items)
                if items.isEmpty {
                    state.infoMessage = "媒体库为空。"
                }
                return .none
                
            case let .libraryFailed(id, sort, message):
                guard state.selectedConfigurationID == id,
                      state.selectedSort == sort else { return .none }
                state.isLoadingLibrary = false
                state.infoMessage = message
                return .none
                
            case let .setIsShowingForm(isPresented):
                state.isShowingForm = isPresented
                if !isPresented {
                    state.resetForm()
                }
                return .none
                
            case .saveNewConfiguration:
                state.formError = nil
                guard !state.formName.trimmingCharacters(in: .whitespaces).isEmpty else {
                    state.formError = "请输入配置名称。"
                    return .none
                }
                guard let baseURL = Self.makeBaseURL(ip: state.formIP, port: state.formPort) else {
                    state.formError = "请输入有效的 IP 与端口。"
                    return .none
                }
                if state.formRequiresToken == true && state.formToken.isEmpty {
                    state.formError = "该媒体库已开启加密，请填写 API Token。"
                    return .none
                }
                state.isCheckingWelcome = true
                let draft = ConfigurationDraft(
                    name: state.formName,
                    baseURLString: baseURL.absoluteString,
                    token: state.formToken.isEmpty ? nil : state.formToken
                )
                return .run { [remoteClient] send in
                    do {
                        let welcome = try await remoteClient.fetchWelcome(baseURL, draft.token)
                        await send(.welcomeChecked(.init(draft: draft, welcome: welcome)))
                    } catch {
                        await send(.welcomeCheckFailed(error.localizedDescription))
                    }
                }
                
            case let .welcomeChecked(payload):
                state.isCheckingWelcome = false
                state.formRequiresToken = payload.welcome.tokenRequired
                if payload.welcome.tokenRequired && (payload.draft.token ?? "").isEmpty {
                    state.formError = "该媒体库开启了 API 加密，请输入 Token 后再试。"
                    return .none
                }
                return persistConfigurationEffect(payload.draft)
                
            case let .welcomeCheckFailed(message):
                state.isCheckingWelcome = false
                state.formError = message
                return .none
                
            case .configurationSaved:
                state.resetForm()
                state.isShowingForm = false
                return loadConfigurationsEffect()
                
            case let .configurationSaveFailed(message):
                state.isCheckingWelcome = false
                state.formError = message
                return .none
                
            case let .setSort(sort):
                guard state.selectedSort != sort else { return .none }
                state.selectedSort = sort
                guard let id = state.selectedConfigurationID else { return .none }
                return triggerFetchLibraryEffect(id)

            case let .setSearchQuery(query):
                state.searchQuery = query
                return .none
            }
        }
        .forEach(\.path, action: /Action.path) {
            Path()
        }
    }
    
    private func loadConfigurationsEffect() -> Effect<Action> {
        let operation = configurationOperation
        return .run { send in
            do {
                let records = try await Task { @MainActor in
                    try operation.fetchAll()
                }.value
                await send(.configurationsLoaded(records.map(State.Configuration.init(record:))))
            } catch {
                await send(.configurationsFailed(error.localizedDescription))
            }
        }
    }

    private func persistConfigurationEffect(_ draft: ConfigurationDraft) -> Effect<Action> {
        let operation = configurationOperation
        return .run { send in
            do {
                let saved = try await Task { @MainActor in
                    let all = try operation.fetchAll()
                    for var existing in all where existing.isDefault {
                        existing.isDefault = false
                        _ = try operation.updateItem(existing)
                    }
                    let record = RemoteLibraryConfigurationOperation.Record(
                        id: UUID(),
                        name: draft.name,
                        url: draft.baseURLString,
                        apiKey: draft.token,
                        isDefault: true,
                        createdAt: Date()
                    )
                    return try operation.addItem(record)
                }.value
                await send(.configurationSaved(.init(record: saved)))
            } catch {
                await send(.configurationSaveFailed(error.localizedDescription))
            }
        }
    }

    private func updateDefaultConfigurationEffect(defaultID: UUID) -> Effect<Action> {
        let operation = configurationOperation
        return .run { send in
            do {
                _ = try await Task { @MainActor in
                    let all = try operation.fetchAll()
                    for var existing in all {
                        let shouldBeDefault = existing.id == defaultID
                        if existing.isDefault != shouldBeDefault {
                            existing.isDefault = shouldBeDefault
                            _ = try operation.updateItem(existing)
                        }
                    }
                }.value
            } catch {
                await send(.configurationsFailed(error.localizedDescription))
            }
        }
    }
    
    private func triggerFetchLibraryEffect(_ id: UUID) -> Effect<Action> {
        .run { send in
            await send(.fetchLibrary(id))
        }
    }
    
    private static func makeBaseURL(ip: String, port: String) -> URL? {
        let trimmedIP = ip.trimmingCharacters(in: .whitespaces)
        let trimmedPort = port.trimmingCharacters(in: .whitespaces)
        if trimmedIP.isEmpty {
            return nil
        }
        if let url = URL(string: trimmedIP), url.scheme != nil {
            return url
        }
        guard let portValue = Int(trimmedPort) else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = trimmedIP
        components.port = portValue
        components.path = ""
        return components.url
    }
}

extension LibraryPresenter.State.BangumiItem {
    init(_ summary: Components.Schemas.LibraryBangumiSummary, baseURL: URL) {
        let identifier = summary.animeId.map { "anime-\($0)" } ?? UUID().uuidString
        let progress: String?
        if let watched = summary.episodeWatched,
           let total = summary.episodeTotal,
           total > 0 {
            progress = "进度 \(watched)/\(total)"
        } else {
            progress = nil
        }
        self.init(
            id: identifier,
            animeId: summary.animeId,
            title: summary.title ?? "未知动画",
            onAirDate: summary.onAirDate,
            groupName: summary.groupName,
            rating: summary.rating,
            userRating: summary.userRating,
            episodeProgress: progress,
            videoFileCount: summary.videoFileCount,
            lastPlay: summary.lastPlay,
            lastUpdate: summary.lastUpdate,
            coverURL: Self.makeCoverURL(baseURL: baseURL, path: summary.cover)
        )
    }
    
    private static func makeCoverURL(baseURL: URL, path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if let url = URL(string: path), url.scheme != nil {
            return url
        }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }
}

extension LibraryPresenter.State {
    var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayedBangumiItems: IdentifiedArrayOf<BangumiItem> {
        let query = trimmedSearchQuery
        guard !query.isEmpty else { return bangumiItems }
        let terms = normalizedSearchTerms(from: query)
        guard !terms.isEmpty else { return bangumiItems }
        let filtered = bangumiItems.filter { item in
            item.matchesSearchTerms(terms)
        }
        return IdentifiedArray(uniqueElements: filtered)
    }

    var groupedBangumiItems: [(group: String, items: [BangumiItem])] {
        var order: [String] = []
        var storage: [String: [BangumiItem]] = [:]
        
        for item in displayedBangumiItems {
            let rawGroup = item.groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = (rawGroup?.isEmpty == false) ? rawGroup! : "未分组"
            if storage[key] == nil {
                order.append(key)
                storage[key] = []
            }
            storage[key]?.append(item)
        }
        
        return order.map { key in
            (group: key, items: storage[key] ?? [])
        }
    }
    
    var groupTitles: [String] {
        groupedBangumiItems.map(\.group)
    }
}

private func normalizedSearchTerms(from query: String) -> [String] {
    query
        .lowercased()
        .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .autoupdatingCurrent)
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)
}

private extension LibraryPresenter.State.BangumiItem {
    func matchesSearchTerms(_ terms: [String]) -> Bool {
        let haystacks = [
            title,
            details,
            groupName,
            episodeProgress,
            animeId.map(String.init),
            videoFileCount.map { "文件 \($0)" }
        ]
        .compactMap { $0 }
        .map {
            $0.lowercased()
                .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .autoupdatingCurrent)
        }

        return terms.allSatisfy { term in
            haystacks.contains(where: { $0.contains(term) })
        }
    }
}

struct RemoteMediaLibraryClient {
    struct Welcome: Equatable {
        let message: String?
        let version: String?
        let tokenRequired: Bool
    }

    struct StreamContext: Equatable {
        let url: URL
        let headers: [String: String]
    }

    struct Subtitle: Equatable, Identifiable {
        var id: String { fileName }
        let fileName: String
        let fileSize: Int?
    }
    
    var fetchWelcome: @Sendable (_ baseURL: URL, _ token: String?) async throws -> Welcome
    var fetchBangumiList: @Sendable (_ baseURL: URL, _ token: String?, _ sort: LibraryPresenter.SortOption) async throws -> [Components.Schemas.LibraryBangumiSummary]
    var fetchBangumiDetail: @Sendable (_ baseURL: URL, _ token: String?, _ animeId: Int) async throws -> Components.Schemas.LibraryBangumiDetailsResponse
    var makeDirectStreamContext: @Sendable (_ baseURL: URL, _ token: String?, _ fileID: String) -> StreamContext
    var makeStreamContext: @Sendable (_ baseURL: URL, _ token: String?, _ fileID: String) async throws -> StreamContext
    var fetchDanmakuXML: @Sendable (_ baseURL: URL, _ token: String?, _ fileID: String) async throws -> String
    var fetchSubtitleInfo: @Sendable (_ baseURL: URL, _ token: String?, _ fileID: String) async throws -> [Subtitle]
    var fetchSubtitleFile: @Sendable (_ baseURL: URL, _ token: String?, _ fileID: String, _ fileName: String) async throws -> String
}

extension RemoteMediaLibraryClient: DependencyKey {
    static var liveValue: RemoteMediaLibraryClient {
        RemoteMediaLibraryClient(
            fetchWelcome: { baseURL, token in
                let api = try makeClient(baseURL: baseURL, token: token)
                let response = try await api.fetch {
                    try await api.getWelcomeMessage(.init())
                }
                return Welcome(
                    message: response.message,
                    version: response.version,
                    tokenRequired: response.tokenRequired ?? false
                )
            },
            fetchBangumiList: { baseURL, token, sort in
                let api = try makeClient(baseURL: baseURL, token: token)
                switch sort {
                case .lastPlay:
                    return try await api.fetch {
                        try await api.listBangumiByLastPlay(.init())
                    }
                case .lastUpdate:
                    return try await api.fetch {
                        try await api.listBangumiByLastUpdate(.init())
                    }
                case .lastAdd:
                    return try await api.fetch {
                        try await api.listBangumiByLastAdd(.init())
                    }
                case .season:
                    return try await api.fetch {
                        try await api.listBangumiBySeason(.init())
                    }
                case .name:
                    return try await api.fetch {
                        try await api.listBangumiByName(.init())
                    }
                case .category:
                    return try await api.fetch {
                        try await api.listBangumiByCategory(.init())
                    }
                case .rating:
                    return try await api.fetch {
                        try await api.listBangumiByRating(.init())
                    }
                }
            },
            fetchBangumiDetail: { baseURL, token, animeId in
                let api = try makeClient(baseURL: baseURL, token: token)
                return try await api.fetch {
                    try await api.getBangumiDetails(.init(path: .init(animeId: animeId)))
                }
            },
            makeDirectStreamContext: { baseURL, token, fileID in
                buildDirectStreamContext(baseURL: baseURL, token: token, fileID: fileID)
            },
            makeStreamContext: { baseURL, token, fileID in
                do {
                    return try await fetchWebPlayerStreamContext(
                        baseURL: baseURL,
                        token: token,
                        fileID: fileID
                    )
                } catch {
#if DEBUG
                    print("[Network][RemoteMediaLibrary] web player stream fallback reason: \(error)")
#endif
                    return buildDirectStreamContext(baseURL: baseURL, token: token, fileID: fileID)
                }
            },
            fetchDanmakuXML: { baseURL, token, fileID in
                let api = try makeClient(baseURL: baseURL, token: token)
                let output = try await api.getCommentById(.init(path: .init(id: fileID)))
                switch output {
                case let .ok(ok):
                    let body = try ok.body.xml
                    return try await String(collecting: body, upTo: 8 * 1024 * 1024)
                case let .undocumented(statusCode, _):
                    throw APIError.serverError(statusCode: statusCode)
                }
            },
            fetchSubtitleInfo: { baseURL, token, fileID in
                do {
                    let api = try makeClient(baseURL: baseURL, token: token)
                    let output = try await api.getSubtitleInfo(.init(path: .init(id: fileID)))
                    switch output {
                    case let .ok(ok):
                        let info = try ok.body.json
                        let mapped = mapSubtitleInfoPayload(info.subtitles)
                        if mapped.isEmpty {
                            return try await fetchSubtitleInfoFallback(
                                baseURL: baseURL,
                                token: token,
                                fileID: fileID,
                                reason: "generated-client-empty"
                            )
                        }
                        return mapped
                    case let .undocumented(statusCode, _):
                        throw APIError.serverError(statusCode: statusCode)
                    }
                } catch {
                    return try await fetchSubtitleInfoFallback(
                        baseURL: baseURL,
                        token: token,
                        fileID: fileID,
                        reason: "generated-client-error: \(error)"
                    )
                }
            },
            fetchSubtitleFile: { baseURL, token, fileID, fileName in
                do {
                    let api = try makeClient(baseURL: baseURL, token: token)
                    let output = try await api.getSubtitleFile(
                        .init(
                            path: .init(id: fileID),
                            query: .init(fileName: fileName)
                        )
                    )
                    switch output {
                    case let .ok(ok):
                        let body = try ok.body.plainText
                        return try await String(collecting: body, upTo: 5 * 1024 * 1024)
                    case let .undocumented(statusCode, _):
                        throw APIError.serverError(statusCode: statusCode)
                    }
                } catch {
                    return try await fetchSubtitleFileFallback(
                        baseURL: baseURL,
                        token: token,
                        fileID: fileID,
                        fileName: fileName
                    )
                }
            }
        )
    }
    
    static var previewValue: RemoteMediaLibraryClient {
        RemoteMediaLibraryClient(
            fetchWelcome: { _, _ in
                .init(message: "欢迎", version: "preview", tokenRequired: false)
            },
            fetchBangumiList: { _, _, sort in
                [
                    Components.Schemas.LibraryBangumiSummary(
                        isFavoriteStatusAbandoned: false,
                        allEpisodesWatched: false,
                        animeId: 1,
                        cover: nil,
                        title: "Preview Anime (\(sort.displayName))",
                        details: "2025-01-01",
                        lastPlay: nil,
                        created: Date(),
                        onAirDate: nil,
                        rating: 8.4,
                        userRating: 8.4,
                        isFavorited: true,
                        favoriteStatus: 0,
                        episodeTotal: 12,
                        episodeWatched: 6,
                        lastUpdate: Date(),
                        typeId: 1,
                        typeDescription: "TV动画",
                        groupName: "预览",
                        videoFileCount: 10
                    )
                ]
            },
            fetchBangumiDetail: { _, _, animeId in
                Components.Schemas.LibraryBangumiDetailsResponse(
                    animeId: animeId,
                    title: "Preview Anime Detail",
                    episodes: [
                        .init(
                            seasonId: 1,
                            episodeId: 1,
                            episodeTitle: "第1集",
                            episodeNumber: "01",
                            lastWatched: nil,
                            lastWatchedCloud: nil,
                            isLatestWatched: true,
                            airDate: Date(),
                            displayTitle: "Episode 1",
                            airStatus: 1,
                            localMatchedExists: true,
                            localMatchedFiles: [
                                .init(
                                    animeId: animeId,
                                    episodeId: 1,
                                    animeTitle: "Preview Anime Detail",
                                    episodeTitle: "Episode 1",
                                    id: UUID().uuidString,
                                    hash: UUID().uuidString,
                                    name: "Preview.Episode.01.mkv",
                                    path: "/preview/Preview.Episode.01.mkv",
                                    dirPath: "/preview",
                                    size: 500 * 1_024 * 1_024,
                                    rate: 9,
                                    isStandalone: true,
                                    created: Date(),
                                    lastMatch: Date(),
                                    includeTime: Date(),
                                    lastPlay: nil,
                                    lastThumbnail: nil,
                                    thumbFailed: 0,
                                    duration: 1_350
                                ),
                                .init(
                                    animeId: animeId,
                                    episodeId: 1,
                                    animeTitle: "Preview Anime Detail",
                                    episodeTitle: "Episode 1",
                                    id: UUID().uuidString,
                                    hash: UUID().uuidString,
                                    name: "Preview.Episode.01.alt.mkv",
                                    path: "/preview/Preview.Episode.01.alt.mkv",
                                    dirPath: "/preview",
                                    size: 520 * 1_024 * 1_024,
                                    rate: 8,
                                    isStandalone: true,
                                    created: Date(),
                                    lastMatch: Date(),
                                    includeTime: Date(),
                                    lastPlay: nil,
                                    lastThumbnail: nil,
                                    thumbFailed: 0,
                                    duration: 1_350
                                )
                            ],
                            canMarkAsWatched: true
                        ),
                        .init(
                            seasonId: 1,
                            episodeId: 2,
                            episodeTitle: "第2集",
                            episodeNumber: "02",
                            lastWatched: nil,
                            lastWatchedCloud: nil,
                            isLatestWatched: false,
                            airDate: Date(),
                            displayTitle: "Episode 2",
                            airStatus: 1,
                            localMatchedExists: true,
                            localMatchedFiles: [
                                .init(
                                    animeId: animeId,
                                    episodeId: 2,
                                    animeTitle: "Preview Anime Detail",
                                    episodeTitle: "Episode 2",
                                    id: UUID().uuidString,
                                    hash: UUID().uuidString,
                                    name: "Preview.Episode.02.mkv",
                                    path: "/preview/Preview.Episode.02.mkv",
                                    dirPath: "/preview",
                                    size: 510 * 1_024 * 1_024,
                                    rate: 8,
                                    isStandalone: true,
                                    created: Date(),
                                    lastMatch: Date(),
                                    includeTime: Date(),
                                    lastPlay: nil,
                                    lastThumbnail: nil,
                                    thumbFailed: 0,
                                    duration: 1_360
                                )
                            ],
                            canMarkAsWatched: true
                        )
                    ]
                )
            },
            makeDirectStreamContext: { baseURL, token, fileID in
                let path = "/preview/\(fileID)"
                let url = buildOperationURL(
                    baseURL: baseURL,
                    path: path,
                    queryItems: token?.isEmpty == false ? [.init(name: "token", value: token)] : []
                )
                return .init(url: url, headers: ["Accept": "video/*"])
            },
            makeStreamContext: { baseURL, token, fileID in
                let path = "/preview/\(fileID)"
                let url = buildOperationURL(
                    baseURL: baseURL,
                    path: path,
                    queryItems: token?.isEmpty == false ? [.init(name: "token", value: token)] : []
                )
                return .init(url: url, headers: ["Accept": "video/*"])
            },
            fetchDanmakuXML: { _, _, fileID in
                """
                <?xml version="1.0"?>
                <i>
                  <chatserver>chat.bilibili.com</chatserver>
                  <chatid>\(fileID)</chatid>
                  <d p="1.5,1,25,16777215,0,0,0,0">Preview Danmaku</d>
                  <d p="6.0,5,25,16744192,0,0,0,0">Top Danmaku</d>
                </i>
                """
            },
            fetchSubtitleInfo: { _, _, fileID in
                [
                    .init(fileName: "Preview-\(fileID).sc.ass", fileSize: 42_000),
                    .init(fileName: "Preview-\(fileID).en.srt", fileSize: 38_000)
                ]
            },
            fetchSubtitleFile: { _, _, _, fileName in
                "Preview subtitles for \(fileName)"
            }
        )
    }
    
    static var testValue: RemoteMediaLibraryClient {
        RemoteMediaLibraryClient(
            fetchWelcome: { _, _ in
                .init(message: nil, version: nil, tokenRequired: false)
            },
            fetchBangumiList: { _, _, _ in [] },
            fetchBangumiDetail: { _, _, _ in
                Components.Schemas.LibraryBangumiDetailsResponse()
            },
            makeDirectStreamContext: { baseURL, _, fileID in
                let url = buildOperationURL(
                    baseURL: baseURL,
                    path: "/api/v1/stream/id/\(fileID)",
                    queryItems: []
                )
                return .init(url: url, headers: ["Accept": "video/*"])
            },
            makeStreamContext: { baseURL, _, fileID in
                let url = buildOperationURL(
                    baseURL: baseURL,
                    path: "/api/v1/stream/id/\(fileID)",
                    queryItems: []
                )
                return .init(url: url, headers: ["Accept": "video/*"])
            },
            fetchDanmakuXML: { _, _, _ in "" },
            fetchSubtitleInfo: { _, _, _ in [] },
            fetchSubtitleFile: { _, _, _, _ in "" }
        )
    }
    
    private static func makeClient(baseURL: URL, token: String?) throws -> RemoteMediaLibrary.Client {
        RemoteMediaLibrary.Client(
            serverURL: baseURL,
            configuration: .init(
                dateTranscoder: LenientRFC3339Transcoder(),
            ),
            transport: TokenTransport(token: token, next: URLSessionTransport())
        )
    }
}

private func buildOperationURL(
    baseURL: URL,
    path: String,
    queryItems: [URLQueryItem]
) -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
        return baseURL
    }
    var encodedPath = components.path
    if encodedPath.isEmpty || !encodedPath.hasSuffix("/") {
        encodedPath += "/"
    }
    let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
    components.path = encodedPath + trimmedPath
    if queryItems.isEmpty == false {
        components.queryItems = (components.queryItems ?? []) + queryItems
    }
    return components.url ?? baseURL.appendingPathComponent(trimmedPath)
}

private func buildDirectStreamContext(
    baseURL: URL,
    token: String?,
    fileID: String
) -> RemoteMediaLibraryClient.StreamContext {
    let path = "/api/v1/stream/id/\(fileID)"
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
    headers["Accept"] = "video/*"
    if let token, !token.isEmpty {
        headers["Authorization"] = "Bearer \(token)"
        queryItems.append(.init(name: "token", value: token))
    }
    let url = buildOperationURL(baseURL: baseURL, path: path, queryItems: queryItems)
    return .init(url: url, headers: headers)
}

private func fetchWebPlayerStreamContext(
    baseURL: URL,
    token: String?,
    fileID: String
) async throws -> RemoteMediaLibraryClient.StreamContext {
    let directStreamContext = buildDirectStreamContext(
        baseURL: baseURL,
        token: token,
        fileID: fileID
    )
    let pageURL = buildOperationURL(
        baseURL: baseURL,
        path: "/web1/video.html",
        queryItems: tokenQueryItems(token) + [.init(name: "id", value: fileID)]
    )
    let request = makeAuthorizedRequest(
        url: pageURL,
        token: token,
        accept: "text/html,application/xhtml+xml"
    )
    let data = try await fetchData(with: request)
    let html = String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: .unicode)
        ?? ""
    guard let relativePath = extractWebPlayerVideoPath(from: html) else {
        throw APIError.unexpectedResponse("播放页面里没有找到 DPlayer 视频地址。")
    }
    guard let playbackURL = resolveOperationURL(baseURL: baseURL, path: relativePath) else {
        throw APIError.unexpectedResponse("播放页面返回了无效的视频地址。")
    }

    if isWebPlayerHistorySyncURL(playbackURL, baseURL: baseURL) {
        scheduleWebPlayerHistorySync(url: playbackURL, token: token)
        return directStreamContext
    }

    return .init(url: playbackURL, headers: directStreamContext.headers)
}

private func extractWebPlayerVideoPath(from html: String) -> String? {
    let patterns = [
        #"url:\s*'([^']+)'"#,
        #"url:\s*"([^"]+)""#
    ]
    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html) else {
            continue
        }
        let path = String(html[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty {
            return path
        }
    }
    return nil
}

private func resolveOperationURL(baseURL: URL, path: String) -> URL? {
    guard !path.isEmpty else { return nil }
    if let absoluteURL = URL(string: path), absoluteURL.scheme != nil {
        return absoluteURL
    }
    return URL(string: path, relativeTo: baseURL)?.absoluteURL
}

private func isWebPlayerHistorySyncURL(_ url: URL, baseURL: URL) -> Bool {
    guard hasSameOrigin(url, as: baseURL) else { return false }
    return url.path.range(
        of: #"^/web1/video/[^/?#]+\.[^/?#]+$"#,
        options: .regularExpression
    ) != nil
}

private func hasSameOrigin(_ url: URL, as baseURL: URL) -> Bool {
    url.scheme?.lowercased() == baseURL.scheme?.lowercased()
        && url.host?.lowercased() == baseURL.host?.lowercased()
        && normalizedPort(for: url) == normalizedPort(for: baseURL)
}

private func normalizedPort(for url: URL) -> Int? {
    if let port = url.port {
        return port
    }
    switch url.scheme?.lowercased() {
    case "http":
        return 80
    case "https":
        return 443
    default:
        return nil
    }
}

private func scheduleWebPlayerHistorySync(url: URL, token: String?) {
    var request = makeAuthorizedRequest(url: url, token: token, accept: "*/*")
    request.timeoutInterval = 10
    request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
    NetworkDebugLogger.logURLRequest(request, label: "RemoteMediaLibraryHistorySync")
    HeaderOnlyRequestRunner.start(request: request, label: "RemoteMediaLibraryHistorySync")
}

private func mapSubtitleInfoPayload(
    _ payloads: Components.Schemas.SubtitleInfoResponse.SubtitlesPayload?
) -> [RemoteMediaLibraryClient.Subtitle] {
    (payloads ?? []).map { payload in
        let name: String
        if let fileName = payload.fileName, !fileName.isEmpty {
            name = fileName
        } else {
            name = "subtitle-\(UUID().uuidString)"
        }
        return .init(
            fileName: name,
            fileSize: payload.fileSize
        )
    }
}

private func fetchSubtitleInfoFallback(
    baseURL: URL,
    token: String?,
    fileID: String,
    reason: String
) async throws -> [RemoteMediaLibraryClient.Subtitle] {
#if DEBUG
    print("[Network][RemoteMediaLibraryFallback] subtitle info fallback reason: \(reason)")
#endif
    let url = buildOperationURL(
        baseURL: baseURL,
        path: "/api/v1/subtitle/info/\(fileID)",
        queryItems: tokenQueryItems(token)
    )
    let request = makeAuthorizedRequest(
        url: url,
        token: token,
        accept: "application/json"
    )
    let data = try await fetchData(with: request)
    NetworkDebugLogger.logBodyPreview(data, label: "RemoteMediaLibraryFallback.subtitleInfo")
    let object = try JSONSerialization.jsonObject(with: data)
    if let rawArray = object as? [[String: Any]] {
        return mapRawSubtitleInfoPayload(rawArray)
    }
    guard let dictionary = object as? [String: Any] else {
        throw APIError.unexpectedResponse("字幕列表响应不是 JSON 对象或数组。")
    }
    let rawSubtitles = (dictionary["subtitles"] as? [[String: Any]])
        ?? (dictionary["Subtitles"] as? [[String: Any]])
        ?? []
    return mapRawSubtitleInfoPayload(rawSubtitles)
}

private func fetchSubtitleFileFallback(
    baseURL: URL,
    token: String?,
    fileID: String,
    fileName: String
) async throws -> String {
    let candidates = [
        buildOperationURL(
            baseURL: baseURL,
            path: "/api/v1/subtitle/file/\(fileID)",
            queryItems: tokenQueryItems(token) + [.init(name: "fileName", value: fileName)]
        ),
        buildSubtitleWebURL(
            baseURL: baseURL,
            fileID: fileID,
            fileName: fileName,
            token: token
        )
    ]

    var lastError: Error?
    for url in candidates {
        do {
            let request = makeAuthorizedRequest(
                url: url,
                token: token,
                accept: "text/plain, text/x-ssa, text/ass, application/octet-stream;q=0.9, */*;q=0.8"
            )
            let data = try await fetchData(with: request)
            NetworkDebugLogger.logBodyPreview(data, label: "RemoteMediaLibraryFallback.subtitleFile")
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return text
            }
            if let text = String(data: data, encoding: .unicode), !text.isEmpty {
                return text
            }
            throw APIError.unexpectedResponse("字幕文件不是可识别的文本编码。")
        } catch {
            lastError = error
        }
    }

    throw lastError ?? APIError.unexpectedResponse("无法加载字幕文件。")
}

private func tokenQueryItems(_ token: String?) -> [URLQueryItem] {
    guard let token, !token.isEmpty else { return [] }
    return [.init(name: "token", value: token)]
}

private func buildSubtitleWebURL(
    baseURL: URL,
    fileID: String,
    fileName: String,
    token: String?
) -> URL {
    let components = fileName.split(separator: "/").map(String.init)
    let suffix = components.isEmpty ? [fileName] : components
    let path = (["web1", "subtitle", fileID] + suffix).joined(separator: "/")
    return buildOperationURL(
        baseURL: baseURL,
        path: path,
        queryItems: tokenQueryItems(token)
    )
}

private func makeAuthorizedRequest(
    url: URL,
    token: String?,
    accept: String? = nil
) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    if let accept, !accept.isEmpty {
        request.setValue(accept, forHTTPHeaderField: "Accept")
    }
    if let token, !token.isEmpty {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
}

private func fetchData(with request: URLRequest) async throws -> Data {
    NetworkDebugLogger.logURLRequest(request, label: "RemoteMediaLibraryFallback")
    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await URLSession.shared.data(for: request)
    } catch {
        NetworkDebugLogger.logURLRequestError(error, request: request, label: "RemoteMediaLibraryFallback")
        throw error
    }
    guard let httpResponse = response as? HTTPURLResponse else {
        throw APIError.unexpectedResponse("字幕接口没有返回 HTTP 响应。")
    }
    NetworkDebugLogger.logURLResponse(httpResponse, request: request, label: "RemoteMediaLibraryFallback")
    guard 200..<300 ~= httpResponse.statusCode else {
        throw APIError.serverError(statusCode: httpResponse.statusCode)
    }
    return data
}

private func mapRawSubtitleInfoPayload(_ rawSubtitles: [[String: Any]]) -> [RemoteMediaLibraryClient.Subtitle] {
    rawSubtitles.map { item in
        let fileName = (item["fileName"] as? String)
            ?? (item["FileName"] as? String)
            ?? "subtitle-\(UUID().uuidString)"
        let fileSize = (item["fileSize"] as? Int)
            ?? (item["FileSize"] as? Int)
        return .init(fileName: fileName, fileSize: fileSize)
    }
}

private final class HeaderOnlyRequestRunner: NSObject, URLSessionDataDelegate {
    private let request: URLRequest
    private let label: String
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    static func start(request: URLRequest, label: String) {
        let runner = HeaderOnlyRequestRunner(request: request, label: label)
        runner.start()
    }

    private init(request: URLRequest, label: String) {
        self.request = request
        self.label = label
    }

    private func start() {
        session.dataTask(with: request).resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let httpResponse = response as? HTTPURLResponse {
            NetworkDebugLogger.logURLResponse(httpResponse, request: request, label: label)
        } else {
            NetworkDebugLogger.logURLRequestError(
                APIError.unexpectedResponse("历史同步接口没有返回 HTTP 响应。"),
                request: request,
                label: label
            )
        }
        completionHandler(.cancel)
        session.finishTasksAndInvalidate()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            let nsError = error as NSError
            let isCancellation = nsError.domain == NSURLErrorDomain
                && nsError.code == NSURLErrorCancelled
            if !isCancellation {
                NetworkDebugLogger.logURLRequestError(error, request: request, label: label)
            }
        }
        session.finishTasksAndInvalidate()
    }
}

extension DependencyValues {
    var remoteMediaLibraryClient: RemoteMediaLibraryClient {
        get { self[RemoteMediaLibraryClient.self] }
        set { self[RemoteMediaLibraryClient.self] = newValue }
    }
}

private struct TokenTransport: ClientTransport {
    let token: String?
    let next: ClientTransport
    
    init(token: String?, next: ClientTransport) {
        self.token = token
        self.next = next
    }
    
    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        NetworkDebugLogger.logRequest(
            client: "RemoteMediaLibrary",
            operationID: operationID,
            request: request,
            baseURL: baseURL
        )
        guard let token, !token.isEmpty else {
            do {
                let result = try await next.send(request, body: body, baseURL: baseURL, operationID: operationID)
                NetworkDebugLogger.logResponse(
                    client: "RemoteMediaLibrary",
                    operationID: operationID,
                    request: request,
                    baseURL: baseURL,
                    response: result.0
                )
                return result
            } catch {
                NetworkDebugLogger.logError(
                    client: "RemoteMediaLibrary",
                    operationID: operationID,
                    request: request,
                    baseURL: baseURL,
                    error: error
                )
                throw error
            }
        }
        var mutableRequest = request
        mutableRequest.headerFields.append(.init(name: .authorization, value: "Bearer \(token)"))
        do {
            let result = try await next.send(mutableRequest, body: body, baseURL: baseURL, operationID: operationID)
            NetworkDebugLogger.logResponse(
                client: "RemoteMediaLibrary",
                operationID: operationID,
                request: mutableRequest,
                baseURL: baseURL,
                response: result.0
            )
            return result
        } catch {
            NetworkDebugLogger.logError(
                client: "RemoteMediaLibrary",
                operationID: operationID,
                request: mutableRequest,
                baseURL: baseURL,
                error: error
            )
            throw error
        }
    }
}

extension RemoteMediaLibrary.Client: BaseAPIProtocol {}

extension Operations.GetWelcomeMessage.Output.Ok: SuccessfulResponse {}

extension Operations.GetWelcomeMessage.Output.Ok.Body: SuccessResponseBody {
    public var model: Components.Schemas.WelcomeResponse? {
        try? self.json
    }
}

extension Operations.GetWelcomeMessage.Output: SuccessExtractable {
    public var successModel: Components.Schemas.WelcomeResponse? {
        guard case let .ok(response) = self else { return nil }
        return response.body.model
    }
}

extension Operations.GetWelcomeMessage.Output: UndocumentedCase {
    public var statusCode: Int {
        guard case let .undocumented(statusCode, _) = self else { return -1 }
        return statusCode
    }
}

extension Operations.GetLibrary.Output.Ok: SuccessfulResponse {}

extension Operations.GetLibrary.Output.Ok.Body: SuccessResponseBody {
    public var model: [Components.Schemas.LibraryVideoInfo]? {
        try? self.json
    }
}

extension Operations.GetLibrary.Output: SuccessExtractable {
    public var successModel: [Components.Schemas.LibraryVideoInfo]? {
        guard case let .ok(response) = self else { return nil }
        return response.body.model
    }
}

extension Operations.GetLibrary.Output: UndocumentedCase {
    public var statusCode: Int {
        guard case let .undocumented(statusCode, _) = self else { return -1 }
        return statusCode
    }
}

extension Operations.ListBangumiByLastPlay.Output.Ok: SuccessfulResponse {}

extension Operations.ListBangumiByLastPlay.Output.Ok.Body: SuccessResponseBody {
    public var model: [Components.Schemas.LibraryBangumiSummary]? {
        try? self.json
    }
}

extension Operations.ListBangumiByLastPlay.Output: SuccessExtractable {
    public var successModel: [Components.Schemas.LibraryBangumiSummary]? {
        guard case let .ok(response) = self else { return nil }
        return response.body.model
    }
}

extension Operations.ListBangumiByLastPlay.Output: UndocumentedCase {
    public var statusCode: Int {
        guard case let .undocumented(statusCode, _) = self else { return -1 }
        return statusCode
    }
}

extension Operations.ListBangumiByLastUpdate.Output.Ok: SuccessfulResponse {}

extension Operations.ListBangumiByLastUpdate.Output.Ok.Body: SuccessResponseBody {
    public var model: [Components.Schemas.LibraryBangumiSummary]? {
        try? self.json
    }
}

extension Operations.ListBangumiByLastUpdate.Output: SuccessExtractable {
    public var successModel: [Components.Schemas.LibraryBangumiSummary]? {
        guard case let .ok(response) = self else { return nil }
        return response.body.model
    }
}

extension Operations.ListBangumiByLastUpdate.Output: UndocumentedCase {
    public var statusCode: Int {
        guard case let .undocumented(statusCode, _) = self else { return -1 }
        return statusCode
    }
}

extension Operations.ListBangumiByLastAdd.Output.Ok: SuccessfulResponse {}

extension Operations.ListBangumiByLastAdd.Output.Ok.Body: SuccessResponseBody {
    public var model: [Components.Schemas.LibraryBangumiSummary]? {
        try? self.json
    }
}

extension Operations.ListBangumiByLastAdd.Output: SuccessExtractable {
    public var successModel: [Components.Schemas.LibraryBangumiSummary]? {
        guard case let .ok(response) = self else { return nil }
        return response.body.model
    }
}

extension Operations.ListBangumiByLastAdd.Output: UndocumentedCase {
    public var statusCode: Int {
        guard case let .undocumented(statusCode, _) = self else { return -1 }
        return statusCode
    }
}

extension Operations.ListBangumiBySeason.Output.Ok: SuccessfulResponse {}

extension Operations.ListBangumiBySeason.Output.Ok.Body: SuccessResponseBody {
    public var model: [Components.Schemas.LibraryBangumiSummary]? {
        try? self.json
    }
}

extension Operations.ListBangumiBySeason.Output: SuccessExtractable {
    public var successModel: [Components.Schemas.LibraryBangumiSummary]? {
        guard case let .ok(response) = self else { return nil }
        return response.body.model
    }
}

extension Operations.ListBangumiBySeason.Output: UndocumentedCase {
    public var statusCode: Int {
        guard case let .undocumented(statusCode, _) = self else { return -1 }
        return statusCode
    }
}

extension Operations.ListBangumiByName.Output.Ok: SuccessfulResponse {}

extension Operations.ListBangumiByName.Output.Ok.Body: SuccessResponseBody {
    public var model: [Components.Schemas.LibraryBangumiSummary]? {
        try? self.json
    }
}

extension Operations.ListBangumiByName.Output: SuccessExtractable {
    public var successModel: [Components.Schemas.LibraryBangumiSummary]? {
        guard case let .ok(response) = self else { return nil }
        return response.body.model
    }
}

extension Operations.ListBangumiByName.Output: UndocumentedCase {
    public var statusCode: Int {
        guard case let .undocumented(statusCode, _) = self else { return -1 }
        return statusCode
    }
}

extension Operations.ListBangumiByCategory.Output.Ok: SuccessfulResponse {}

extension Operations.ListBangumiByCategory.Output.Ok.Body: SuccessResponseBody {
    public var model: [Components.Schemas.LibraryBangumiSummary]? {
        try? self.json
    }
}

extension Operations.ListBangumiByCategory.Output: SuccessExtractable {
    public var successModel: [Components.Schemas.LibraryBangumiSummary]? {
        guard case let .ok(response) = self else { return nil }
        return response.body.model
    }
}

extension Operations.ListBangumiByCategory.Output: UndocumentedCase {
    public var statusCode: Int {
        guard case let .undocumented(statusCode, _) = self else { return -1 }
        return statusCode
    }
}

extension Operations.ListBangumiByRating.Output.Ok: SuccessfulResponse {}

extension Operations.ListBangumiByRating.Output.Ok.Body: SuccessResponseBody {
    public var model: [Components.Schemas.LibraryBangumiSummary]? {
        try? self.json
    }
}

extension Operations.ListBangumiByRating.Output: SuccessExtractable {
    public var successModel: [Components.Schemas.LibraryBangumiSummary]? {
        guard case let .ok(response) = self else { return nil }
        return response.body.model
    }
}

extension Operations.ListBangumiByRating.Output: UndocumentedCase {
    public var statusCode: Int {
        guard case let .undocumented(statusCode, _) = self else { return -1 }
        return statusCode
    }
}

extension Operations.GetBangumiDetails.Output.Ok: SuccessfulResponse {}

extension Operations.GetBangumiDetails.Output.Ok.Body: SuccessResponseBody {
    public var model: Components.Schemas.LibraryBangumiDetailsResponse? {
        try? self.json
    }
}

extension Operations.GetBangumiDetails.Output: SuccessExtractable {
    public var successModel: Components.Schemas.LibraryBangumiDetailsResponse? {
        guard case let .ok(response) = self else { return nil }
        return response.body.model
    }
}

extension Operations.GetBangumiDetails.Output: UndocumentedCase {
    public var statusCode: Int {
        guard case let .undocumented(statusCode, _) = self else { return -1 }
        return statusCode
    }
}
