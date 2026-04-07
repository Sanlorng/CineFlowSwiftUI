import Foundation

public enum DanmakuCommentMode: Int, CaseIterable, Sendable {
    case scroll = 1
    case scrollAlt = 2
    case scrollBottom = 3
    case bottom = 4
    case top = 5
    case reverseScroll = 6
    case advanced = 7
    case code = 8
    case scripted = 9

    public var defaultLifetime: TimeInterval {
        switch self {
        case .bottom, .top:
            return 4
        case .scroll, .scrollAlt, .scrollBottom, .reverseScroll:
            return 12
        case .advanced:
            return 4
        case .code, .scripted:
            return 0
        }
    }

    public var isRenderable: Bool {
        switch self {
        case .scroll, .scrollAlt, .scrollBottom, .bottom, .top, .reverseScroll, .advanced:
            return true
        case .code, .scripted:
            return false
        }
    }
}

public struct DanmakuAdvancedPayload: Equatable, Sendable {
    public var rawJSON: String
    public var text: String?
    public var startX: Double?
    public var startY: Double?
    public var endX: Double?
    public var endY: Double?
    public var alphaFrom: Double?
    public var alphaTo: Double?
    public var lifetime: TimeInterval?

    public init(
        rawJSON: String,
        text: String? = nil,
        startX: Double? = nil,
        startY: Double? = nil,
        endX: Double? = nil,
        endY: Double? = nil,
        alphaFrom: Double? = nil,
        alphaTo: Double? = nil,
        lifetime: TimeInterval? = nil
    ) {
        self.rawJSON = rawJSON
        self.text = text
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.alphaFrom = alphaFrom
        self.alphaTo = alphaTo
        self.lifetime = lifetime
    }

    public static func parse(rawText: String) -> Self? {
        guard let data = rawText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let array = object as? [Any] {
            let extractedText = extractText(from: array)
            let alpha = parseAlpha(from: value(at: 2, in: array)) ?? parseAlpha(from: value(at: 6, in: array))
            return Self(
                rawJSON: rawText,
                text: extractedText,
                startX: number(from: value(at: 0, in: array)),
                startY: number(from: value(at: 1, in: array)),
                endX: number(from: value(at: 7, in: array)),
                endY: number(from: value(at: 8, in: array)),
                alphaFrom: alpha?.lowerBound,
                alphaTo: alpha?.upperBound,
                lifetime: timeInterval(from: value(at: 3, in: array))
            )
        }

        if let dictionary = object as? [String: Any] {
            let alphaFrom = number(from: dictionary["alphaFrom"]) ?? number(from: dictionary["fromAlpha"])
            let alphaTo = number(from: dictionary["alphaTo"]) ?? number(from: dictionary["toAlpha"]) ?? alphaFrom
            return Self(
                rawJSON: rawText,
                text: string(from: dictionary["text"]) ?? string(from: dictionary["content"]),
                startX: number(from: dictionary["x"]) ?? number(from: dictionary["startX"]),
                startY: number(from: dictionary["y"]) ?? number(from: dictionary["startY"]),
                endX: number(from: dictionary["toX"]) ?? number(from: dictionary["endX"]),
                endY: number(from: dictionary["toY"]) ?? number(from: dictionary["endY"]),
                alphaFrom: alphaFrom,
                alphaTo: alphaTo,
                lifetime: timeInterval(from: dictionary["duration"]) ?? timeInterval(from: dictionary["lifetime"])
            )
        }

        return nil
    }

    private static func value(at index: Int, in array: [Any]) -> Any? {
        guard array.indices.contains(index) else { return nil }
        return array[index]
    }

    private static func extractText(from array: [Any]) -> String? {
        if let candidate = string(from: value(at: 4, in: array)), candidate.isEmpty == false {
            return candidate
        }
        for value in array.reversed() {
            guard let candidate = string(from: value)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  candidate.isEmpty == false else {
                continue
            }
            if Double(candidate) == nil {
                return candidate
            }
        }
        return nil
    }

    private static func parseAlpha(from value: Any?) -> ClosedRange<Double>? {
        guard let string = string(from: value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              string.isEmpty == false else {
            return nil
        }

        if string.contains("-") {
            let parts = string.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let lower = Double(parts[0]),
                  let upper = Double(parts[1]) else {
                return nil
            }
            return lower...upper
        }

        guard let alpha = Double(string) else { return nil }
        return alpha...alpha
    }

    private static func number(from value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func timeInterval(from value: Any?) -> TimeInterval? {
        number(from: value)
    }

    private static func string(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}

public struct DanmakuComment: Equatable, Identifiable, Sendable {
    public let id: Int
    public let appearTime: TimeInterval
    public let mode: DanmakuCommentMode
    public let fontSize: Double
    public let colorRGB: UInt32
    public let text: String
    public let rawParameter: String
    public let advancedPayload: DanmakuAdvancedPayload?

    public init(
        id: Int,
        appearTime: TimeInterval,
        mode: DanmakuCommentMode,
        fontSize: Double,
        colorRGB: UInt32,
        text: String,
        rawParameter: String,
        advancedPayload: DanmakuAdvancedPayload? = nil
    ) {
        self.id = id
        self.appearTime = appearTime
        self.mode = mode
        self.fontSize = fontSize
        self.colorRGB = colorRGB
        self.text = text
        self.rawParameter = rawParameter
        self.advancedPayload = advancedPayload
    }

    public var visibilityWindow: TimeInterval {
        if let customLifetime = advancedPayload?.lifetime, customLifetime > 0 {
            return customLifetime
        }
        return mode.defaultLifetime
    }
}

public struct DanmakuDocument: Equatable, Sendable {
    public let comments: [DanmakuComment]
    public let maximumVisibilityWindow: TimeInterval

    public init(comments: [DanmakuComment]) {
        let sortedComments = comments.sorted { lhs, rhs in
            if lhs.appearTime != rhs.appearTime {
                return lhs.appearTime < rhs.appearTime
            }
            return lhs.id < rhs.id
        }
        self.comments = sortedComments
        self.maximumVisibilityWindow = sortedComments.map(\.visibilityWindow).max() ?? 0
    }

    public func comments(in timeRange: ClosedRange<TimeInterval>) -> ArraySlice<DanmakuComment> {
        guard comments.isEmpty == false else { return comments[0..<0] }
        let lower = lowerBound(for: max(timeRange.lowerBound, 0))
        let upper = upperBound(for: max(timeRange.upperBound, 0))
        return comments[lower..<upper]
    }

    public func lowerBound(for time: TimeInterval) -> Int {
        var lower = 0
        var upper = comments.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if comments[middle].appearTime < time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    public func upperBound(for time: TimeInterval) -> Int {
        var lower = 0
        var upper = comments.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if comments[middle].appearTime <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}
