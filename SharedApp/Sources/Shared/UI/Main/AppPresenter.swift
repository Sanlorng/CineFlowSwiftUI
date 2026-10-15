import ComposableArchitecture

@Reducer
struct AppPresenter {
    @ObservableState
    struct State: Equatable {
        var home = HomePresenter.State()
        var library = LibraryPresenter.State()
        var player: PlayerPresenter.State?
        var selectedTab: MainTabs = .Home
    }

    enum Action {
        case home(HomePresenter.Action)
        case library(LibraryPresenter.Action)
        case player(PlayerPresenter.Action)
        case selectTab(MainTabs)
        case stopPlayback
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.home, action: \.home) { HomePresenter() }
        Scope(state: \.library, action: \.library) { LibraryPresenter() }
        Reduce { state, action in
            switch action {
            case let .home(.delegate(.startPlayback(request))),
                 let .library(.delegate(.startPlayback(request))):
                state.player = PlayerPresenter.State(request: request)
                state.selectedTab = .Player
                return .none

            case let .selectTab(tab):
                state.selectedTab = tab
                return .none

            case .stopPlayback:
                state.player = nil
                if state.selectedTab == .Player { state.selectedTab = .Home }
                return .none

            case .home, .library, .player:
                return .none
            }
        }
        .ifLet(\.player, action: \.player) { PlayerPresenter() }
    }
}
