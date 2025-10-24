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
            let details: String?
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
                 details: String?,
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
                self.details = details
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
        case bangumiTapped(State.BangumiItem)
        case path(StackAction<Path.State, Path.Action>)
    }
    
    @Dependency(\.remoteLibraryConfigurationOperation) var configurationOperation
    @Dependency(\.remoteMediaLibraryClient) var remoteClient

    @Reducer
    struct Path {
        enum State: Equatable {
            case bangumiDetail(BangumiDetailPresenter.State)
        }

        enum Action: Equatable {
            case bangumiDetail(BangumiDetailPresenter.Action)
        }

        var body: some ReducerOf<Self> {
            Scope(state: /State.bangumiDetail, action: /Action.bangumiDetail) {
                BangumiDetailPresenter()
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
            details: summary.details,
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
    var groupedBangumiItems: [(group: String, items: [BangumiItem])] {
        var order: [String] = []
        var storage: [String: [BangumiItem]] = [:]
        
        for item in bangumiItems {
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

struct RemoteMediaLibraryClient {
    struct Welcome: Equatable {
        let message: String?
        let version: String?
        let tokenRequired: Bool
    }
    
    var fetchWelcome: @Sendable (_ baseURL: URL, _ token: String?) async throws -> Welcome
    var fetchBangumiList: @Sendable (_ baseURL: URL, _ token: String?, _ sort: LibraryPresenter.SortOption) async throws -> [Components.Schemas.LibraryBangumiSummary]
    var fetchBangumiDetail: @Sendable (_ baseURL: URL, _ token: String?, _ animeId: Int) async throws -> Components.Schemas.LibraryBangumiDetailsResponse
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
                            localMatchedFiles: [],
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
                            localMatchedExists: false,
                            localMatchedFiles: [],
                            canMarkAsWatched: true
                        )
                    ]
                )
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
            }
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
        guard let token, !token.isEmpty else {
            return try await next.send(request, body: body, baseURL: baseURL, operationID: operationID)
        }
        var mutableRequest = request
        mutableRequest.headerFields.append(.init(name: .authorization, value: "Bearer \(token)"))
        return try await next.send(mutableRequest, body: body, baseURL: baseURL, operationID: operationID)
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
