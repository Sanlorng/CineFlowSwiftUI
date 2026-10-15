import ComposableArchitecture
import DanmakuRendererCore
import Foundation

@Reducer
struct PlayerDanmakuPresenter {
    @Dependency(\.remoteMediaLibraryClient) var remoteClient
    @Dependency(\.uuid) var uuid

    @ObservableState
    struct State: Equatable {
        struct LoadedDanmaku: Equatable, Sendable {
            let id: UUID
            let document: DanmakuDocument

            static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        }

        let context: PlaybackAttachmentContext
        var hasLoaded = false
        var isLoading = false
        var error: String?
        var document: LoadedDanmaku?
        var requestID: UUID?
    }

    enum Action: Equatable {
        case load
        case response(UUID, TaskResult<State.LoadedDanmaku>)
        case stop
    }

    private enum CancelID { case load }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .load:
                guard !state.hasLoaded else { return .none }
                state.hasLoaded = true
                guard let fileID = state.context.item?.file.id, !fileID.isEmpty,
                      let baseURL = state.context.configuration.baseURL else {
                    return .cancel(id: CancelID.load)
                }
                let requestID = uuid()
                state.requestID = requestID
                state.isLoading = true
                state.error = nil
                let token = state.context.configuration.apiToken
                return .run { [remoteClient] send in
                    let result = await TaskResult {
                        let xml = try await remoteClient.fetchDanmakuXML(baseURL, token, fileID)
                        try Task.checkCancellation()
                        return State.LoadedDanmaku(id: requestID, document: try BilibiliDanmakuParser.parse(xml: xml))
                    }
                    try Task.checkCancellation()
                    await send(.response(requestID, result))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .response(requestID, result):
                guard state.requestID == requestID else { return .none }
                state.requestID = nil
                state.isLoading = false
                switch result {
                case let .success(document):
                    state.document = document
                    state.error = nil
                case let .failure(error):
                    state.document = nil
                    state.error = error.localizedDescription
                }
                return .none

            case .stop:
                state.hasLoaded = false
                state.requestID = nil
                state.isLoading = false
                return .cancel(id: CancelID.load)
            }
        }
    }
}
