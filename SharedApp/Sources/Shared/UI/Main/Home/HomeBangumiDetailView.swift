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

struct HomeBangumiDetailView: View {
    let store: StoreOf<HomeBangumiDetailPresenter>

    private let pillColumns = [
        GridItem(.adaptive(minimum: 120, maximum: 220), spacing: 10, alignment: .top)
    ]

    private let episodeColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14, alignment: .top)
    ]

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection(viewStore)

                    if let error = viewStore.errorMessage, viewStore.detail != nil {
                        messagePanel(title: "详情刷新失败", message: error)
                    }

                    if viewStore.isLoading && viewStore.detail == nil {
                        loadingPanel
                    } else if let error = viewStore.errorMessage, viewStore.detail == nil {
                        messagePanel(title: "详情加载失败", message: error)
                    } else if let detail = viewStore.detail {
                        detailSections(viewStore, detail)
                    } else {
                        pendingPanel
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            .background {
                backgroundLayer(for: viewStore.detail?.coverURL ?? viewStore.summary.imageURL)
                    .ignoresSafeArea()
            }
        }
    }

    private func headerSection(
        _ viewStore: ViewStore<HomeBangumiDetailPresenter.State, HomeBangumiDetailPresenter.Action>
    ) -> some View {
        let detail = viewStore.detail
        let summary = viewStore.summary
        let title = detail?.title ?? summary.title
        let coverURL = detail?.coverURL ?? summary.imageURL

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                coverView(url: coverURL, title: title)
                    .frame(width: 176)

                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text("作品编号 \(summary.requestIdentifier)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    badgeRow(detail: detail, summary: summary)

                    if let overview = overviewSnippet(detail: detail) {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let latestTitle = detail?.latestWatchedEpisodeTitle,
                       let latestWatchedAt = detail?.latestWatchedAt {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最近观看到")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(latestTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(formattedDateTime(latestWatchedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 10) {
                        if let bangumiURL = detail?.bangumiURL {
                            Link(destination: bangumiURL) {
                                detailActionLabel(title: "Bangumi.tv", systemImage: "safari")
                            }
                            .buttonStyle(.plain)
                        }

                        if let trailer = detail?.trailers.first {
                            Link(destination: trailer.url) {
                                detailActionLabel(title: "预告片", systemImage: "play.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(24)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    @ViewBuilder
    private func detailSections(
        _ viewStore: ViewStore<HomeBangumiDetailPresenter.State, HomeBangumiDetailPresenter.Action>,
        _ detail: HomeBangumiDetailPresenter.State.Detail
    ) -> some View {
        if let summary = detail.summary {
            textSection(title: "简介", text: summary)
        }

        if let intro = detail.intro, intro != detail.summary {
            textSection(title: "补充简介", text: intro)
        }

        if let comment = detail.comment {
            textSection(title: "备注", text: comment)
        }

        if !detail.aliases.isEmpty {
            pillsSection(
                title: "别名",
                pills: detail.aliases.map { alias in
                    if let language = alias.language {
                        return "\(language) · \(alias.title)"
                    }
                    return alias.title
                }
            )
        }

        if !detail.metadata.isEmpty {
            metadataSection(detail.metadata)
        }

        if !detail.siteRatings.isEmpty {
            siteRatingsSection(detail.siteRatings)
        }

        if !detail.tags.isEmpty {
            pillsSection(title: "标签", pills: detail.tags)
        }

        if !detail.seasons.isEmpty {
            seasonsSection(detail.seasons)
        }

        if !detail.episodes.isEmpty {
            episodesSection(viewStore, detail.episodes)
        }

        if !detail.onlineDatabases.isEmpty {
            linksSection(title: "相关链接", links: detail.onlineDatabases)
        }

        if !detail.trailers.isEmpty {
            linksSection(title: "预告片", links: detail.trailers)
        }

        if !detail.relateds.isEmpty {
            relatedSection(title: "关联作品", items: detail.relateds)
        }

        if !detail.similars.isEmpty {
            relatedSection(title: "相似作品", items: detail.similars)
        }
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
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func metadataSection(_ metadata: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("资料")

            VStack(alignment: .leading, spacing: 10) {
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
                }
            }
            .textSelection(.enabled)
        }
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func siteRatingsSection(
        _ ratings: [HomeBangumiDetailPresenter.State.Detail.SiteRating]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("站点评分")

            LazyVGrid(columns: pillColumns, spacing: 10) {
                ForEach(ratings) { rating in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rating.source)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(formatRating(rating.value))
                            .font(.headline.weight(.bold))
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
        }
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func pillsSection(title: String, pills: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)

            LazyVGrid(columns: pillColumns, spacing: 10) {
                ForEach(pills, id: \.self) { pill in
                    Text(pill)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
            }
        }
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func seasonsSection(
        _ seasons: [HomeBangumiDetailPresenter.State.Detail.SeasonInfo]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("季度")

            LazyVGrid(columns: pillColumns, spacing: 10) {
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
        }
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func episodesSection(
        _ viewStore: ViewStore<HomeBangumiDetailPresenter.State, HomeBangumiDetailPresenter.Action>,
        _ episodes: [HomeBangumiDetailPresenter.State.Detail.Episode]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("剧集列表")

            LazyVGrid(columns: episodeColumns, spacing: 14) {
                ForEach(episodes) { episode in
                    Button {
                        viewStore.send(.episodeTapped(episode))
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(episode.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                if episode.isLatestWatched {
                                    detailTagView(text: "最近观看")
                                }
                                Spacer(minLength: 0)
                            }

                            HStack(spacing: 12) {
                                if let airDate = episode.airDate {
                                    Label {
                                        Text(formattedDate(airDate))
                                    } icon: {
                                        Image(systemName: "calendar")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Label(
                                    episode.hasMatchedFile ? "已匹配文件" : "无匹配文件",
                                    systemImage: episode.hasMatchedFile ? "checkmark.circle" : "exclamationmark.circle"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            if let lastWatched = episode.lastWatched {
                                Label(
                                    "上次观看 \(formattedDateTime(lastWatched))",
                                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            } else {
                                Label(
                                    "无远程播放记录",
                                    systemImage: "clock.badge.questionmark"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    episode.isLatestWatched
                                        ? Color.accentColor.opacity(episode.hasMatchedFile ? 0.18 : 0.12)
                                        : Color.secondary.opacity(0.08)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    episode.isLatestWatched
                                        ? Color.accentColor.opacity(episode.hasMatchedFile ? 0.55 : 0.32)
                                        : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!episode.hasMatchedFile)
                }
            }
        }
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

            LazyVGrid(columns: pillColumns, spacing: 10) {
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
        }
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

            ScrollView(.horizontal, showsIndicators: false) {
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
        }
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
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
        if let rating = detail?.rating ?? summary.rating, rating > 0 {
            badges.append("综合 \(formatRating(rating))")
        }
        if let userRating = detail?.userRating {
            badges.append("我的评分 \(userRating)")
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

    private func overviewSnippet(
        detail: HomeBangumiDetailPresenter.State.Detail?
    ) -> String? {
        detail?.summary ?? detail?.intro ?? detail?.comment
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

    private func detailTagView(text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
            )
            .foregroundStyle(Color.accentColor)
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
            Text("详情主体会直接来自弹弹 API，播放记录后续只做附加合并。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(panelBackground)
        .overlay(panelBorder)
        .onAppear {
            ViewStore(store, observe: { $0.isLoading }).send(.onAppear)
        }
    }

    private func placeholderPanel(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func backgroundLayer(for coverURL: URL?) -> some View {
        if let coverURL {
            AsyncImage(url: coverURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .saturation(0.8)
                        .blur(radius: 34)
                        .overlay(Color.black.opacity(0.22))
                default:
                    fallbackBackground
                }
            }
        } else {
            fallbackBackground
        }
    }

    private var fallbackBackground: some View {
        LinearGradient(
            colors: [
                Color.secondary.opacity(0.16),
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
                                    .fill(Color.secondary.opacity(0.12))
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
