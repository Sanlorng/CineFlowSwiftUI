//
//  BangumiDetailView.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/10/19.
//

import SwiftUI
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
            headerSection(for: viewStore.summary)
            
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
                episodesSection(detail: detail)
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
    private func headerSection(for item: LibraryPresenter.State.BangumiItem) -> some View {
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
                }
                Spacer(minLength: 0)
            }
            
            
        }
    }
    
    @ViewBuilder
    private func episodesSection(detail: Components.Schemas.LibraryBangumiDetailsResponse) -> some View {
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
                        EpisodeCard(episode: episode)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                .lineLimit(2...2)
                    .font(.headline)
                if episode.isLatestWatched == true {
                    TagView(text: "最近观看")
                }
                Spacer()
            }
            
            HStack(spacing: 12) {
                if let airDate = episode.airDate {
                    Label {
                        Text(airDate, style: .date)
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                if let matched = episode.localMatchedExists {
                    Label(matched ? "已匹配文件" : "无匹配文件", systemImage: matched ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(matched ? .green : .orange)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.platformBackground.opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.platformBackground.opacity(0.25), lineWidth: 1)
        )
    }
    
    private var title: String {
        var components: [String] = []
        if let number = episode.episodeNumber, !number.isEmpty {
            components.append("#\(number)")
        }
        if let episodeTitle = episode.episodeTitle, !episodeTitle.isEmpty {
            components.append(episodeTitle)
        }
        else if let displayTitle = episode.displayTitle, !displayTitle.isEmpty {
            components.append(displayTitle)
        }
        return components.isEmpty ? "未命名剧集" : components.joined(separator: " ")
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

// MARK: - Helpers

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
