//
//  LibraryContentView.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/10/14.
//

import SwiftUI
import ComposableArchitecture
#if os(macOS)
import AppKit
#endif

struct LibraryContentView: View {
    let store: StoreOf<LibraryPresenter>
    
    var body: some View {
        NavigationStackStore(
            store.scope(state: \.path, action: \.path)
        ) {
            WithViewStore(store, observe: { $0 }) { viewStore in
                mainContent(viewStore)
                    .sheet(
                        isPresented: Binding(
                            get: { viewStore.isShowingForm },
                            set: { viewStore.send(.setIsShowingForm($0)) }
                        )
                    ) {
                        ConfigurationFormView(store: store)
                    }
            }
        } destination: { destination in
            IfLetStore(
                destination.scope(
                    state: /LibraryPresenter.Path.State.bangumiDetail,
                    action: { .bangumiDetail($0) }
                ),
                then: BangumiDetailView.init(store:)
            )
            IfLetStore(
                destination.scope(
                    state: /LibraryPresenter.Path.State.player,
                    action: { .player($0) }
                ),
                then: PlayerContentView.init(store:)
            )
        }
    }
    
    @ViewBuilder
    private func mainContent(_ viewStore: ViewStore<LibraryPresenter.State, LibraryPresenter.Action>) -> some View {
        let hasSelectedConfiguration = viewStore.selectedConfigurationID != nil
        VStack(spacing: 0) {
            libraryList(viewStore)
        }
        .navigationTitle("远程媒体库")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                librarySearchField(viewStore)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewStore.send(.setIsShowingForm(true))
                } label: {
                    Label("新增", systemImage: "plus")
                }
                Picker(
                    selection: Binding<UUID?>(
                        get: { viewStore.selectedConfigurationID },
                        set: { id in
                            if (id != nil) {
                                viewStore.send(.selectConfiguration(id!)) 
                            }
                        }
                    ),
                ) {
                    ForEach(viewStore.configurations) { configuration in
                        Text(configuration.name)
                            .tag(configuration.id)
                    }

                    if viewStore.configurations.isEmpty {
                        Text("无可用媒体库")
                            .tag(UUID?.none)
                    }
                    
                } label: {
                    Label("选择媒体库", systemImage: "externaldrive")
                }

                let hasSelectedConfiguration = viewStore.selectedConfigurationID != nil

                Picker(
                    selection: Binding(
                        get: { viewStore.selectedSort },
                        set: { viewStore.send(.setSort($0)) }
                    ),
                ) {
                    ForEach(LibraryPresenter.SortOption.allCases, id: \.self) { sort in
                        Text(sort.displayName)
                            .tag(sort)
                    }
                    
                } label: {
                    Label("选择排序方式", systemImage: "square.grid.3x1.below.line.grid.1x2")
                }
                .disabled(!hasSelectedConfiguration || viewStore.isLoadingLibrary)

