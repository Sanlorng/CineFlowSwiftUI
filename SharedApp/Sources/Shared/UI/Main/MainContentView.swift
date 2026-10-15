import SwiftUI
import ComposableArchitecture

struct MainContentView: View {
    let store: StoreOf<AppPresenter>

    var body: some View {
        TabView(selection: Binding(
            get: { store.selectedTab },
            set: { store.send(.selectTab($0)) }
        )) {
            Tab("首页", systemImage: "house", value: MainTabs.Home) {
                HomeContentView(store: store.scope(state: \.home, action: \.home))
            }
            Tab("媒体库", systemImage: "rectangle.stack", value: MainTabs.Library) {
                LibraryContentView(store: store.scope(state: \.library, action: \.library))
            }
            Tab("播放器", systemImage: "play.rectangle.on.rectangle", value: MainTabs.Player) {
                PlayerContentView(store: store.scope(state: \.player, action: \.player))
                    .id(store.player?.id)
            }
        }
        .tabViewStyle(.automatic)
    }
}
