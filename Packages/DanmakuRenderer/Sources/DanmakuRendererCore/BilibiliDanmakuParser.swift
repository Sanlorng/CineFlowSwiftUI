import Foundation

public enum DanmakuParserError: LocalizedError, Sendable {
    case emptyInput

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "弹幕 XML 为空。"
        }
    }
}

public enum BilibiliDanmakuParser {
    public static func parse(xml: String) throws -> DanmakuDocument {
        guard xml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw DanmakuParserError.emptyInput
        }
        var parser = Parser(xml: xml)
        return parser.parse()
    }
}

private struct Parser {
    private struct CommentNode {
        let rawParameter: String
        let text: String
    }

    private let bytes: [UInt8]
    private var index = 0
    private var nextCommentID = 0

    init(xml: String) {
        self.bytes = Array(xml.utf8)
    }

    mutating func parse() -> DanmakuDocument {
        var comments: [DanmakuComment] = []
        comments.reserveCapacity(4096)

        while let node = nextCommentNode() {
            if let comment = makeComment(rawParameter: node.rawParameter, text: node.text) {
                comments.append(comment)
            }
        }

        return DanmakuDocument(comments: comments)
    }

    private mutating func nextCommentNode() -> CommentNode? {
        let lessThan = UInt8(ascii: "<")
        let greaterThan = UInt8(ascii: ">")
        let slash = UInt8(ascii: "/")
        let quote = UInt8(ascii: "\"")
        let apostrophe = UInt8(ascii: "'")

        while index < bytes.count {
            guard let tagStart = findByte(lessThan, startingAt: index) else {
                index = bytes.count
                return nil
            }

            var scan = tagStart + 1
            guard scan < bytes.count else {
                index = bytes.count
                return nil
            }

            if bytes[scan] != UInt8(ascii: "d") {
                index = scan
                continue
            }

            let trailing = scan + 1 < bytes.count ? bytes[scan + 1] : nil
            if let trailing, isNameByte(trailing) {
                index = scan + 1
                continue
            }

            scan += 1
            var rawParameter: String?
            var reachedTagEnd = false

            while scan < bytes.count {
                skipWhitespace(&scan)
                guard scan < bytes.count else { break }

                if bytes[scan] == greaterThan {
                    scan += 1
                    reachedTagEnd = true
                    break
                }

                if bytes[scan] == slash {
                    if scan + 1 < bytes.count, bytes[scan + 1] == greaterThan {
                        scan += 2
                    }
                    break
                }

                let nameStart = scan
                while scan < bytes.count, isNameByte(bytes[scan]) {
                    scan += 1
                }
                guard nameStart < scan else {
                    scan += 1
                    continue
                }

                let name = String(decoding: bytes[nameStart..<scan], as: UTF8.self)
                skipWhitespace(&scan)
                guard scan < bytes.count, bytes[scan] == UInt8(ascii: "=") else {
                    scan = advanceToTagEnd(from: scan)
                    break
                }

                scan += 1
                skipWhitespace(&scan)
                guard scan < bytes.count, bytes[scan] == quote || bytes[scan] == apostrophe else {
                    scan = advanceToTagEnd(from: scan)
                    break
                }

                let attributeQuote = bytes[scan]
                scan += 1
                let valueStart = scan
                while scan < bytes.count, bytes[scan] != attributeQuote {
                    scan += 1
                }

                let valueEnd = min(scan, bytes.count)
                if name == "p" {
                    rawParameter = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
                }

                if scan < bytes.count {
                    scan += 1
                }
            }

            guard reachedTagEnd else {
                index = scan
                continue
            }

            let contentStart = scan
            guard let contentEnd = findClosingTag(startingAt: contentStart) else {
                index = bytes.count
                return nil
            }

            index = contentEnd + 4

            guard let rawParameter else { continue }

            let rawText = String(decoding: bytes[contentStart..<contentEnd], as: UTF8.self)
            return CommentNode(
                rawParameter: rawParameter,
                text: decodeEntities(in: rawText)
            )
        }

        return nil
    }

