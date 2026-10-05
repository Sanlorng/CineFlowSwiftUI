//
//  BangumiPosterCard.swift
//  CineFlowPackage
//
//  Created by Codex on 2026/4/9.
//

import SwiftUI

struct BangumiPosterCard<Content: View>: View {
    let title: String
    let imageURL: URL?
    let width: CGFloat?
    let content: () -> Content

    private let cardPadding: CGFloat = 12
    private let coverCornerRadius: CGFloat = 14
    private let coverAspectRatio: CGFloat = 2 / 3

    init(
        title: String,
        imageURL: URL?,
        width: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.imageURL = imageURL
        self.width = width
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            coverContainer

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(cardPadding)
        .frame(width: width, alignment: .topLeading)
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    private var coverContainer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: coverCornerRadius)
                .fill(Color.secondary.opacity(0.08))
            coverView
        }
        .aspectRatio(coverAspectRatio, contentMode: .fit)
        .modifier(OptionalWidthFrame(width: coverWidth))
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: coverCornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: coverCornerRadius))
    }

    @ViewBuilder
    private var coverView: some View {
        GeometryReader { geometry in
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height,
                                alignment: .center
                            )
                            .clipped()
                    case .failure:
                        placeholder
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    case .empty:
                        ZStack {
                            placeholder
                            ProgressView()
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    @unknown default:
                        placeholder
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            } else {
                placeholder
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let initial = title.first {
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

    private var coverWidth: CGFloat? {
        guard let width else { return nil }
        return max(width - (cardPadding * 2), 0)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.regularMaterial)
            .cineFlowCardInteractionTint()
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                Color.primary.opacity(0.08),
                lineWidth: 1
            )
    }

}

private struct OptionalWidthFrame: ViewModifier {
    let width: CGFloat?

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width)
        } else {
            content
        }
    }
}
