import Foundation

struct DanmakuPayload: Equatable, Sendable {
    struct Comment: Equatable, Identifiable, Sendable {
        enum Mode: Int, Equatable, Sendable {
            case scroll = 1
            case scrollAlt = 2
            case scrollBottom = 3
            case bottom = 4
            case top = 5
            case reverseScroll = 6

            var isSupported: Bool {
                switch self {
                case .scroll, .scrollAlt, .scrollBottom, .bottom, .top, .reverseScroll:
                    true
                }
            }
        }

        let id: Int
        let appearTime: TimeInterval
        let mode: Mode
        let fontSize: Double
        let colorRGB: UInt32
        let text: String

        var visibilityWindow: TimeInterval {
            switch mode {
            case .bottom, .top:
                4
            case .scroll, .scrollAlt, .scrollBottom, .reverseScroll:
                12
            }
        }
    }

    let comments: [Comment]
    let commentsBySecond: [UInt: [Comment]]
}

enum BilibiliDanmakuParser {
    static func parse(xml: String) throws -> DanmakuPayload {
        let parser = Parser(xml: xml)
        return try parser.parse()
    }
}

private final class Parser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var comments: [DanmakuPayload.Comment] = []
    private var currentAttributes: [String: String]?
    private var currentText = ""
    private var nextCommentID = 0
    private var parserError: Error?

    init(xml: String) {
        let data = Data(xml.utf8)
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }

    func parse() throws -> DanmakuPayload {
        guard parser.parse() else {
            throw parserError
                ?? parser.parserError
                ?? NSError(domain: "BilibiliDanmakuParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "弹幕 XML 解析失败。"])
        }
        let sortedComments = comments.sorted { lhs, rhs in
            if lhs.appearTime != rhs.appearTime {
                return lhs.appearTime < rhs.appearTime
            }
            return lhs.id < rhs.id
        }
        var commentsBySecond: [UInt: [DanmakuPayload.Comment]] = [:]
        for comment in sortedComments {
            let second = UInt(max(comment.appearTime, 0).rounded(.towardZero))
            commentsBySecond[second, default: []].append(comment)
        }
        return DanmakuPayload(
            comments: sortedComments,
            commentsBySecond: commentsBySecond
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "d" else { return }
        currentAttributes = attributeDict
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "d" else { return }
        defer {
            currentAttributes = nil
            currentText = ""
        }
        guard let attributes = currentAttributes,
              let rawP = attributes["p"] else {
            return
        }
        guard let comment = makeComment(rawP: rawP, text: currentText) else {
            return
        }
        comments.append(comment)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        parserError = parseError
    }

    private func makeComment(rawP: String, text: String) -> DanmakuPayload.Comment? {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let parts = rawP.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4,
              let appearTime = TimeInterval(parts[0]),
              let modeValue = Int(parts[1]),
              let mode = DanmakuPayload.Comment.Mode(rawValue: modeValue),
              mode.isSupported,
              let fontSize = Double(parts[2]),
              let colorValue = UInt32(parts[3]) else {
            return nil
        }

        defer { nextCommentID += 1 }
        return DanmakuPayload.Comment(
            id: nextCommentID,
            appearTime: appearTime,
            mode: mode,
            fontSize: fontSize,
            colorRGB: colorValue,
            text: content
        )
    }
}
