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
            SharedContentView()
        }.windowStyle(.hiddenTitleBar)
    }
}
