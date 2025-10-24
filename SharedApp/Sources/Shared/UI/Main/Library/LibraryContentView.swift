//
//  LibraryContentView.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/10/14.
//

import SwiftUI
import ComposableArchitecture

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
        }
    }
    
    @ViewBuilder
    private func mainContent(_ viewStore: ViewStore<LibraryPresenter.State, LibraryPresenter.Action>) -> some View {
        VStack(spacing: 0) {
            libraryList(viewStore)
        }
        .navigationTitle("远程媒体库")
        .toolbar {
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
        if let group = item.groupName, !group.isEmpty {
            components.append(group)
        }
        if let count = item.videoFileCount, count > 0 {
            components.append("文件 \(count)")
        }
        return components.isEmpty ? nil : components.joined(separator: " • ")
    }
}

private struct LibraryGrid: View {
    @ObservedObject var viewStore: ViewStore<LibraryPresenter.State, LibraryPresenter.Action>
    @State private var selectedGroup: String?
    @State private var isProgrammaticScroll = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16, alignment: .top)
    ]
    
    var body: some View {
        ScrollViewReader { proxy in
            let hasSidebar = viewStore.groupedBangumiItems.count > 1
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                    ForEach(viewStore.groupedBangumiItems, id: \.group) { group in
                        Section {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(group.items) { item in
                                    LibraryCard(item: item) {
                                        viewStore.send(.bangumiTapped(item))
                                    }
                                }
                            }
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
                            .background(.regularMaterial)
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
            .padding(.leading, 0)
            .padding(.trailing, hasSidebar ? 120 : 0)
            .overlay(alignment: .topTrailing) {
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
                    .padding(.trailing, 12)
                    .padding(.top, 32)
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
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(.plain)
    }
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            coverView
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if let details = item.details, !details.isEmpty {
                    Text(details)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let metadata = LibraryContentView.makeMetadataLine(for: item) {
                    Text(metadata)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
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
    }
}

private struct GroupSidebar: View {
    let groups: [String]
    let selected: String?
    let action: (String) -> Void
    
    var body: some View {
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
                            .frame(minWidth: 72, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 110, alignment: .trailing)
        .frame(maxHeight: 360)
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
    }
}

private struct GroupPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }
    
    static func reduce(value: inout [String : CGFloat], nextValue: () -> [String : CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
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