                Button {
                    viewStore.send(.refresh)
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(!hasSelectedConfiguration || viewStore.isLoadingLibrary)
            }
        }
        .onAppear {
            viewStore.send(.onAppear)
        }
    }

    @ViewBuilder
    private func librarySearchField(
        _ viewStore: ViewStore<LibraryPresenter.State, LibraryPresenter.Action>
    ) -> some View {
        AdaptiveLibraryToolbarSearchField(
            query: Binding(
                get: { viewStore.searchQuery },
                set: { viewStore.send(.setSearchQuery($0)) }
            )
        )
    }
    
    @ViewBuilder
    private func libraryList(_ viewStore: ViewStore<LibraryPresenter.State, LibraryPresenter.Action>) -> some View {
        Group {
            if viewStore.isLoadingLibrary {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载媒体库…")
                        .foregroundColor(.secondary)
                }
            } else if let message = viewStore.infoMessage {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding()
                if viewStore.configurations.isEmpty {

                    Button {
                        viewStore.send(.setIsShowingForm(true))
                    } label: {
                        Label("添加远程媒体库", systemImage: "plus")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if viewStore.displayedBangumiItems.isEmpty {
                if viewStore.trimmedSearchQuery.isEmpty {
                    Text("没有可显示的动漫内容。")
                        .foregroundColor(.secondary)
                } else {
                    Text("没有匹配“\(viewStore.trimmedSearchQuery)”的番剧。")
                        .foregroundColor(.secondary)
                }
            } else if viewStore.bangumiItems.isEmpty {
                Text("没有可显示的动漫内容。")
                    .foregroundColor(.secondary)
            } else {
                LibraryGrid(viewStore: viewStore)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    static func makeMetadataLine(for item: LibraryPresenter.State.BangumiItem) -> String? {
        var components: [String] = []
        if let progress = item.episodeProgress {
            components.append(progress)
        }
        if let rating = item.rating ?? item.userRating {
            components.append(String(format: "评分 %.1f", rating))
        }
        if let count = item.videoFileCount, count > 0 {
            components.append("文件 \(count)")
        }
        return components.isEmpty ? nil : components.joined(separator: " • ")
    }
}

private struct AdaptiveLibraryToolbarSearchField: View {
    @Binding var query: String
    @State private var isPopoverPresented = false
    @State private var isWindowActive = true
    @FocusState private var isInlineFieldFocused: Bool
    @FocusState private var isPopoverFieldFocused: Bool

    private let collapsedButtonSize: CGFloat = 32
    private let minimumExpandedWidth: CGFloat = 144
    private let idealExpandedWidth: CGFloat = 160
    private let maximumExpandedWidth: CGFloat = 240
    private let popoverExpandedWidth: CGFloat = 220

    var body: some View {
        ViewThatFits(in: .horizontal) {
            searchField(
                focused: $isInlineFieldFocused,
                isFocused: isInlineFieldFocused && isWindowActive
            )
                .frame(
                    minWidth: minimumExpandedWidth,
                    idealWidth: idealExpandedWidth,
                    maxWidth: maximumExpandedWidth
                )

            collapsedSearchButton
        }
#if os(macOS)
        .background {
            LibraryToolbarWindowActivationObserver { isActive in
                isWindowActive = isActive
            }
            .frame(width: 0, height: 0)
        }
#endif
    }

    private var collapsedSearchButton: some View {
        Button {
            isPopoverPresented = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(searchAccentColor)
                .frame(width: collapsedButtonSize, height: collapsedButtonSize)
                .background {
                    Capsule(style: .continuous)
                        .fill(.clear)
                        .glassEffect()
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(searchBorderColor, lineWidth: 0.6)
                }
        }
        .buttonStyle(.plain)
        .help("搜索番剧")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            searchField(
                focused: $isPopoverFieldFocused,
                isFocused: isPopoverFieldFocused && isWindowActive
            )
                .frame(width: popoverExpandedWidth)
                .onAppear {
                    isPopoverFieldFocused = true
                }
        }
    }

    @ViewBuilder
    private func searchField(
        focused focusBinding: FocusState<Bool>.Binding,
        isFocused: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(searchPromptAndIconColor)

            TextField(
                "搜索番剧",
                text: $query,
                prompt: Text("搜索番剧").foregroundColor(searchPromptAndIconColor)
            )
            .textFieldStyle(.plain)
            .foregroundColor(searchTextColor)
            .focused(focusBinding)

            if !query.isEmpty {
                Button {
                    query = ""
                    focusBinding.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(searchPromptAndIconColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(height: collapsedButtonSize)
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    isFocused ? Color.accentColor.opacity(0.42) : .clear,
                    lineWidth: isFocused ? 1 : 0
                )
        }
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            focusBinding.wrappedValue = true
        }
    }

    private var searchBorderColor: Color {
        if isInlineFieldFocused || isPopoverFieldFocused {
            return .accentColor.opacity(0.28)
        }
        return .white.opacity(query.isEmpty ? 0.14 : 0.22)
    }

    private var searchAccentColor: Color {
        isWindowActive ? (query.isEmpty ? .primary : .accentColor) : searchPromptAndIconColor
    }

    private var searchPromptAndIconColor: Color {
        isWindowActive ? .secondary : disabledSearchColor
    }

    private var searchTextColor: Color {
        isWindowActive ? .primary : disabledSearchColor
    }

    private var disabledSearchColor: Color {
#if os(macOS)
        Color(nsColor: .disabledControlTextColor)
#else
        .secondary
#endif
    }
}

#if os(macOS)
private struct LibraryToolbarWindowActivationObserver: NSViewRepresentable {
    let onActiveStateChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onActiveStateChanged: onActiveStateChanged)
    }

    func makeNSView(context: Context) -> LibraryToolbarWindowObserverView {
        let view = LibraryToolbarWindowObserverView(frame: .zero)
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: LibraryToolbarWindowObserverView, context: Context) {
        view.coordinator = context.coordinator
        context.coordinator.refresh(for: view.window)
    }

    @MainActor
    final class Coordinator: NSObject {
        private let onActiveStateChanged: (Bool) -> Void
        private weak var observedWindow: NSWindow?
        private var notificationTokens: [NSObjectProtocol] = []

        init(onActiveStateChanged: @escaping (Bool) -> Void) {
            self.onActiveStateChanged = onActiveStateChanged
        }

        func refresh(for window: NSWindow?) {
            guard observedWindow !== window else {
                reportActiveState()
                return
            }

            notificationTokens.forEach(NotificationCenter.default.removeObserver)
            notificationTokens.removeAll()
            observedWindow = window
            reportActiveState()

            guard let window else { return }

            notificationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportActiveState()
                }
            )

            notificationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportActiveState()
                }
            )

            notificationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportActiveState()
                }
            )

            notificationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportActiveState()
                }
            )
        }

        private func reportActiveState() {
            let isActive = (observedWindow?.isKeyWindow ?? false) && NSApp.isActive
            Task { @MainActor in
                onActiveStateChanged(isActive)
            }
        }
    }
}

