import Foundation

enum SubtitleSanitizer {
    private struct StyleDefinition {
        let alignment: Int?
        let marginV: Int?
    }

    private enum Language {
        case japanese
        case chinese
        case other
    }

    private struct DialogueEntry {
        let index: Int
        let fields: [String]
        let style: String
        let styleIndex: Int
        let textIndex: Int
        let language: Language
        let pairingKey: String?
    }

    static func prepareForFSPlayer(rawText: String, fileName: String) -> String {
        guard let document = parseASS(rawText),
              document.supportsBilingualLayout else {
            return rawText
        }
        return makeMergedBilingualASS(document: document)
    }

    private struct ASSDocument {
        let lines: [String]
        let styles: [String: StyleDefinition]
        let dialogueEntries: [DialogueEntry]
        let textIndex: Int
        let supportsBilingualLayout: Bool
    }

    private static func parseASS(_ rawText: String) -> ASSDocument? {
        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.contains(where: { $0.hasPrefix("[Events]") }),
              lines.contains(where: { $0.hasPrefix("Dialogue:") }) else {
            return nil
        }

        var inEventsSection = false
        var inStylesSection = false
        var formatFieldCount = 0
        var textFieldIndex = -1
        var styleFieldIndex: Int?
        var styleFormat: [String] = []
        var styles: [String: StyleDefinition] = [:]
        var dialogueEntries: [DialogueEntry] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[Events]") {
                inEventsSection = true
                inStylesSection = false
                continue
            }
            if trimmed.hasPrefix("[V4+ Styles]") || trimmed.hasPrefix("[V4 Styles]") {
                inStylesSection = true
                inEventsSection = false
                continue
            }

