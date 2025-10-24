//
//  CineFlowApp.swift
//  CineFlow
//
//  Created by sanlorng char on 2025/9/21.
//

import SwiftUI
import Shared

@main
struct CineFlowApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                VisualEffectView()
                    .ignoresSafeArea()
                SharedContentView()
            }
            .frame(minWidth: 400, minHeight: 400)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct VisualEffectView: NSViewRepresentable {
    // 定义模糊的材质和混合模式
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        // 设置为 active 状态，使其一直保持模糊效果
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // 当 SwiftUI 视图更新时，同步更新 NSView 的属性
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
