//
//  HomeBangumiDetailView.swift
//  CineFlowPackage
//
//  Created by Codex on 2026/4/9.
//

import Foundation
import SwiftUI
import ComposableArchitecture
import RemoteMediaLibrary
#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
#endif

struct HomeBangumiDetailView: View {
    let store: StoreOf<HomeBangumiDetailPresenter>

    @State private var selectedEpisodePageIndex = 0
    @State private var isRatingPopoverPresented = false

    private let metadataColumns = [
        GridItem(.adaptive(minimum: 180), spacing: 10, alignment: .top)
    ]

    private let trailerColumns = [
        GridItem(.adaptive(minimum: 260), spacing: 14, alignment: .top)
    ]

    private let detailHorizontalPadding: CGFloat = 20
    private let detailVerticalPadding: CGFloat = 18
    private let detailColumnSpacing: CGFloat = 20
    private let detailSidebarWidth: CGFloat = 320
    private let detailMinMainColumnWidth: CGFloat = 620
    private let detailMaxMainColumnWidth: CGFloat = 960
    private let detailHeaderInlineBreakpoint: CGFloat = 760

    var body: some View {
        GeometryReader { geometry in
            WithViewStore(store, observe: { $0 }) { viewStore in
                detailLayout(
                    viewStore,
                    availableWidth: geometry.size.width,
                    availableHeight: geometry.size.height,
                    bottomSafeAreaInset: geometry.safeAreaInsets.bottom
                )
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .background {
                    blockingBackgroundLayer(for: viewStore.detail?.coverURL ?? viewStore.summary.imageURL)
                        .ignoresSafeArea()
                }
                .navigationTitle(viewStore.detail?.title ?? viewStore.summary.title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewStore.send(.refresh)
                        } label: {
                            Label("刷新详情", systemImage: "arrow.clockwise")
                        }
                        .disabled(viewStore.isLoading)
                    }
                }
                .onAppear {
                    viewStore.send(.onAppear)
                    syncEpisodePageSelection(with: viewStore.detail?.episodes ?? [])
                }
                .onChange(of: episodePageSelectionSeed(for: viewStore.detail?.episodes ?? [])) { _, _ in
                    syncEpisodePageSelection(with: viewStore.detail?.episodes ?? [])
                }
                .sheet(
                    item: viewStore.binding(
                        get: \.fileSelection,
                        send: { _ in .fileSelectionDismissed }
                    )
                ) { selection in
                    HomeDetailFileSelectionView(
                        selection: selection,
                        onSelect: { file in
                            viewStore.send(.fileSelected(file))
                        },
                        onCancel: {
                            viewStore.send(.fileSelectionDismissed)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func detailLayout(
        _ viewStore: ViewStore<HomeBangumiDetailPresenter.State, HomeBangumiDetailPresenter.Action>,
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        bottomSafeAreaInset: CGFloat
    ) -> some View {
        let maximumContentWidth = detailMaxMainColumnWidth + detailColumnSpacing + detailSidebarWidth
        let containerWidth = max(
            min(availableWidth - detailHorizontalPadding * 2, maximumContentWidth),
            0
        )
        let usesTwoColumnLayout = containerWidth >= detailMinMainColumnWidth + detailColumnSpacing + detailSidebarWidth
        let mainColumnWidth = usesTwoColumnLayout
            ? min(
                max(containerWidth - detailSidebarWidth - detailColumnSpacing, detailMinMainColumnWidth),
                detailMaxMainColumnWidth
            )
            : min(containerWidth, detailMaxMainColumnWidth)
        let contentWidth = usesTwoColumnLayout
            ? mainColumnWidth + detailColumnSpacing + detailSidebarWidth
            : mainColumnWidth
        let bottomPadding = max(bottomSafeAreaInset, 24)
        let sidebarHeight = max(
            availableHeight - detailVerticalPadding - bottomPadding,
            1
        )

        Group {
            if usesTwoColumnLayout {
                HStack(alignment: .top, spacing: detailColumnSpacing) {
                    ScrollView {
                        mainContent(
                            viewStore,
                            isCompactHeader: mainColumnWidth < detailHeaderInlineBreakpoint
                        )
                        .frame(width: mainColumnWidth, alignment: .leading)
                        .padding(.top, detailVerticalPadding)
                        .padding(.bottom, detailVerticalPadding + bottomPadding)
                    }
                    .frame(width: mainColumnWidth, height: availableHeight, alignment: .top)
                    .layoutPriority(1)

                    episodeSidebar(
                        viewStore,
                        availableHeight: sidebarHeight
                    )
                    .frame(width: detailSidebarWidth, alignment: .top)
                    .padding(.top, detailVerticalPadding)
                    .padding(.bottom, bottomPadding)
                }
                .frame(width: max(contentWidth, 0), alignment: .topLeading)
                .frame(height: availableHeight, alignment: .topLeading)
                .padding(.horizontal, detailHorizontalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: detailColumnSpacing) {
                        mainContent(
                            viewStore,
                            isCompactHeader: mainColumnWidth < detailHeaderInlineBreakpoint
                        )

                        episodeSidebar(viewStore)
                    }
                    .frame(width: max(contentWidth, 0), alignment: .topLeading)
                    .padding(.horizontal, detailHorizontalPadding)
                    .padding(.top, detailVerticalPadding)
                    .padding(.bottom, detailVerticalPadding + bottomPadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private func mainContent(
        _ viewStore: ViewStore<HomeBangumiDetailPresenter.State, HomeBangumiDetailPresenter.Action>,
        isCompactHeader: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            headerSection(viewStore, isCompact: isCompactHeader)

            if let error = viewStore.errorMessage, viewStore.detail != nil {
                messagePanel(title: "详情刷新失败", message: error)
            }

            if viewStore.isLoading && viewStore.detail == nil {
                loadingPanel
            } else if let error = viewStore.errorMessage, viewStore.detail == nil {
                messagePanel(title: "详情加载失败", message: error)
            } else if let detail = viewStore.detail {
                detailSections(detail)
            } else {
                pendingPanel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerSection(
        _ viewStore: ViewStore<HomeBangumiDetailPresenter.State, HomeBangumiDetailPresenter.Action>,
        isCompact: Bool
    ) -> some View {
        let detail = viewStore.detail
        let summary = viewStore.summary
        let title = detail?.title ?? summary.title
        let coverURL = detail?.coverURL ?? summary.imageURL

        return Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 20) {
                    coverView(url: coverURL, title: title)
                        .frame(width: 200)

                    headerSummary(
                        detail: detail,
                        summary: summary,
                        title: title
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 24) {
                    coverView(url: coverURL, title: title)
                        .frame(width: 190)

                    headerSummary(
                        detail: detail,
                        summary: summary,
                        title: title
                    )

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    @ViewBuilder
    private func headerSummary(
        detail: HomeBangumiDetailPresenter.State.Detail?,
        summary: HomeBangumiDetailPresenter.State.Summary,
        title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Text("作品编号 \(summary.requestIdentifier)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            badgeRow(detail: detail, summary: summary)

            if let featuredEpisode = featuredEpisode(in: detail?.episodes ?? []) {
                latestEpisodeSummary(featuredEpisode)
            }

            headerActionRow(detail: detail, summary: summary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func latestEpisodeSummary(
        _ episode: HomeBangumiDetailPresenter.State.Detail.Episode
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("最近播放")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            Text(episode.title)
                .font(.headline.weight(.semibold))
                .lineLimit(2)

            if let lastWatched = episode.lastWatched {
                Text(formattedDateTime(lastWatched))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let airDate = episode.airDate {
                Text("首播于 \(formattedDate(airDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func headerActionRow(
        detail: HomeBangumiDetailPresenter.State.Detail?,
        summary: HomeBangumiDetailPresenter.State.Summary
    ) -> some View {
        HStack(spacing: 10) {
            if let bangumiURL = detail?.bangumiURL {
                Link(destination: bangumiURL) {
                    detailActionLabel(title: "Bangumi.tv", systemImage: "safari")
                }
                .buttonStyle(.plain)
            }

            if let ratingTitle = ratingButtonTitle(detail: detail, summary: summary) {
                Button {
                    isRatingPopoverPresented.toggle()
                } label: {
                    detailActionLabel(title: ratingTitle, systemImage: "star.leadinghalf.filled")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isRatingPopoverPresented, arrowEdge: .bottom) {
                    ratingPopover(detail: detail, summary: summary)
                }
            }
        }
    }

    @ViewBuilder
    private func detailSections(
        _ detail: HomeBangumiDetailPresenter.State.Detail
    ) -> some View {
        let synopsis = synopsisParagraphs(for: detail)

        if !synopsis.isEmpty {
            synopsisSection(paragraphs: synopsis)
        }

        if !detail.tags.isEmpty {
            tagsSection(detail.tags)
        }

        if !detail.trailers.isEmpty {
            trailersSection(detail.trailers)
        }

        if let comment = detail.comment {
            textSection(title: "备注", text: comment)
        }

        let metadata = filteredMetadata(detail.metadata, aliases: detail.aliases)

        if !metadata.isEmpty {
            metadataSection(metadata)
        }

        if !detail.seasons.isEmpty {
            seasonsSection(detail.seasons)
        }

        if !detail.onlineDatabases.isEmpty {
            linksSection(title: "相关链接", links: detail.onlineDatabases)
        }

        if !detail.relateds.isEmpty {
            relatedSection(title: "关联作品", items: detail.relateds)
        }

        if !detail.similars.isEmpty {
            relatedSection(title: "相似作品", items: detail.similars)
        }
    }

    private func episodeSidebar(
        _ viewStore: ViewStore<HomeBangumiDetailPresenter.State, HomeBangumiDetailPresenter.Action>,
        availableHeight: CGFloat? = nil
    ) -> some View {
        let detail = viewStore.detail
        let episodes = detail?.episodes ?? []
        let featured = featuredEpisode(in: episodes)

        return Group {
            if let availableHeight {
                ViewThatFits(in: .vertical) {
                    episodeSidebarCard(
                        viewStore: viewStore,
                        detail: detail,
                        episodes: episodes,
                        featured: featured,
                        usesScrollableList: false
                    )

                    episodeSidebarCard(
                        viewStore: viewStore,
                        detail: detail,
                        episodes: episodes,
                        featured: featured,
                        usesScrollableList: true
                    )
                    .frame(height: availableHeight, alignment: .top)
                }
            } else {
                episodeSidebarCard(
                    viewStore: viewStore,
                    detail: detail,
                    episodes: episodes,
                    featured: featured,
                    usesScrollableList: false
                )
            }
        }
    }

    @ViewBuilder
    private func episodeSidebarCard(
        viewStore: ViewStore<HomeBangumiDetailPresenter.State, HomeBangumiDetailPresenter.Action>,
        detail: HomeBangumiDetailPresenter.State.Detail?,
        episodes: [HomeBangumiDetailPresenter.State.Detail.Episode],
        featured: HomeBangumiDetailPresenter.State.Detail.Episode?,
        usesScrollableList: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("剧集")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                Text(detail?.title ?? viewStore.summary.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                if let featured {
                    Text(featured.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.92))
                        .lineLimit(2)

                    if let lastWatched = featured.lastWatched {
                        Text("最近播放于 \(formattedDateTime(lastWatched))")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.85))
                    } else {
                        Text("已定位到最近播放剧集")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.85))
                    }
                } else {
                    Text("暂无最近播放记录")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.85))
                }

                Text("\(episodes.count) 集内容")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.85))
            }

            if !episodes.isEmpty {
                episodePagePicker(episodes: episodes)
            }

            if viewStore.isLoading && episodes.isEmpty {
                sidebarStatusView(
                    title: "正在加载",
                    message: "正在同步番剧详情和剧集记录。"
                )
            } else if let error = viewStore.errorMessage, episodes.isEmpty {
                sidebarStatusView(
                    title: "加载失败",
                    message: error
                )
            } else if episodes.isEmpty {
                sidebarStatusView(
                    title: "暂无剧集",
                    message: "当前番剧还没有可展示的剧集列表。"
                )
            } else {
                episodeSidebarEpisodeList(
                    viewStore: viewStore,
                    episodes: episodes,
                    featured: featured,
                    usesScrollableList: usesScrollableList
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: usesScrollableList ? .infinity : nil, alignment: .top)
        .padding(14)
        .background(sidebarBackground)
        .overlay(sidebarBorder)
        .shadow(color: .black.opacity(0.14), radius: 22, y: 10)
    }

    @ViewBuilder
    private func episodeSidebarEpisodeList(
        viewStore: ViewStore<HomeBangumiDetailPresenter.State, HomeBangumiDetailPresenter.Action>,
        episodes: [HomeBangumiDetailPresenter.State.Detail.Episode],
        featured: HomeBangumiDetailPresenter.State.Detail.Episode?,
        usesScrollableList: Bool
    ) -> some View {
        if usesScrollableList {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    episodeSidebarButtons(
                        viewStore: viewStore,
                        episodes: episodes,
                        featured: featured
                    )
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                episodeSidebarButtons(
                    viewStore: viewStore,
                    episodes: episodes,
                    featured: featured
                )
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private func episodeSidebarButtons(
        viewStore: ViewStore<HomeBangumiDetailPresenter.State, HomeBangumiDetailPresenter.Action>,
        episodes: [HomeBangumiDetailPresenter.State.Detail.Episode],
        featured: HomeBangumiDetailPresenter.State.Detail.Episode?
    ) -> some View {
        ForEach(displayedEpisodes(episodes)) { episode in
            Button {
                viewStore.send(.episodeTapped(episode))
            } label: {
                episodeSidebarRow(
                    episode: episode,
                    isSelected: featured?.id == episode.id
                )
            }
            .buttonStyle(.plain)
            .disabled(!episode.hasMatchedFile)
        }
    }

    @ViewBuilder
    private func episodePagePicker(
        episodes: [HomeBangumiDetailPresenter.State.Detail.Episode]
    ) -> some View {
        let pages = episodePages(itemCount: episodes.count)
        if pages.count > 1 {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 6) {
                    ForEach(pages) { page in
                        HomeDetailEpisodePageTag(
                            page: page,
                            isSelected: selectedEpisodePageIndex == page.index,
                            action: { selectedEpisodePageIndex = page.index }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func displayedEpisodes(
        _ episodes: [HomeBangumiDetailPresenter.State.Detail.Episode]
    ) -> [HomeBangumiDetailPresenter.State.Detail.Episode] {
        let pages = episodePages(itemCount: episodes.count)
        guard let page = pages.first(where: { $0.index == selectedEpisodePageIndex }) else {
            return episodes
        }
        return Array(episodes[page.range])
    }

    private func syncEpisodePageSelection(
        with episodes: [HomeBangumiDetailPresenter.State.Detail.Episode]
    ) {
        let pages = episodePages(itemCount: episodes.count)
        guard !pages.isEmpty else {
            selectedEpisodePageIndex = 0
            return
        }

        if let featured = featuredEpisode(in: episodes),
           let index = episodes.firstIndex(where: { $0.id == featured.id }) {
            selectedEpisodePageIndex = min(index / 25, pages.count - 1)
        } else if pages.indices.contains(selectedEpisodePageIndex) == false {
            selectedEpisodePageIndex = 0
        }
    }

    private func featuredEpisode(
        in episodes: [HomeBangumiDetailPresenter.State.Detail.Episode]
    ) -> HomeBangumiDetailPresenter.State.Detail.Episode? {
        if let latest = episodes.first(where: { $0.isLatestWatched }) {
            return latest
        }

        return episodes.max {
            ($0.lastWatched ?? .distantPast) < ($1.lastWatched ?? .distantPast)
        }
    }

    private func synopsisParagraphs(
        for detail: HomeBangumiDetailPresenter.State.Detail
    ) -> [String] {
        var paragraphs: [String] = []

        if let intro = detail.intro?.trimmingCharacters(in: .whitespacesAndNewlines), !intro.isEmpty {
            paragraphs.append(intro)
        }

        if let summary = detail.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty,
           paragraphs.contains(summary) == false {
            paragraphs.append(summary)
        }

        return paragraphs
    }

    private func filteredMetadata(
        _ metadata: [String],
        aliases: [HomeBangumiDetailPresenter.State.Detail.AlternativeTitle]
    ) -> [String] {
        let aliasTitles = Set(
            aliases
                .map(\.title)
                .map(normalizedMetadataToken(_:))
                .filter { !$0.isEmpty }
        )

        return metadata.filter { item in
            let normalizedItem = normalizedMetadataToken(item)
            guard !normalizedItem.isEmpty else { return false }
            guard normalizedItem.contains("别名") == false else { return false }
            guard normalizedItem.contains("别称") == false else { return false }
            return aliasTitles.contains { alias in
                normalizedItem.contains(alias)
            } == false
        }
    }

    private func normalizedMetadataToken(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "：", with: ":")
    }

    private func synopsisSection(paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("简介")

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func textSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func tagsSection(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("标签")

            HomeTagFlowLayout(spacing: 10, rowSpacing: 10) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func trailersSection(
        _ trailers: [HomeBangumiDetailPresenter.State.Detail.ExternalLink]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("预告片")

            LazyVGrid(columns: trailerColumns, spacing: 14) {
                ForEach(trailers) { trailer in
                    Link(destination: trailer.url) {
                        HomeTrailerCard(
                            trailer: trailer,
                            previewImageURL: trailerPreviewImageURL(for: trailer)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func metadataSection(_ metadata: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("资料")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(metadata, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)

                        Text(item)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func seasonsSection(
        _ seasons: [HomeBangumiDetailPresenter.State.Detail.SeasonInfo]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("季度")

            LazyVGrid(columns: metadataColumns, spacing: 10) {
                ForEach(seasons) { season in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(season.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        if let airDate = season.airDate {
                            Text(formattedDate(airDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let episodeCount = season.episodeCount {
                            Text("\(episodeCount) 集")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func linksSection(
        title: String,
        links: [HomeBangumiDetailPresenter.State.Detail.ExternalLink]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)

            LazyVGrid(columns: metadataColumns, spacing: 10) {
                ForEach(links) { link in
                    Link(destination: link.url) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(link.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                if let subtitle = link.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func relatedSection(
        title: String,
        items: [HomeBangumiDetailPresenter.State.Detail.RelatedBangumi]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        BangumiPosterCard(
                            title: item.title,
                            imageURL: item.imageURL,
                            width: 162
                        ) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2, reservesSpace: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(relatedSubtitle(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func ratingPopover(
        detail: HomeBangumiDetailPresenter.State.Detail?,
        summary: HomeBangumiDetailPresenter.State.Summary
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("评分明细")
                .font(.title3.weight(.bold))

            if let rating = detail?.rating ?? summary.rating, rating > 0 {
                ratingSummaryRow(title: "综合评分", value: formatRating(rating))
            }

            if let userRating = detail?.userRating {
                ratingSummaryRow(title: "我的评分", value: "\(userRating)")
            }

            if let detail, !detail.siteRatings.isEmpty {
                Divider()

                LazyVGrid(columns: metadataColumns, spacing: 10) {
                    ForEach(detail.siteRatings) { rating in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rating.source)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(formatRating(rating.value))
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
            } else {
                Text("暂无站点评分明细。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
        .background(Color.detailBackgroundBase.opacity(0.96))
    }

    private func ratingSummaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.headline.weight(.bold))
        }
        .padding(.vertical, 2)
    }

    private func sidebarStatusView(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func episodeSidebarRow(
        episode: HomeBangumiDetailPresenter.State.Detail.Episode,
        isSelected: Bool
    ) -> some View {
        HomeEpisodeSidebarRow(episode: episode, isSelected: isSelected)
    }

    private func badgeRow(
        detail: HomeBangumiDetailPresenter.State.Detail?,
        summary: HomeBangumiDetailPresenter.State.Summary
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(headerBadges(detail: detail, summary: summary), id: \.self) { badge in
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func headerBadges(
        detail: HomeBangumiDetailPresenter.State.Detail?,
        summary: HomeBangumiDetailPresenter.State.Summary
    ) -> [String] {
        var badges: [String] = []

        if let typeDescription = detail?.typeDescription ?? summary.typeDescription {
            badges.append(typeDescription)
        }
        if let favoriteStatus = detail?.favoriteStatus {
            badges.append(favoriteStatus)
        } else if summary.isFavorited {
            badges.append("已关注")
        }
        if let detail, !detail.episodes.isEmpty {
            badges.append("\(detail.episodes.count) 集")
        }
        if let detail, detail.seasons.count > 1 {
            badges.append("\(detail.seasons.count) 季")
        }

        return badges
    }

    private func ratingButtonTitle(
        detail: HomeBangumiDetailPresenter.State.Detail?,
        summary: HomeBangumiDetailPresenter.State.Summary
    ) -> String? {
        if let rating = detail?.rating ?? summary.rating, rating > 0 {
            return "评分 \(formatRating(rating))"
        }

        if detail?.userRating != nil || detail?.siteRatings.isEmpty == false {
            return "评分"
        }

        return nil
    }

    private func relatedSubtitle(
        for item: HomeBangumiDetailPresenter.State.Detail.RelatedBangumi
    ) -> String {
        if let rating = item.rating, rating > 0 {
            return "评分 \(formatRating(rating))"
        }
        if item.isOnAir {
            return "连载中"
        }
        return "尚未连载"
    }

    @ViewBuilder
    private func coverView(url: URL?, title: String) -> some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))

                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        case .empty:
                            ProgressView()
                        default:
                            coverPlaceholder(title: title)
                        }
                    }
                } else {
                    coverPlaceholder(title: title)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func coverPlaceholder(title: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.secondary.opacity(0.18),
                    Color.secondary.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(String(title.prefix(1)))
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func detailActionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
    }

    private var loadingPanel: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在加载番剧详情…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private var pendingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("正在准备详情…")
                .font(.headline)
            Text("详情主体来自弹弹 API，最近播放记录会在可用时合并进来。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
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
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.ultraThinMaterial)
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(Color.white.opacity(0.12), lineWidth: 1)
    }

    private var sidebarBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var sidebarBorder: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
    }

    @ViewBuilder
    private func blockingBackgroundLayer(for coverURL: URL?) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.detailBackgroundBase

                if let coverURL {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .saturation(0.8)
                                .blur(radius: 36)
                                .opacity(0.42)
                        default:
                            fallbackBackground
                        }
                    }
                } else {
                    fallbackBackground
                }

                LinearGradient(
                    colors: [
                        Color.detailBackgroundBase.opacity(0.24),
                        Color.detailBackgroundBase.opacity(0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }

    private var fallbackBackground: some View {
        LinearGradient(
            colors: [
                Color.secondary.opacity(0.14),
                Color.clear,
                Color.secondary.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func formatRating(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func formattedDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func trailerPreviewImageURL(
        for trailer: HomeBangumiDetailPresenter.State.Detail.ExternalLink
    ) -> URL? {
        if let imageURL = trailer.imageURL {
            return imageURL
        }
        return inferredYouTubeThumbnailURL(from: trailer.url)
    }

    private func inferredYouTubeThumbnailURL(from url: URL) -> URL? {
        guard let host = url.host()?.lowercased() else { return nil }

        let videoID: String?
        if host.contains("youtu.be") {
            videoID = url.pathComponents.dropFirst().first
        } else if host.contains("youtube.com") {
            if url.path == "/watch" {
                videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "v" })?
                    .value
            } else if url.path.hasPrefix("/shorts/") {
                videoID = url.pathComponents.dropFirst(2).first
            } else {
                videoID = nil
            }
        } else {
            videoID = nil
        }

        guard let videoID, !videoID.isEmpty else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }
}

private struct HomeEpisodeSidebarRow: View {
    let episode: HomeBangumiDetailPresenter.State.Detail.Episode
    let isSelected: Bool
    @State private var isHovering = false

    private var isDisabled: Bool {
        !episode.hasMatchedFile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(episode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if isSelected {
                    recentTag
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                if let number = episode.number, !number.isEmpty {
                    Label("第\(number)话", systemImage: "textformat.123")
                        .lineLimit(1)
                }

                if let airDate = episode.airDate {
                    Label(formattedDate(airDate), systemImage: "calendar")
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Label(
                episode.hasMatchedFile ? "已匹配文件" : "无匹配文件",
                systemImage: episode.hasMatchedFile ? "checkmark.circle" : "exclamationmark.circle"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let lastWatched = episode.lastWatched {
                Label(
                    "上次观看 \(formattedDateTime(lastWatched))",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .scaleEffect(isHovering && !isSelected && !isDisabled ? 1.01 : 1)
        .opacity(isDisabled ? 0.72 : 1)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
#if os(macOS)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
#endif
    }

    private var backgroundFill: LinearGradient {
        if isSelected {
            return LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.24),
                    Color.accentColor.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(isHovering ? 0.24 : 0.1),
                Color.white.opacity(isHovering ? 0.14 : 0.04)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.55)
        }
        return Color.white.opacity(isHovering ? 0.28 : 0.08)
    }

    private var recentTag: some View {
        Text("最近播放")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
            )
            .foregroundStyle(Color.accentColor)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func formattedDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct HomeDetailEpisodePageTag: View {
    let page: HomeDetailEpisodePage
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(page.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isSelected
                            ? Color.white.opacity(0.18)
                            : Color.white.opacity(isHovering ? 0.08 : 0.02)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected
                            ? Color.white.opacity(0.16)
                            : Color.white.opacity(isHovering ? 0.1 : 0.04),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
#if os(macOS)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
#endif
    }
}

private struct HomeDetailEpisodePage: Identifiable, Equatable {
    let index: Int
    let range: Range<Int>
    let title: String

    var id: Int { index }
}

private func episodePages(itemCount: Int) -> [HomeDetailEpisodePage] {
    guard itemCount > 0 else { return [] }
    let pageSize = 25
    let starts = stride(from: 0, to: itemCount, by: pageSize)
    return starts.enumerated().map { pageIndex, start in
        let end = min(start + pageSize, itemCount)
        return HomeDetailEpisodePage(
            index: pageIndex,
            range: start..<end,
            title: "\(start + 1)-\(end)"
        )
    }
}

private func episodePageSelectionSeed(
    for episodes: [HomeBangumiDetailPresenter.State.Detail.Episode]
) -> String {
    let latestEpisodeID = episodes.first(where: { $0.isLatestWatched })?.id ?? "none"
    return "\(episodes.count)-\(latestEpisodeID)"
}

private struct HomeTagFlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = arrangedRows(maxWidth: maxWidth, subviews: subviews)

        let height = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + row.height
        } + max(CGFloat(rows.count - 1), 0) * rowSpacing

        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = arrangedRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX

            for element in row.elements {
                let size = element.size
                element.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + spacing
            }

            y += row.height + rowSpacing
        }
    }

    private func arrangedRows(
        maxWidth: CGFloat,
        subviews: Subviews
    ) -> [FlowRow] {
        guard !subviews.isEmpty else { return [] }

        let availableWidth = max(maxWidth, 1)
        var rows: [FlowRow] = []
        var currentRow = FlowRow()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = currentRow.elements.isEmpty
                ? size.width
                : currentRow.width + spacing + size.width

            if proposedWidth > availableWidth, currentRow.elements.isEmpty == false {
                rows.append(currentRow)
                currentRow = FlowRow()
            }

            currentRow.add(subview: subview, size: size, spacing: currentRow.elements.isEmpty ? 0 : spacing)
        }

        rows.append(currentRow)
        return rows
    }

    private struct FlowRow {
        var elements: [FlowElement] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func add(
            subview: LayoutSubview,
            size: CGSize,
            spacing: CGFloat
        ) {
            elements.append(.init(subview: subview, size: size))
            width += size.width + spacing
            height = max(height, size.height)
        }
    }

    private struct FlowElement {
        let subview: LayoutSubview
        let size: CGSize
    }
}

private struct HomeTrailerCard: View {
    let trailer: HomeBangumiDetailPresenter.State.Detail.ExternalLink
    let previewImageURL: URL?
    @State private var isHovering = false

    private var previewBorderColor: Color {
        isHovering ? Color.white.opacity(0.2) : Color.white.opacity(0.08)
    }

    private var cardBackgroundColor: Color {
        Color.white.opacity(isHovering ? 0.12 : 0.07)
    }

    private var cardBorderColor: Color {
        isHovering ? Color.white.opacity(0.18) : Color.white.opacity(0.08)
    }

    private var cardShadowColor: Color {
        isHovering ? Color.black.opacity(0.22) : .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                previewImage

                LinearGradient(
                    colors: [
                        Color.black.opacity(isHovering ? 0.02 : 0.08),
                        Color.black.opacity(isHovering ? 0.68 : 0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(alignment: .center) {
                    Label("PV", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.28), in: Capsule(style: .continuous))

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                        .scaleEffect(isHovering ? 1.08 : 1)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(previewBorderColor, lineWidth: 1.2)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(trailer.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Text(trailer.url.host() ?? trailer.subtitle ?? "预告片")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
        .shadow(
            color: cardShadowColor,
            radius: isHovering ? 24 : 0,
            y: isHovering ? 12 : 0
        )
        .scaleEffect(isHovering ? 1.015 : 1)
#if os(macOS)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
#endif
    }

    @ViewBuilder
    private var previewImage: some View {
        if let previewImageURL {
            AsyncImage(url: previewImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(isHovering ? 1.04 : 1)
                case .empty:
                    placeholderImage
                        .overlay(ProgressView())
                default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.26),
                    Color.secondary.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

private struct HomeDetailFileSelectionView: View {
    let selection: HomeBangumiDetailPresenter.State.FileSelection
    let onSelect: (RemoteMediaLibrary.Components.Schemas.LibraryBangumiMatchedFile) -> Void
    let onCancel: () -> Void

    private let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("选择播放文件")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", action: onCancel)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if selection.files.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.square.dashed")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("没有可用的匹配文件")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(selection.files.enumerated()), id: \.offset) { _, file in
                        Button {
                            onSelect(file)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.name ?? "未知文件")
                                    .font(.headline)
                                if let size = file.size {
                                    Text(formatter.string(fromByteCount: size))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let path = file.dirPath {
                                    Text(path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .padding(.horizontal)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.detailBackgroundBase.opacity(0.14))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

private extension Color {
    static var detailBackgroundBase: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        Color(uiColor: .systemBackground)
#else
        Color.black
#endif
    }
}
