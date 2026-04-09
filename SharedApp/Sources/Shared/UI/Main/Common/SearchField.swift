//
//  SearchField.swift
//  CineFlowPackage
//
//  Created by Codex on 2026/4/9.
//

import SwiftUI

struct AdaptiveToolbarSearchField: View {
    @Binding var query: String
    let placeholder: String
    var helpText: String? = nil

    @State private var isPopoverPresented = false
    @Environment(\.appearsActive) private var appearsActive
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
                isFocused: isInlineFieldFocused && appearsActive
            )
            .frame(
                minWidth: minimumExpandedWidth,
                idealWidth: idealExpandedWidth,
                maxWidth: maximumExpandedWidth
            )

            collapsedSearchButton
        }
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
        .help(helpText ?? placeholder)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            searchField(
                focused: $isPopoverFieldFocused,
                isFocused: isPopoverFieldFocused && appearsActive
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
                placeholder,
                text: $query,
                prompt: Text(placeholder).foregroundColor(searchPromptAndIconColor)
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
        appearsActive ? (query.isEmpty ? .primary : .accentColor) : searchPromptAndIconColor
    }

    private var searchPromptAndIconColor: Color {
        appearsActive ? .secondary : Color.secondary.opacity(0.7)
    }

    private var searchTextColor: Color {
        appearsActive ? .primary : .secondary
    }
}
