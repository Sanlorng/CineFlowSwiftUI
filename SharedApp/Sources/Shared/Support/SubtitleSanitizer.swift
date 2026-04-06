import Foundation

enum SubtitleSanitizer {
    private enum Language {
        case japanese
        case chinese
        case other
    }

    private struct DialogueEntry {
        let index: Int
        var fields: [String]
        let style: String
        let start: String
        let end: String
        let textIndex: Int
        let language: Language
        let baseKey: String
        let layer: Int?
        let marginV: Int?
        let alignment: Int?
    }

    static func sanitizeASS(forFSPlayer rawText: String) -> String? {
        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.contains(where: { $0.hasPrefix("Dialogue:") }) else {
            return nil
        }

        var inEventsSection = false
        var formatFieldCount = 0
        var textFieldIndex = -1
        var styleFieldIndex: Int?
        var startFieldIndex: Int?
        var endFieldIndex: Int?
        var layerFieldIndex: Int?
        var marginVFieldIndex: Int?
        var alignmentFieldIndex: Int?
        var dialogueEntries: [DialogueEntry] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[Events]") {
                inEventsSection = true
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
                startFieldIndex = uppercased.firstIndex(of: "START")
                endFieldIndex = uppercased.firstIndex(of: "END")
                layerFieldIndex = uppercased.firstIndex(of: "LAYER")
                marginVFieldIndex = uppercased.firstIndex(of: "MARGINV")
                alignmentFieldIndex = uppercased.firstIndex(of: "ALIGNMENT")
                continue
            }
            guard trimmed.hasPrefix("Dialogue:") else { continue }
            guard formatFieldCount > 0, textFieldIndex >= 0 else { continue }
            let payload = trimmed.dropFirst("Dialogue:".count)
            guard let fields = splitASSFields(String(payload), expected: formatFieldCount) else { continue }
            let style = fieldValue(from: fields, preferredIndex: styleFieldIndex, fallbackIndex: 3)
            let start = fieldValue(from: fields, preferredIndex: startFieldIndex, fallbackIndex: 1)
            let end = fieldValue(from: fields, preferredIndex: endFieldIndex, fallbackIndex: 2)
            let language = languageForStyle(style)
            let baseKey = makeBaseStyleKey(style)
            let layer = intValue(from: fields, at: layerFieldIndex)
            let marginV = intValue(from: fields, at: marginVFieldIndex)
            let alignment = intValue(from: fields, at: alignmentFieldIndex)
            let entry = DialogueEntry(
                index: index,
                fields: fields,
                style: style,
                start: start,
                end: end,
                textIndex: textFieldIndex,
                language: language,
                baseKey: baseKey,
                layer: layer,
                marginV: marginV,
                alignment: alignment
            )
            dialogueEntries.append(entry)
        }

        guard !dialogueEntries.isEmpty else { return nil }

        var groups: [String: [DialogueEntry]] = [:]
        for entry in dialogueEntries {
            let key = "\(entry.start)|\(entry.end)|\(entry.baseKey)"
            groups[key, default: []].append(entry)
        }

        var replacements: [Int: String] = [:]
        var skipIndices = Set<Int>()

        for (_, entries) in groups {
            let jpEntries = entries.filter { $0.language == .japanese }
            let chEntries = entries.filter { $0.language == .chinese }
            guard layoutIsMergeCompatible(entries) else { continue }
            guard let primary = chEntries.first ?? jpEntries.first else { continue }
            guard !jpEntries.isEmpty && !chEntries.isEmpty else { continue }
            var primaryFields = primary.fields
            let jpText = jpEntries.first?.fields[primary.textIndex] ?? ""
            let chText = chEntries.first?.fields[primary.textIndex] ?? ""
            let combinedText = combinedASSLine(japaneseText: jpText, japaneseStyle: jpEntries.first?.style ?? primary.style, chineseText: chText, chineseStyle: chEntries.first?.style ?? primary.style)
            primaryFields[primary.textIndex] = combinedText
            let newLine = "Dialogue: " + primaryFields.joined(separator: ",")
            replacements[primary.index] = newLine
            for entry in entries where entry.index != primary.index {
                skipIndices.insert(entry.index)
            }
        }

        guard !replacements.isEmpty else { return nil }

        var output: [String] = []
        output.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            if skipIndices.contains(index) { continue }
            if let replacement = replacements[index] {
                output.append(replacement)
            } else {
                output.append(line)
            }
        }

        return output.joined(separator: "\n")
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

    private static func fieldValue(from fields: [String], preferredIndex: Int?, fallbackIndex: Int) -> String {
        if let index = preferredIndex, fields.indices.contains(index) {
            return fields[index]
        }
        let safeIndex = min(max(fallbackIndex, 0), fields.count - 1)
        return fields[safeIndex]
    }

    private static func intValue(from fields: [String], at index: Int?) -> Int? {
        guard let index, fields.indices.contains(index) else { return nil }
        return Int(fields[index].trimmingCharacters(in: .whitespaces))
    }

    private static func languageForStyle(_ style: String) -> Language {
        let lower = style.lowercased()
        if lower.contains("_jp") || lower.hasSuffix("jp") {
            return .japanese
        }
        if lower.contains("_ch") || lower.hasSuffix("ch") {
            return .chinese
        }
        return .other
    }

    private static func makeBaseStyleKey(_ style: String) -> String {
        var base = style
        base = base.replacingOccurrences(of: "_JP_Top", with: "_Top", options: .caseInsensitive)
        base = base.replacingOccurrences(of: "_CH_Top", with: "_Top", options: .caseInsensitive)
        base = base.replacingOccurrences(of: "_JP", with: "", options: .caseInsensitive)
        base = base.replacingOccurrences(of: "_CH", with: "", options: .caseInsensitive)
        return base
    }

    private static func combinedASSLine(japaneseText: String, japaneseStyle: String, chineseText: String, chineseStyle: String) -> String {
        let jpSegment = "{\\r\(japaneseStyle)}\(japaneseText)"
        let chSegment = "{\\r\(chineseStyle)}\(chineseText)"
        return jpSegment + "\\N" + chSegment
    }

    private static func layoutIsMergeCompatible(_ entries: [DialogueEntry]) -> Bool {
        // Preserve original stacked layout when languages rely on different layers or margins.
        guard let reference = entries.first else { return false }
        for entry in entries {
            if entry.layer != reference.layer { return false }
            if entry.alignment != reference.alignment { return false }
            if entry.marginV != reference.marginV { return false }
        }
        return true
    }
}
