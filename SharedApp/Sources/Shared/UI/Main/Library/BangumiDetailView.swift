//
//  BangumiDetailView.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/10/19.
//

import SwiftUI
import Foundation
import ComposableArchitecture
import RemoteMediaLibrary
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct BangumiDetailView: View {
    let store: StoreOf<BangumiDetailPresenter>
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                content(for: viewStore)
                .navigationTitle(viewStore.summary.title)
                .task {
                    viewStore.send(.onAppear)
                }
            }
            .sheet(
                item: viewStore.binding(
                    get: \.fileSelection,
                    send: { _ in .fileSelectionDismissed }
                )
            ) { selection in

                FileSelectionView(
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
                backgroundLayer(for: viewStore.summary.coverURL)
                    .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        viewStore.send(.onAppear)
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func content(for viewStore: ViewStore<BangumiDetailPresenter.State, BangumiDetailPresenter.Action>) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            headerSection(for: viewStore.summary, detail: viewStore.detail)
            
            if viewStore.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载详情…")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if let error = viewStore.errorMessage {
                Text(error)
                    .foregroundColor(.secondary)
            } else if let detail = viewStore.detail {
                episodesSection(viewStore: viewStore, detail: detail)
            } else {
                Text("暂无可显示的详情。")
                    .foregroundColor(.secondary)
            }
        }
        .padding([.horizontal, .top])
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func headerSection(
        for item: LibraryPresenter.State.BangumiItem,
        detail: Components.Schemas.LibraryBangumiDetailsResponse?
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                coverView(url: item.coverURL)
                    .frame(width: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
                
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title)
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.leading)

                    if let details = item.details, !details.isEmpty {
                        Text(details)
                            .foregroundStyle(.secondary)
                    }

                    if let metadata = LibraryContentView.makeMetadataLine(for: item) {
                        Text(metadata)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let latestWatchedEpisode = detail?.episodes?.first(where: { $0.isLatestWatched == true }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最近观看到")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.6)
                            Text(bangumiEpisodeDisplayTitle(latestWatchedEpisode))
                                .font(.subheadline.weight(.semibold))
                            if let watchedDate = preferredLastWatchedDate(for: latestWatchedEpisode) {
                                Text(localizedBangumiDetailDateTime(watchedDate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                        )
                    }
                }
                Spacer(minLength: 0)
            }
            
            
        }
    }
    
    @ViewBuilder
    private func episodesSection(
        viewStore: ViewStore<BangumiDetailPresenter.State, BangumiDetailPresenter.Action>,
        detail: Components.Schemas.LibraryBangumiDetailsResponse
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("剧集列表")
                .font(.headline)
            
            if let episodes = detail.episodes, !episodes.isEmpty {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)
                    ],
                    spacing: 16
                ) {
                    ForEach(episodes, id: \.self) { episode in
                        EpisodeCard(episode: episode) {
                            viewStore.send(.episodeTapped(episode))
                        }.disabled(episode.localMatchedFiles?.isEmpty ?? true)
                    }
                }
            } else {
                Text("暂无剧集信息。")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func coverView(url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    coverPlaceholder
                case .empty:
                    ZStack {
                        coverPlaceholder
                        ProgressView()
                    }
                @unknown default:
                    coverPlaceholder
                }
            }
        } else {
            coverPlaceholder
        }
    }
    
    private var coverPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.12))
            Image(systemName: "rectangle.stack.badge.play")
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }
}

private struct EpisodeCard: View {
    let episode: Components.Schemas.LibraryBangumiEpisode
    let onTap: () -> Void
    @State private var isHovering = false

    private var isSelected: Bool {
        episode.isLatestWatched == true
    }

    private var isDisabled: Bool {
        episode.localMatchedFiles?.isEmpty ?? true
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .lineLimit(2...2)
                        .font(.headline)
                    if isSelected {
                        TagView(text: "最近观看")
                    }
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    if let watchedDate = preferredLastWatchedDate(for: episode) {
                        Label(
                            "上次观看 \(localizedBangumiDetailDateTime(watchedDate))",
                            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let airDate = episode.airDate {
                        Label {
                            Text(localizedBangumiDetailDate(airDate))
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    if let matched = episode.localMatchedExists {
                        Label(
                            matched ? "已匹配文件" : "无匹配文件",
                            systemImage: matched ? "checkmark.circle" : "exclamationmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(matched ? .green : .orange)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        isSelected
                        ? Color.accentColor.opacity(isDisabled ? 0.12 : 0.2)
                        : Color.platformBackground.opacity(isHovering ? 0.36 : 0.25)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected
                        ? Color.accentColor.opacity(isDisabled ? 0.4 : 0.7)
                        : Color.platformBackground.opacity(isHovering ? 0.5 : 0.25),
                        lineWidth: 1.2
                    )
            )
            .scaleEffect(isHovering && !isDisabled ? 1.01 : 1)
            .opacity(isDisabled ? 0.72 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .buttonStyle(.plain)
#if os(macOS)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
#endif
    }
    
    private var title: String {
        bangumiEpisodeDisplayTitle(episode)
    }
}

private struct TagView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.15))
            )
            .foregroundColor(.accentColor)
    }
}

private func localizedBangumiDetailDate(_ date: Date) -> String {
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

private func localizedBangumiDetailDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    if let preferredLanguage = Locale.preferredLanguages.first, !preferredLanguage.isEmpty {
        formatter.locale = Locale(identifier: preferredLanguage)
    } else {
        formatter.locale = .autoupdatingCurrent
    }
    formatter.calendar = .autoupdatingCurrent
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func preferredLastWatchedDate(
    for episode: Components.Schemas.LibraryBangumiEpisode
) -> Date? {
    episode.lastWatched ?? episode.lastWatchedCloud
}

private func bangumiEpisodeDisplayTitle(
    _ episode: Components.Schemas.LibraryBangumiEpisode
) -> String {
    if let episodeTitle = episode.episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
       !episodeTitle.isEmpty {
        return episodeTitle
    }
    if let displayTitle = episode.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
       !displayTitle.isEmpty {
        return displayTitle
    }
    if let number = episode.episodeNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
       !number.isEmpty {
        return "第\(number)话"
    }
    return "未命名剧集"
}

// MARK: - Helpers

private struct FileSelectionView: View {
    let selection: BangumiDetailPresenter.State.FileSelection
    let onSelect: (Components.Schemas.LibraryBangumiMatchedFile) -> Void
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
                                    .fill(Color.platformBackground.opacity(0.3))
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

@ViewBuilder
private func backgroundLayer(for url: URL?) -> some View {
    if let url {
        AsyncImage(url: url) { phase in 
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 120, opaque: true)
                    .overlay(Color.platformBackground.opacity(0.5))
                    .ignoresSafeArea()
            case .failure, .empty:
                Color.clear
            @unknown default:
                Color.clear
        }
    }
    } else {
        Color.clear
    }
}

private extension Color {
    static var platformBackground: Color {
#if os(macOS)
        Color(NSColor.windowBackgroundColor)
#elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        Color(UIColor.systemBackground)
#else
        Color(.white)
#endif
    }
}
