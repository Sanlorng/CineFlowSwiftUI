//
//  CineFlowApp.swift
//  CineFlow
//
//  Created by sanlorng char on 2025/9/21.
//

import SwiftUI
import Shared
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@main
struct CineFlowApp: App {
    var body: some Scene {
        mainWindowScene
#if os(macOS)
        Settings {
            SharedSettingsView()
        }
#endif
    }

    private var mainWindowScene: some Scene {
        WindowGroup {
            ZStack {
                HostBackgroundView()
                    .ignoresSafeArea()
                SharedContentView()
            }
#if os(macOS)
            .frame(minWidth: 400, minHeight: 400)
#endif
        }
#if os(macOS)
        .windowStyle(.hiddenTitleBar)
#endif
    }
}

private struct HostBackgroundView: View {
    var body: some View {
#if os(macOS)
        VisualEffectView()
#else
        Color(uiColor: .systemBackground)
#endif
    }
}

#if os(macOS)
private struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#endif