private final class LibraryToolbarWindowObserverView: NSView {
    weak var coordinator: LibraryToolbarWindowActivationObserver.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.refresh(for: window)
    }
}
#endif

private struct LibraryGrid: View {
    @ObservedObject var viewStore: ViewStore<LibraryPresenter.State, LibraryPresenter.Action>
    @State private var selectedGroup: String?
    @State private var isProgrammaticScroll = false
    
    var body: some View {
        ScrollViewReader { proxy in
            let hasSidebar = viewStore.groupedBangumiItems.count > 1
            HStack(alignment: .top, spacing: 12) {
                GeometryReader { geometry in
                    let gridMetrics = libraryGridMetrics(for: geometry.size.width)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(viewStore.groupedBangumiItems, id: \.group) { group in
                                Section {
                                    LazyVGrid(columns: gridMetrics.columns, spacing: 16) {
                                        ForEach(group.items) { item in
                                            LibraryCard(item: item, width: gridMetrics.itemWidth) {
                                                viewStore.send(.bangumiTapped(item))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                } header: {
                                    HStack {
                                        Text(group.group)
                                            .font(.title2)
                                            .bold()
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .id(group.group)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear
                                                .preference(
                                                    key: GroupPositionPreferenceKey.self,
                                                    value: [group.group: geo.frame(in: .named("LibraryGridScroll")).minY]
                                                )
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .coordinateSpace(name: "LibraryGridScroll")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasSidebar {
                    GroupSidebar(
                        groups: viewStore.groupTitles,
                        selected: selectedGroup ?? viewStore.groupTitles.first,
                        action: { group in
                            withAnimation(.easeInOut) {
                                isProgrammaticScroll = true
                                proxy.scrollTo(group, anchor: .top)
                                selectedGroup = group
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    isProgrammaticScroll = false
                                }
                            }
                        }
                    )
                    .padding(.top, 24)
                }
            }
            .onAppear {
                selectedGroup = viewStore.groupTitles.first
            }
            .onGroupTitlesChange(viewStore.groupTitles) { newValue in
                guard let current = selectedGroup, newValue.contains(current) else {
                    selectedGroup = newValue.first
                    return
                }
            }
            .onPreferenceChange(GroupPositionPreferenceKey.self) { positions in
                guard !positions.isEmpty, !isProgrammaticScroll else { return }
                let sorted = positions.sorted { $0.value < $1.value }
                let threshold: CGFloat = 80
                let current = sorted.last(where: { $0.value <= threshold }) ?? sorted.first
                if let group = current?.key, group != selectedGroup {
                    selectedGroup = group
                }
            }
        }
    }
}

private struct LibraryCard: View {
    let item: LibraryPresenter.State.BangumiItem
    let width: CGFloat
    let onTap: () -> Void

    private let cardPadding: CGFloat = 12
    private let coverCornerRadius: CGFloat = 14
    private let coverAspectRatio: CGFloat = 2 / 3
    
    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(.plain)
    }
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            coverContainer
            
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                
                Text(localizedLibraryCardDate(item.onAirDate))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let metadata = LibraryContentView.makeMetadataLine(for: item) {
                    Text(metadata)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(cardPadding)
        .frame(width: width, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    private var coverContainer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: coverCornerRadius)
                .fill(Color.secondary.opacity(0.08))
            coverView
        }
        .frame(width: coverWidth)
        .aspectRatio(coverAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: coverCornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: coverCornerRadius))
    }
    
    @ViewBuilder
    private var coverView: some View {
        if let url = item.coverURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .clipped()
                case .failure:
                    placeholder
                case .empty:
                    ZStack {
                        placeholder
                        ProgressView()
                    }
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }
    
    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let initial = item.title.first {
                Text(String(initial))
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var coverWidth: CGFloat {
        max(width - (cardPadding * 2), 0)
    }
}

private struct LibraryGridMetrics {
    let columns: [GridItem]
    let itemWidth: CGFloat
}

private func libraryGridMetrics(for availableWidth: CGFloat) -> LibraryGridMetrics {
    let minimumItemWidth: CGFloat = 180
    let maximumItemWidth: CGFloat = 220
    let spacing: CGFloat = 16
    let resolvedWidth = max(availableWidth - 32, minimumItemWidth)
    let columnCount = max(
        Int((resolvedWidth + spacing) / (minimumItemWidth + spacing)),
        1
    )
    let rawItemWidth = (resolvedWidth - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
    let itemWidth = min(max(rawItemWidth, minimumItemWidth), maximumItemWidth)
    let columns = Array(
        repeating: GridItem(.fixed(itemWidth), spacing: spacing, alignment: .top),
        count: columnCount
    )
    return .init(columns: columns, itemWidth: itemWidth)
}

private struct GroupSidebar: View {
    let groups: [String]
    let selected: String?
    let action: (String) -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(groups, id: \.self) { group in
                        Button {
                            action(group)
                        } label: {
                            Text(group)
                                .font(.caption)
                                .foregroundColor(selected == group ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(selected == group ? Color.accentColor : Color.secondary.opacity(0.2))
                                )
                        }
                        .id(group)
                        .buttonStyle(.plain)
                    }
                }
            }
            .onAppear {
                guard let selected else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
            .onChange(of: selected) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(maxHeight: 360)
        .padding(.horizontal, 4)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct GroupPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }
    
    static func reduce(value: inout [String : CGFloat], nextValue: () -> [String : CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

private func localizedLibraryCardDate(_ date: Date) -> String {
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

private func localizedLibraryCardDate(_ date: Date?) -> String {
    guard let date else {
        return "暂无播出日期"
    }
    return localizedLibraryCardDate(date)
}

private extension View {
    @ViewBuilder
    func onGroupTitlesChange(_ titles: [String], perform action: @escaping ([String]) -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.onChange(of: titles) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: titles) { newValue in
                action(newValue)
            }
        }
    }
}

private struct ConfigurationFormView: View {
    let store: StoreOf<LibraryPresenter>
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationStack {
                Form {
                    Section("基本信息") {
                        TextField(
                            "配置名称",
                            text: Binding(
                                get: { viewStore.formName },
                                set: { viewStore.send(.setFormName($0)) }
                            )
                        )
                        TextField(
                            "IP 地址或域名",
                            text: Binding(
                                get: { viewStore.formIP },
                                set: { viewStore.send(.setFormIP($0)) }
                            )
                        )
#if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
#endif
                        TextField(
                            "端口",
                            text: Binding(
                                get: { viewStore.formPort },
                                set: { viewStore.send(.setFormPort($0)) }
                            )
                        )
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    }
                    
                    Section("安全") {
                        SecureField(
                            "API Token（如需要）",
                            text: Binding(
                                get: { viewStore.formToken },
                                set: { viewStore.send(.setFormToken($0)) }
                            )
                        )
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
#endif
                        if viewStore.formRequiresToken == true {
                            Text("已检测到该媒体库启用了 API 加密，必须提供 Token。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let error = viewStore.formError {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                        }
                    }
                }
                .disabled(viewStore.isCheckingWelcome)
                .navigationTitle("新增媒体库")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            viewStore.send(.setIsShowingForm(false))
                        }
                        .disabled(viewStore.isCheckingWelcome)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            viewStore.send(.saveNewConfiguration)
                        } label: {
                            if viewStore.isCheckingWelcome {
                                ProgressView()
                            } else {
                                Text("保存")
                            }
                        }
                        .disabled(viewStore.isCheckingWelcome)
                    }
                }
            }
        }
    }
}
