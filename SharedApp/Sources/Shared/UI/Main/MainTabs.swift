//
//  File.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/9/28.
//

import Foundation

enum MainTabs: Equatable, Hashable, Identifiable {
    case Home
    case Library
    case Player
    
    var id: Self {
        return self
    }
}
