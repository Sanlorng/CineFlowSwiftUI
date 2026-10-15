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
        
        var configurations: IdentifiedArrayOf<MediaLibraryConfiguration> = []
        var path = StackState<Path.State>()
        var selectedConfigurationID: UUID?
        var bangumiItems: IdentifiedArrayOf<BangumiItem> = []
        var selectedSort: MediaLibrarySort = .lastPlay
        var searchQuery: String = ""
        
        var libraryRequestID: UUID?
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
    
    enum Action: Equatable {
        case onAppear
        case configurationsLoaded([MediaLibraryConfiguration])
        case configurationsFailed(String)
        case selectConfiguration(UUID)
        case refresh
        case fetchLibrary(UUID)
        case libraryLoaded(UUID, UUID, MediaLibrarySort, [State.BangumiItem])
        case libraryFailed(UUID, UUID, MediaLibrarySort, String)
        case setIsShowingForm(Bool)
        case saveNewConfiguration
        case welcomeChecked(WelcomePayload)
        case welcomeCheckFailed(String)
        case configurationSaved(MediaLibraryConfiguration)
        case configurationSaveFailed(String)
        case setFormName(String)
        case setFormIP(String)
        case setFormPort(String)
        case setFormToken(String)
        case setSort(MediaLibrarySort)
        case setSearchQuery(String)
        case bangumiTapped(State.BangumiItem)
        case delegate(DelegateAction)
        case path(StackAction<Path.State, Path.Action>)
    }
    
    enum DelegateAction: Equatable {
        case startPlayback(PlaybackRequest)
    }

    @Dependency(\.remoteLibraryConfigurationOperation) var configurationOperation
    @Dependency(\.remoteMediaLibraryClient) var remoteClient
    @Dependency(\.uuid) var uuid

    private enum CancelID { case library }

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

            case let .path(.element(id: _, action: .bangumiDetail(.delegate(.startPlayback(playerState))))):
                return .send(.delegate(.startPlayback(playerState)))

            case .path:
                return .none

            case .delegate:
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
                let requestID = uuid()
                state.libraryRequestID = requestID
                state.isLoadingLibrary = true
                state.infoMessage = nil
                return .run { [token = configuration.apiToken, remoteClient, sort] send in
                    do {
                        let items = try await remoteClient.fetchBangumiList(baseURL, token, sort)
                        let mapped = items.map { State.BangumiItem($0, baseURL: baseURL) }
                        try Task.checkCancellation()
                        await send(.libraryLoaded(requestID, id, sort, mapped))
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.libraryFailed(requestID, id, sort, error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.library, cancelInFlight: true)
                
            case let .libraryLoaded(requestID, id, sort, items):
                guard state.libraryRequestID == requestID,
                      state.selectedConfigurationID == id,
                      state.selectedSort == sort else { return .none }
                state.libraryRequestID = nil
                state.isLoadingLibrary = false
                state.bangumiItems = IdentifiedArray(uniqueElements: items)
                if items.isEmpty {
                    state.infoMessage = "媒体库为空。"
                }
                return .none
                
            case let .libraryFailed(requestID, id, sort, message):
                guard state.libraryRequestID == requestID,
                      state.selectedConfigurationID == id,
                      state.selectedSort == sort else { return .none }
                state.libraryRequestID = nil
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
                        await send(.welcomeCheckFailed(RemoteMediaLibraryNetworking.validationErrorMessage(for: error)))
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
                await send(.configurationsLoaded(records.map(MediaLibraryConfiguration.init(record:))))
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
            onAirDate.map(localizedLibrarySearchDate),
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

private func localizedLibrarySearchDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    if let preferredLanguage = Locale.preferredLanguages.first, !preferredLanguage.isEmpty {
        formatter.locale = Locale(identifier: preferredLanguage)
    } else {
        formatter.locale = .autoupdatingCurrent
    }
    formatter.calendar = .autoupdatingCurrent
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}
