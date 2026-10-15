enum PlayerPlaybackMode: String, CaseIterable, Identifiable {
    case sequential
    case singleRepeat
    case listRepeat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential:
            return "顺序播放"
        case .singleRepeat:
            return "单集循环"
        case .listRepeat:
            return "列表循环"
        }
    }

    var description: String {
        switch self {
        case .sequential:
            return "播放完成后自动进入下一集，最后一集结束后停止"
        case .singleRepeat:
            return "当前集播放完成后从头重新播放"
        case .listRepeat:
            return "播放完成后自动进入下一集，最后一集结束后回到第一集"
        }
    }
}
