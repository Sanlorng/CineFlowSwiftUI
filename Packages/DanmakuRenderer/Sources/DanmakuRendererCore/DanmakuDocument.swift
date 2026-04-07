import CoreGraphics
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

public enum DanmakuMotionCurve: String, CaseIterable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    package func value(at progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        switch self {
        case .linear:
            return clamped
        case .easeIn:
            return clamped * clamped
        case .easeOut:
            return 1 - pow(1 - clamped, 2)
        case .easeInOut:
            if clamped < 0.5 {
                return 2 * clamped * clamped
            }
            return 1 - pow(-2 * clamped + 2, 2) / 2
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
    public var translationDuration: TimeInterval?
    public var translationDelay: TimeInterval
    public var rotationZ: Double?
    public var endRotationZ: Double?
    public var rotationY: Double?
    public var fontFamily: String?
    public var usesStroke: Bool?
    public var motionCurve: DanmakuMotionCurve
    public var path: [CGPoint]?

    public init(
        rawJSON: String,
        text: String? = nil,
        startX: Double? = nil,
        startY: Double? = nil,
        endX: Double? = nil,
        endY: Double? = nil,
        alphaFrom: Double? = nil,
        alphaTo: Double? = nil,
        lifetime: TimeInterval? = nil,
        translationDuration: TimeInterval? = nil,
        translationDelay: TimeInterval = 0,
        rotationZ: Double? = nil,
        endRotationZ: Double? = nil,
        rotationY: Double? = nil,
        fontFamily: String? = nil,
        usesStroke: Bool? = nil,
        motionCurve: DanmakuMotionCurve = .linear,
        path: [CGPoint]? = nil
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
        self.translationDuration = translationDuration
        self.translationDelay = translationDelay
        self.rotationZ = rotationZ
        self.endRotationZ = endRotationZ
        self.rotationY = rotationY
        self.fontFamily = fontFamily
        self.usesStroke = usesStroke
        self.motionCurve = motionCurve
        self.path = path
    }

    public var totalLifetime: TimeInterval? {
        let baseLifetime = lifetime ?? 0
        let motionLifetime = translationDelay + max(translationDuration ?? 0, 0)
        let resolved = max(baseLifetime, motionLifetime)
        return resolved > 0 ? resolved : nil
    }

    public static func parse(rawText: String) -> Self? {
        guard let data = rawText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let array = object as? [Any] {
            let alpha = parseAlpha(from: value(at: 2, in: array))
            var path = pathPoints(from: value(at: 14, in: array))
            let startPoint = point(x: value(at: 0, in: array), y: value(at: 1, in: array))
            let endPoint = point(x: value(at: 7, in: array), y: value(at: 8, in: array))
            normalizePath(&path, startPoint: startPoint, endPoint: endPoint)

            return Self(
                rawJSON: rawText,
                text: extractText(from: array),
                startX: startPoint.map { Double($0.x) },
                startY: startPoint.map { Double($0.y) },
                endX: endPoint.map { Double($0.x) } ?? path?.last.map { Double($0.x) },
                endY: endPoint.map { Double($0.y) } ?? path?.last.map { Double($0.y) },
                alphaFrom: alpha?.lowerBound,
                alphaTo: alpha?.upperBound,
                lifetime: timeInterval(from: value(at: 3, in: array)),
                translationDuration: timeInterval(from: value(at: 9, in: array)),
                translationDelay: timeInterval(from: value(at: 10, in: array)) ?? 0,
                rotationZ: number(from: value(at: 5, in: array)),
                endRotationZ: nil,
                rotationY: number(from: value(at: 6, in: array)),
                fontFamily: fontFamily(from: value(at: 12, in: array)),
                usesStroke: bool(from: value(at: 11, in: array)),
                motionCurve: curve(from: value(at: 13, in: array)) ?? .linear,
                path: path
            )
        }

        if let dictionary = object as? [String: Any] {
            let alphaFrom = number(from: dictionary["alphaFrom"]) ?? number(from: dictionary["fromAlpha"])
            let alphaTo = number(from: dictionary["alphaTo"]) ?? number(from: dictionary["toAlpha"]) ?? alphaFrom
            let startPoint = point(x: dictionary["x"] ?? dictionary["startX"], y: dictionary["y"] ?? dictionary["startY"])
            let endPoint = point(x: dictionary["toX"] ?? dictionary["endX"], y: dictionary["toY"] ?? dictionary["endY"])
            var path = pathPoints(from: dictionary["path"] ?? dictionary["points"] ?? dictionary["trajectory"])
            normalizePath(&path, startPoint: startPoint, endPoint: endPoint)

            return Self(
                rawJSON: rawText,
                text: string(from: dictionary["text"]) ?? string(from: dictionary["content"]),
                startX: startPoint.map { Double($0.x) },
                startY: startPoint.map { Double($0.y) },
                endX: endPoint.map { Double($0.x) } ?? path?.last.map { Double($0.x) },
                endY: endPoint.map { Double($0.y) } ?? path?.last.map { Double($0.y) },
                alphaFrom: alphaFrom,
                alphaTo: alphaTo,
                lifetime: timeInterval(from: dictionary["duration"]) ?? timeInterval(from: dictionary["lifetime"]),
                translationDuration: timeInterval(from: dictionary["moveDuration"]) ?? timeInterval(from: dictionary["translationDuration"]),
                translationDelay: timeInterval(from: dictionary["moveDelay"]) ?? timeInterval(from: dictionary["translationDelay"]) ?? 0,
                rotationZ: number(from: dictionary["rotationZ"]) ?? number(from: dictionary["rotateZ"]) ?? number(from: dictionary["fromRotationZ"]),
                endRotationZ: number(from: dictionary["endRotationZ"]) ?? number(from: dictionary["toRotationZ"]),
                rotationY: number(from: dictionary["rotationY"]) ?? number(from: dictionary["rotateY"]),
                fontFamily: fontFamily(from: dictionary["fontFamily"] ?? dictionary["font"]),
                usesStroke: bool(from: dictionary["usesStroke"] ?? dictionary["stroke"] ?? dictionary["outline"]),
                motionCurve: curve(from: dictionary["motionCurve"] ?? dictionary["easing"]) ?? .linear,
                path: path
            )
        }

        return nil
    }

    private static func value(at index: Int, in array: [Any]) -> Any? {
        guard array.indices.contains(index) else { return nil }
        return array[index]
    }

    private static func extractText(from array: [Any]) -> String? {
        if let candidate = string(from: value(at: 4, in: array))?.trimmingCharacters(in: .whitespacesAndNewlines),
           candidate.isEmpty == false {
            return candidate
        }

        for value in array.reversed() {
            guard let candidate = string(from: value)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  candidate.isEmpty == false else {
                continue
            }
            if Double(candidate) != nil || pathPoints(from: value) != nil || curve(from: value) != nil {
                continue
            }
            return candidate
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

    private static func point(x: Any?, y: Any?) -> CGPoint? {
        guard let x = number(from: x), let y = number(from: y) else { return nil }
        return CGPoint(x: x, y: y)
    }

    private static func normalizePath(
        _ path: inout [CGPoint]?,
        startPoint: CGPoint?,
        endPoint: CGPoint?
    ) {
        guard path != nil || startPoint != nil || endPoint != nil else { return }
        var resolved = path ?? []

        if let startPoint {
            if resolved.first.map({ approximatelyEqual($0, startPoint) }) != true {
                resolved.insert(startPoint, at: 0)
            }
        }

        if let endPoint {
            if resolved.last.map({ approximatelyEqual($0, endPoint) }) != true {
                resolved.append(endPoint)
            }
        }

        path = resolved.isEmpty ? nil : resolved
    }

    private static func approximatelyEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.0001 && abs(lhs.y - rhs.y) < 0.0001
    }

    private static func pathPoints(from value: Any?) -> [CGPoint]? {
        switch value {
        case let points as [Any]:
            let resolved = points.compactMap(point(from:))
            return resolved.count >= 2 ? resolved : nil
        case let dictionary as [String: Any]:
            if let nested = dictionary["points"] {
                return pathPoints(from: nested)
            }
            return point(from: dictionary).map { [$0] }
        case let raw as String:
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            if (trimmed.hasPrefix("[") || trimmed.hasPrefix("{")),
               let data = trimmed.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                return pathPoints(from: object)
            }
            guard trimmed.contains(",") || trimmed.contains("M") || trimmed.contains("L") || trimmed.contains(";") || trimmed.contains("|") else {
                return nil
            }
            let numbers = extractNumbers(from: trimmed)
            guard numbers.count >= 4, numbers.count.isMultiple(of: 2) else { return nil }
            return stride(from: 0, to: numbers.count, by: 2).map {
                CGPoint(x: numbers[$0], y: numbers[$0 + 1])
            }
        default:
            return nil
        }
    }

    private static func point(from value: Any?) -> CGPoint? {
        switch value {
        case let array as [Any]:
            guard array.count >= 2 else { return nil }
            return point(x: array[0], y: array[1])
        case let dictionary as [String: Any]:
            return point(
                x: dictionary["x"] ?? dictionary["0"] ?? dictionary["left"],
                y: dictionary["y"] ?? dictionary["1"] ?? dictionary["top"]
            )
        default:
            return nil
        }
    }

    private static func extractNumbers(from raw: String) -> [Double] {
        let pattern = #"-?\d+(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        return regex.matches(in: raw, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: raw) else { return nil }
            return Double(raw[swiftRange])
        }
    }

    private static func curve(from value: Any?) -> DanmakuMotionCurve? {
        switch value {
        case let string as String:
            let normalized = string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
            switch normalized {
            case "linear", "0":
                return .linear
            case "easein", "ease", "1":
                return .easeIn
            case "easeout", "2":
                return .easeOut
            case "easeinout", "3":
                return .easeInOut
            default:
                return nil
            }
        case let number as NSNumber:
            return curve(from: number.stringValue)
        default:
            return nil
        }
    }

    private static func fontFamily(from value: Any?) -> String? {
        guard let candidate = string(from: value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              candidate.isEmpty == false,
              Double(candidate) == nil,
              pathPoints(from: value) == nil else {
            return nil
        }
        return candidate
    }

    private static func bool(from value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
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
        if let customLifetime = advancedPayload?.totalLifetime, customLifetime > 0 {
            return customLifetime
        }
        return mode.defaultLifetime
    }
}

public struct DanmakuDocument: Equatable, Sendable {
    public let comments: [DanmakuComment]
    public let maximumVisibilityWindow: TimeInterval

    package let renderableComments: [DanmakuComment]
    package let timelineIndex: DanmakuTimelineIndex

    public init(comments: [DanmakuComment]) {
        let sortedComments = comments.sorted { lhs, rhs in
            if lhs.appearTime != rhs.appearTime {
                return lhs.appearTime < rhs.appearTime
            }
            return lhs.id < rhs.id
        }
        self.comments = sortedComments
        self.renderableComments = sortedComments.filter { $0.mode.isRenderable }
        self.maximumVisibilityWindow = sortedComments.map(\.visibilityWindow).max() ?? 0
        self.timelineIndex = DanmakuTimelineIndex(
            times: sortedComments.map(\.appearTime),
            bucketDuration: 0.5
        )
    }

    public func comments(in timeRange: ClosedRange<TimeInterval>) -> ArraySlice<DanmakuComment> {
        guard comments.isEmpty == false else { return comments[0..<0] }
        let lower = lowerBound(for: max(timeRange.lowerBound, 0))
        let upper = upperBound(for: max(timeRange.upperBound, 0))
        return comments[lower..<upper]
    }

    public func lowerBound(for time: TimeInterval) -> Int {
        lowerBound(in: candidateRange(for: time), time: max(time, 0))
    }

    public func upperBound(for time: TimeInterval) -> Int {
        upperBound(in: candidateRange(for: time), time: max(time, 0))
    }

    private func candidateRange(for time: TimeInterval) -> Range<Int> {
        timelineIndex.searchRange(for: time, totalCount: comments.count)
    }

    private func lowerBound(in range: Range<Int>, time: TimeInterval) -> Int {
        var lower = range.lowerBound
        var upper = range.upperBound
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

    private func upperBound(in range: Range<Int>, time: TimeInterval) -> Int {
        var lower = range.lowerBound
        var upper = range.upperBound
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

package struct DanmakuTimelineIndex: Equatable, Sendable {
    package let bucketDuration: TimeInterval
    private let firstBucket: Int
    private let offsets: [Int]

    package init(times: [TimeInterval], bucketDuration: TimeInterval) {
        let normalizedTimes = times.map { max($0, 0) }
        self.bucketDuration = max(bucketDuration, 0.1)

        guard let first = normalizedTimes.first,
              let last = normalizedTimes.last else {
            self.firstBucket = 0
            self.offsets = [0]
            return
        }

        let firstBucket = Int(floor(first / self.bucketDuration))
        let lastBucket = Int(floor(last / self.bucketDuration))
        self.firstBucket = firstBucket

        var offsets = Array(repeating: normalizedTimes.count, count: lastBucket - firstBucket + 2)
        var timeIndex = 0

        for bucket in firstBucket...(lastBucket + 1) {
            let bucketStart = TimeInterval(bucket) * self.bucketDuration
            while timeIndex < normalizedTimes.count, normalizedTimes[timeIndex] < bucketStart {
                timeIndex += 1
            }
            offsets[bucket - firstBucket] = timeIndex
        }

        self.offsets = offsets
    }

    package func searchRange(for time: TimeInterval, totalCount: Int) -> Range<Int> {
        guard totalCount > 0, offsets.isEmpty == false else { return 0..<0 }

        let normalizedTime = max(time, 0)
        let bucket = Int(floor(normalizedTime / bucketDuration))

        if bucket < firstBucket {
            let upper = min(offsets.first ?? 0, totalCount)
            return 0..<upper
        }

        let localBucket = bucket - firstBucket
        if localBucket >= offsets.count - 1 {
            let lower = min(max(offsets.last ?? 0, 0), totalCount)
            return lower..<totalCount
        }

        let lower = min(max(offsets[localBucket], 0), totalCount)
        let upper = min(max(offsets[localBucket + 1], lower), totalCount)
        return lower..<upper
    }
}
