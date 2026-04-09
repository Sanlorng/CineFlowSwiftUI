//
//  HomeContentView.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/28.
//

import Foundation
import SwiftUI
import ComposableArchitecture

struct HomeContentView: View {
    let store: StoreOf<HomePresenter>
    @Environment(\.openURL) private var openURL
    @State private var currentBannerIndex = 0

    private let scheduleColumns = [
        GridItem(.adaptive(minimum: 148, maximum: 188), spacing: 16, alignment: .top)
    ]

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    bannerSection(viewStore)
                    quickStatusSection(viewStore)

                    if shouldShowSearchSection(viewStore) {
                        homeSearchSection(viewStore)
                    }

                    seasonScheduleSection(viewStore)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .navigationTitle("首页")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    AdaptiveToolbarSearchField(
                        query: Binding(
                            get: { viewStore.homeSearchQuery },
                            set: { viewStore.send(.setHomeSearchQuery($0)) }
                        ),
                        placeholder: "搜索番剧",
                        helpText: "使用弹弹 API 搜索番剧"
                    )
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewStore.send(.refresh)
                    } label: {
                        Label("刷新首页", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewStore.isLoadingHomepage || viewStore.isLoadingSeason)
                }
            }
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }

    @ViewBuilder
    private func bannerSection(_ viewStore: ViewStore<HomePresenter.State, HomePresenter.Action>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("公告")

            if viewStore.isLoadingHomepage && viewStore.banners.isEmpty {
                placeholderPanel("正在加载首页内容…")
            } else if let message = viewStore.homepageErrorMessage, viewStore.banners.isEmpty {
                messagePanel(title: "首页加载失败", message: message)
            } else if viewStore.banners.isEmpty {
                placeholderPanel("当前没有可展示的公告。")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    bannerCarousel(viewStore.banners)

                    if viewStore.banners.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(Array(viewStore.banners.enumerated()), id: \.element.id) { index, _ in
                                Capsule(style: .continuous)
                                    .fill(index == currentBannerIndex ? Color.primary : Color.secondary.opacity(0.22))
                                    .frame(width: index == currentBannerIndex ? 22 : 8, height: 8)
                            }
                        }
                    }
                }
                .task(id: viewStore.banners.map(\.id)) {
                    currentBannerIndex = 0
                    guard viewStore.banners.count > 1 else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { break }
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                advanceBanner(total: viewStore.banners.count)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quickStatusSection(_ viewStore: ViewStore<HomePresenter.State, HomePresenter.Action>) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                quickStatusCards(viewStore)
            }

            VStack(alignment: .leading, spacing: 16) {
                quickStatusCards(viewStore)
            }
        }
    }

    @ViewBuilder
    private func quickStatusCards(_ viewStore: ViewStore<HomePresenter.State, HomePresenter.Action>) -> some View {
        Group {
            quickStatusCard(
                title: "未看番剧",
                subtitle: "首页 API 支持返回未看番剧，但当前 API key 不具备用户相关权限。",
                icon: "clock.badge.exclamationmark",
                accent: Color.orange,
                items: viewStore.unwatchedItems
            )

            quickStatusCard(
                title: "继续播放",
                subtitle: "后续会接本地数据库和最终播放器抽象，这里暂时不接数据。",
                icon: "play.circle",
                accent: Color.blue,
                items: []
            )
        }
    }

    @ViewBuilder
    private func homeSearchSection(_ viewStore: ViewStore<HomePresenter.State, HomePresenter.Action>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("搜索结果")
                Spacer()
                if viewStore.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let message = viewStore.searchErrorMessage {
                messagePanel(title: "搜索失败", message: message)
            } else if viewStore.isSearching && viewStore.homeSearchResults.isEmpty {
                placeholderPanel("正在搜索“\(viewStore.trimmedHomeSearchQuery)”…")
            } else if !viewStore.trimmedHomeSearchQuery.isEmpty && viewStore.homeSearchResults.isEmpty {
                placeholderPanel("没有找到与“\(viewStore.trimmedHomeSearchQuery)”相关的番剧。")
            } else {
                LazyVGrid(columns: scheduleColumns, spacing: 16) {
                    ForEach(viewStore.homeSearchResults) { item in
                        SearchResultCard(item: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func seasonScheduleSection(_ viewStore: ViewStore<HomePresenter.State, HomePresenter.Action>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                sectionTitle("新番时间表")

                Picker(
                    "季度",
                    selection: Binding(
                        get: { viewStore.selectedSeasonID },
                        set: { id in
                            guard let id else { return }
                            viewStore.send(.selectedSeasonChanged(id))
                        }
                    )
                ) {
                    ForEach(viewStore.seasons) { season in
                        Text(season.name)
                            .tag(Optional(season.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)

                Button {
                    viewStore.send(.refresh)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewStore.isLoadingHomepage || viewStore.isLoadingSeason)

                Spacer()

                ScheduleFilterField(
                    text: Binding(
                        get: { viewStore.seasonFilterQuery },
                        set: { viewStore.send(.setSeasonFilterQuery($0)) }
                    ),
                    placeholder: "筛选当前时间表"
                )
                .frame(width: 250)
            }

            scheduleDaySelector(viewStore)

            if let message = viewStore.seasonErrorMessage {
                messagePanel(title: "时间表加载失败", message: message)
            } else if viewStore.isLoadingSeason && viewStore.seasonItems.isEmpty {
                placeholderPanel("正在加载季度番剧…")
            } else if viewStore.selectedSeason == nil {
                placeholderPanel("当前没有可选季度。")
            } else if viewStore.filteredSeasonItems.isEmpty {
                placeholderPanel(emptyScheduleMessage(viewStore))
            } else {
                LazyVGrid(columns: scheduleColumns, spacing: 16) {
                    ForEach(viewStore.filteredSeasonItems) { item in
                        SeasonBangumiCard(item: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func scheduleDaySelector(_ viewStore: ViewStore<HomePresenter.State, HomePresenter.Action>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(HomePresenter.State.ScheduleDay.allCases) { day in
                    Button {
                        viewStore.send(.selectedScheduleDayChanged(day))
                    } label: {
                        Text(day.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(viewStore.selectedScheduleDay == day ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        viewStore.selectedScheduleDay == day
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.12)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func quickStatusCard(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        items: [HomePresenter.State.BangumiItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if items.isEmpty {
                Text("暂不可用")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                    )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items.prefix(3)) { item in
                        HStack(spacing: 10) {
                            HomePosterThumbnail(url: item.imageURL, title: item.title)
                                .frame(width: 42, height: 60)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(item.searchKeyword ?? "有未观看更新")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    @ViewBuilder
    private func bannerCarousel(_ banners: [HomePresenter.State.Banner]) -> some View {
        let safeIndex = min(max(currentBannerIndex, 0), max(banners.count - 1, 0))

        ZStack(alignment: .bottomTrailing) {
            bannerCard(banners[safeIndex])
                .transition(.opacity.combined(with: .scale(scale: 0.985)))

            if banners.count > 1 {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentBannerIndex = (safeIndex - 1 + banners.count) % banners.count
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            advanceBanner(total: banners.count)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .padding(18)
            }
        }
        .frame(height: 320)
    }

    private func bannerCard(_ banner: HomePresenter.State.Banner) -> some View {
        Button {
            guard let url = banner.url else { return }
            openURL(url)
        } label: {
            GeometryReader { geometry in
                let size = geometry.size
                let horizontalInset = max(min(size.width * 0.03, 28), 18)
                let verticalInset = max(min(size.height * 0.08, 24), 16)
                let textPanelMaxWidth = min(max(size.width * 0.34, 280), 420)
                let textPanelMaxHeight = max(size.height - (verticalInset * 2), 120)

                let containerShape = RoundedRectangle(cornerRadius: 30, style: .continuous)

                ZStack {
                    bannerBackground(banner)

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.08),
                            Color.black.opacity(0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.42),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .frame(width: size.width, height: size.height)
                .background(containerShape.fill(Color.black.opacity(0.08)))
                .clipShape(containerShape)
                .overlay(
                    containerShape
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("FEATURED")
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.78))

                        VStack(alignment: .leading, spacing: 10) {
                            Text(banner.title)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            if !banner.description.isEmpty {
                                Text(banner.description)
                                    .font(.headline)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(3)
                            }
                        }

                        HStack(spacing: 10) {
                            Label("查看详情", systemImage: "arrow.up.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.black.opacity(0.84))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.92))
                                )

                            Text("公告")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                    .frame(maxWidth: textPanelMaxWidth, maxHeight: textPanelMaxHeight, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.28),
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.leading, horizontalInset)
                    .padding(.bottom, verticalInset)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 308)
            .shadow(color: .black.opacity(0.14), radius: 24, y: 14)
        }
        .buttonStyle(.plain)
        .disabled(banner.url == nil)
    }

    private func advanceBanner(total: Int) {
        guard total > 0 else { return }
        currentBannerIndex = (currentBannerIndex + 1) % total
    }

    @ViewBuilder
    private func bannerBackground(_ banner: HomePresenter.State.Banner) -> some View {
        if let url = banner.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    bannerPlaceholder
                }
            }
        } else {
            bannerPlaceholder
        }
    }

    private var bannerPlaceholder: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.12, blue: 0.22),
                Color(red: 0.16, green: 0.30, blue: 0.56),
                Color(red: 0.34, green: 0.18, blue: 0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title2.weight(.bold))
    }

    private func placeholderPanel(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(panelBackground)
            .overlay(panelBorder)
    }

    private func messagePanel(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func shouldShowSearchSection(_ viewStore: ViewStore<HomePresenter.State, HomePresenter.Action>) -> Bool {
        !viewStore.trimmedHomeSearchQuery.isEmpty || viewStore.isSearching || viewStore.searchErrorMessage != nil
    }

    private func emptyScheduleMessage(_ viewStore: ViewStore<HomePresenter.State, HomePresenter.Action>) -> String {
        if !viewStore.trimmedSeasonFilterQuery.isEmpty {
            return "当前季度没有匹配“\(viewStore.trimmedSeasonFilterQuery)”的番剧。"
        }
        if viewStore.selectedScheduleDay == .all {
            return "当前季度没有可展示的番剧。"
        }
        return "\(viewStore.selectedScheduleDay.title) 暂无番剧。"
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color.white.opacity(0.12), lineWidth: 1)
    }
}

private struct HomePosterThumbnail: View {
    let url: URL?
    let title: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))

            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(title.prefix(1)))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

private struct ScheduleFilterField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor)

            TextField(
                placeholder,
                text: $text,
                prompt: Text(placeholder).foregroundColor(.secondary)
            )
            .textFieldStyle(.plain)
            .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(
                    color: Color.black.opacity(isFocused ? 0.08 : 0.06),
                    radius: isFocused ? 12 : 10,
                    y: isFocused ? 5 : 4
                )
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    isFocused ? Color.white.opacity(0.24) : Color.white.opacity(0.16),
                    lineWidth: 1
                )
        }
    }

    private var iconColor: Color {
        isFocused ? .primary.opacity(0.9) : .secondary
    }
}

private struct SeasonBangumiCard: View {
    let item: HomePresenter.State.BangumiItem

    var body: some View {
        BangumiPosterCard(title: item.title, imageURL: item.imageURL) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var subtitleText: String? {
        if let rating = item.rating, rating > 0 {
            return String(format: "评分 %.1f", rating)
        }
        if item.isOnAir {
            return "连载中"
        }
        return "尚未连载"
    }
}

private struct SearchResultCard: View {
    let item: HomePresenter.State.SearchResult

    var body: some View {
        BangumiPosterCard(title: item.title, imageURL: item.imageURL) {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let metadata = searchMetadata {
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var searchMetadata: String? {
        var parts: [String] = []
        if let typeDescription = item.typeDescription, !typeDescription.isEmpty {
            parts.append(typeDescription)
        }
        if let episodeCount = item.episodeCount, episodeCount > 0 {
            parts.append("\(episodeCount) 集")
        }
        if let rating = item.rating, rating > 0 {
            parts.append(String(format: "评分 %.1f", rating))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