            if inStylesSection {
                if trimmed.lowercased().hasPrefix("format:") {
                    let formatLine = trimmed.dropFirst("Format:".count)
                    styleFormat = formatLine.split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespaces).uppercased()
                    }
                    continue
                }
                if trimmed.lowercased().hasPrefix("style:"),
                   let style = parseStyleDefinition(trimmed, format: styleFormat) {
                    styles[style.name] = .init(alignment: style.alignment, marginV: style.marginV)
                }
                continue
            }

            if !inEventsSection { continue }
            if trimmed.lowercased().hasPrefix("format:") {
                let formatLine = trimmed.dropFirst("Format:".count)
                let fields = formatLine.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                formatFieldCount = fields.count
                let uppercased = fields.map { $0.uppercased() }
                textFieldIndex = uppercased.firstIndex(of: "TEXT") ?? -1
                styleFieldIndex = uppercased.firstIndex(of: "STYLE")
                continue
            }
            guard trimmed.hasPrefix("Dialogue:") else { continue }
            guard formatFieldCount > 0,
                  textFieldIndex >= 0,
                  let styleIndex = styleFieldIndex else { continue }
            let payload = trimmed.dropFirst("Dialogue:".count)
            guard let fields = splitASSFields(String(payload), expected: formatFieldCount) else { continue }
            let style = fields[styleIndex]
            let language = languageForStyle(style)
            let pairingKey = makePairingKey(fields: fields, styleIndex: styleIndex, textIndex: textFieldIndex, style: style)
            let entry = DialogueEntry(
                index: index,
                fields: fields,
                style: style,
                styleIndex: styleIndex,
                textIndex: textFieldIndex,
                language: language,
                pairingKey: pairingKey
            )
            dialogueEntries.append(entry)
        }

        guard !dialogueEntries.isEmpty,
              let styleIndex = styleFieldIndex else { return nil }

        var groups: [String: [DialogueEntry]] = [:]
        for entry in dialogueEntries {
            guard let key = entry.pairingKey else { continue }
            groups[key, default: []].append(entry)
        }

        let supportsBilingualLayout = groups.values.contains { entries in
            requiresMarginWorkaround(entries: entries, styles: styles)
        }

        return ASSDocument(
            lines: lines,
            styles: styles,
            dialogueEntries: dialogueEntries,
            textIndex: textFieldIndex,
            supportsBilingualLayout: supportsBilingualLayout
        )
    }

    private static func makeMergedBilingualASS(document: ASSDocument) -> String {
        var grouped: [String: [DialogueEntry]] = [:]
        for entry in document.dialogueEntries {
            guard let key = entry.pairingKey else { continue }
            grouped[key, default: []].append(entry)
        }

        var replacements: [Int: String] = [:]
        var skipIndices = Set<Int>()

        for entries in grouped.values {
            guard requiresMarginWorkaround(entries: entries, styles: document.styles) else {
                continue
            }
            let jpEntries = entries.filter { $0.language == .japanese }.sorted { $0.index < $1.index }
            let chEntries = entries.filter { $0.language == .chinese }.sorted { $0.index < $1.index }
            let pairCount = min(jpEntries.count, chEntries.count)
            guard pairCount > 0 else { continue }

            for idx in 0..<pairCount {
                let jp = jpEntries[idx]
                let ch = chEntries[idx]
                let primary = jp.index <= ch.index ? jp : ch
                let secondary = primary.index == jp.index ? ch : jp
                var fields = primary.fields
                fields[document.textIndex] = combinedASSLine(
                    japaneseText: jp.fields[document.textIndex],
                    japaneseStyle: jp.style,
                    chineseText: ch.fields[document.textIndex],
                    chineseStyle: ch.style
                )
                replacements[primary.index] = "Dialogue: " + fields.joined(separator: ",")
                skipIndices.insert(secondary.index)
            }
        }

        return render(document: document, replacements: replacements, skipIndices: skipIndices)
    }

    private static func render(
        document: ASSDocument,
        replacements: [Int: String],
        skipIndices: Set<Int>
    ) -> String {
        var output: [String] = []
        output.reserveCapacity(document.lines.count)

        for (index, line) in document.lines.enumerated() {
            if skipIndices.contains(index) { continue }
            if let replacement = replacements[index] {
                output.append(replacement)
            } else {
                output.append(line)
            }
        }

        return output.joined(separator: "\n")
    }

    private static func parseStyleDefinition(_ line: String, format: [String]) -> (name: String, alignment: Int?, marginV: Int?)? {
        guard !format.isEmpty else { return nil }
        let payload = line.dropFirst("Style:".count)
        let values = payload.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard values.count == format.count,
              let nameIndex = format.firstIndex(of: "NAME"),
              values.indices.contains(nameIndex) else {
            return nil
        }

        let alignment: Int?
        if let alignmentIndex = format.firstIndex(of: "ALIGNMENT"), values.indices.contains(alignmentIndex) {
            alignment = Int(values[alignmentIndex])
        } else {
            alignment = nil
        }

        let marginV: Int?
        if let marginVIndex = format.firstIndex(of: "MARGINV"), values.indices.contains(marginVIndex) {
            marginV = Int(values[marginVIndex])
        } else {
            marginV = nil
        }

        return (
            name: values[nameIndex],
            alignment: alignment,
            marginV: marginV
        )
    }

    private static func splitASSFields(_ content: String, expected: Int) -> [String]? {
        var fields: [String] = []
        fields.reserveCapacity(expected)
        var current = ""
        var iterator = content.makeIterator()
        var remaining = expected - 1
        while let char = iterator.next() {
            if char == "," && remaining > 0 {
                fields.append(current)
                current.removeAll(keepingCapacity: true)
                remaining -= 1
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields.count == expected ? fields : nil
    }

    private static func languageForStyle(_ style: String) -> Language {
        guard let role = styleRole(for: style) else {
            return .other
        }
        switch role.language {
        case .japanese:
            return .japanese
        case .chinese:
            return .chinese
        case .other:
            return .other
        }
    }

    private static func makePairingKey(
        fields: [String],
        styleIndex: Int,
        textIndex: Int,
        style: String
    ) -> String? {
        guard let role = styleRole(for: style) else {
            return nil
        }
        var normalized = fields
        normalized[styleIndex] = role.baseKey
        normalized[textIndex] = ""
        return normalized.joined(separator: "\u{1F}")
    }

    private struct StyleRole {
        let language: Language
        let baseKey: String
    }

    private static func styleRole(for style: String) -> StyleRole? {
        let patterns = [
            "_(JP|JPN|JA|CH|SC|TC|ZH|CN)(\\d*)$",
            "(JP|JPN|JA|CH|SC|TC|ZH|CN)(\\d*)$"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(style.startIndex..<style.endIndex, in: style)
            guard let match = regex.firstMatch(in: style, options: [], range: range),
                  match.range.location != NSNotFound,
                  let langRange = Range(match.range(at: 1), in: style) else {
                continue
            }

            let languageToken = style[langRange].lowercased()
            let language: Language
            switch languageToken {
            case "jp", "jpn", "ja":
                language = .japanese
            case "ch", "sc", "tc", "zh", "cn":
                language = .chinese
            default:
                language = .other
            }
            let base = regex.stringByReplacingMatches(
                in: style,
                options: [],
                range: range,
                withTemplate: pattern.hasPrefix("_") ? "_$2" : "$2"
            )
            let normalizedBase = base.replacingOccurrences(of: "__", with: "_")
            guard language != .other else { continue }
            return StyleRole(language: language, baseKey: normalizedBase)
        }

        return nil
    }

    private static func combinedASSLine(japaneseText: String, japaneseStyle: String, chineseText: String, chineseStyle: String) -> String {
        let jpSegment = "{\\r\(japaneseStyle)}\(japaneseText)"
        let chSegment = "{\\r\(chineseStyle)}\(chineseText)"
        return jpSegment + "\\N" + chSegment
    }

    private static func requiresMarginWorkaround(
        entries: [DialogueEntry],
        styles: [String: StyleDefinition]
    ) -> Bool {
        let japaneseEntries = entries.filter { $0.language == .japanese }.sorted { $0.index < $1.index }
        let chineseEntries = entries.filter { $0.language == .chinese }.sorted { $0.index < $1.index }
        let pairCount = min(japaneseEntries.count, chineseEntries.count)
        guard pairCount > 0 else { return false }

        for idx in 0..<pairCount {
            guard let japaneseStyle = styles[japaneseEntries[idx].style],
                  let chineseStyle = styles[chineseEntries[idx].style],
                  let japaneseAlignment = japaneseStyle.alignment,
                  let chineseAlignment = chineseStyle.alignment,
                  let japaneseMarginV = japaneseStyle.marginV,
                  let chineseMarginV = chineseStyle.marginV else {
                continue
            }

            if japaneseAlignment == chineseAlignment,
               japaneseMarginV != chineseMarginV {
                return true
            }
        }

        return false
    }
}
