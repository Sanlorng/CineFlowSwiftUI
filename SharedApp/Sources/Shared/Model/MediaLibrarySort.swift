import Foundation

enum MediaLibrarySort: String, CaseIterable, Equatable, Sendable {
    case lastPlay
    case lastUpdate
    case lastAdd
    case season
    case name
    case category
    case rating

    var displayName: String {
        switch self {
        case .lastPlay: return "最近播放"
        case .lastUpdate: return "最近更新"
        case .lastAdd: return "最近关注"
        case .season: return "季度番剧"
        case .name: return "按名称"
        case .category: return "按分类"
        case .rating: return "按评分"
        }
    }
}