    private mutating func makeComment(rawParameter: String, text: String) -> DanmakuComment? {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedText.isEmpty == false else { return nil }

        let parts = rawParameter.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4,
              let appearTime = TimeInterval(parts[0]),
              let rawMode = Int(parts[1]),
              let mode = DanmakuCommentMode(rawValue: rawMode),
              let fontSize = Double(parts[2]),
              let colorRGB = UInt32(parts[3]) else {
            return nil
        }

        let advancedPayload = mode == .advanced ? DanmakuAdvancedPayload.parse(rawText: normalizedText) : nil
        let displayText: String
        if mode == .advanced {
            displayText = advancedPayload?.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ""
        } else {
            displayText = normalizedText
        }

        defer { nextCommentID += 1 }
        return DanmakuComment(
            id: nextCommentID,
            appearTime: appearTime,
            mode: mode,
            fontSize: fontSize,
            colorRGB: colorRGB,
            text: displayText,
            rawParameter: rawParameter,
            advancedPayload: advancedPayload
        )
    }

    private func findByte(_ byte: UInt8, startingAt start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        for candidate in start..<bytes.count where bytes[candidate] == byte {
            return candidate
        }
        return nil
    }

    private func findClosingTag(startingAt start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        var scan = start
        while scan + 3 < bytes.count {
            if bytes[scan] == UInt8(ascii: "<"),
               bytes[scan + 1] == UInt8(ascii: "/"),
               bytes[scan + 2] == UInt8(ascii: "d"),
               bytes[scan + 3] == UInt8(ascii: ">") {
                return scan
            }
            scan += 1
        }
        return nil
    }

    private func advanceToTagEnd(from start: Int) -> Int {
        guard start < bytes.count else { return bytes.count }
        var scan = start
        while scan < bytes.count {
            if bytes[scan] == UInt8(ascii: ">") {
                return scan + 1
            }
            scan += 1
        }
        return bytes.count
    }

    private func skipWhitespace(_ index: inout Int) {
        while index < bytes.count, isWhitespace(bytes[index]) {
            index += 1
        }
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t"):
            return true
        default:
            return false
        }
    }

    private func isNameByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"),
             UInt8(ascii: "_"),
             UInt8(ascii: ":"):
            return true
        default:
            return false
        }
    }

    private func decodeEntities(in rawText: String) -> String {
        guard rawText.contains("&") else { return rawText }

        var output = String()
        output.reserveCapacity(rawText.count)
        var index = rawText.startIndex

        while index < rawText.endIndex {
            let character = rawText[index]
            guard character == "&",
                  let semicolon = rawText[index...].firstIndex(of: ";") else {
                output.append(character)
                index = rawText.index(after: index)
                continue
            }

            let entityRange = rawText.index(after: index)..<semicolon
            let entity = String(rawText[entityRange])
            if let decoded = decodeEntity(entity) {
                output.append(decoded)
                index = rawText.index(after: semicolon)
            } else {
                output.append(character)
                index = rawText.index(after: index)
            }
        }

        return output
    }

    private func decodeEntity(_ entity: String) -> Character? {
        switch entity {
        case "amp":
            return "&"
        case "lt":
            return "<"
        case "gt":
            return ">"
        case "quot":
            return "\""
        case "apos":
            return "'"
        default:
            break
        }

        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            let hexStart = entity.index(entity.startIndex, offsetBy: 2)
            guard let scalar = UInt32(entity[hexStart...], radix: 16).flatMap(UnicodeScalar.init) else {
                return nil
            }
            return Character(scalar)
        }

        if entity.hasPrefix("#") {
            let decimalStart = entity.index(after: entity.startIndex)
            guard let scalar = UInt32(entity[decimalStart...], radix: 10).flatMap(UnicodeScalar.init) else {
                return nil
            }
            return Character(scalar)
        }

        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
