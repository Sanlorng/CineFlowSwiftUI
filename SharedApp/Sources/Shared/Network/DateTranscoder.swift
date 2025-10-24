import Foundation
import OpenAPIRuntime

struct LenientRFC3339Transcoder: DateTranscoder, @unchecked Sendable {
    private let isoWithMS: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        return f
    }()
    private let isoNoMS: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return f
    }()

    func encode(_ value: Date) throws -> String {
        // 统一输出带毫秒（也可改成 isoNoMS.string(from:) 统一去掉毫秒）
        self.isoWithMS.string(from: value)
    }

    func decode(_ value: String) throws -> Date {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("0001-01-01T00:00:00") {
            // 选择一：返回一个固定占位（业务层识别）
            return Date.distantPast
            // 选择二：如果你更想“强制解析”，也可以补 Z 再试：
            // if let d = Self.isoNoMS.date(from: s0 + "Z") { return d }
        }
        if let d = self.isoWithMS.date(from: s) { return d }
        if let d = self.isoNoMS.date(from: s) { return d }

                // 2) 无时区或毫秒位数不规范 → 先规范化再试
        let x = normalize(s)
        if let d = self.isoWithMS.date(from: x) { return d }
        if let d = self.isoNoMS.date(from: x) { return d }

        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid RFC3339 date-time: \(value)"))
    }

        // 规范化：补时区、规整毫秒到 3 位
    private func normalize(_ s: String) -> String {
        var x = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // 若没有时区与 Z（匹配到结尾是纯日期时间）
        let noTZ = x.range(of: #"Z|[+\-]\d{2}:\d{2}$"#, options: .regularExpression) == nil
        if noTZ { x += "Z" } // 假定 UTC

        // 如果有小数秒但位数不是 3，则补/截成 3 位（只处理 Z/±HH:MM 前面的部分）
        if let fracRange = x.range(of: #"\.\d+"#, options: .regularExpression) {
            let digitsRange = x.index(after: fracRange.lowerBound)..<fracRange.upperBound
            let digits = x[digitsRange]
            let count = digits.count
            if count != 3 {
                let fixed: String
                if count > 3 {
                    fixed = String(digits.prefix(3))
                } else {
                    fixed = digits + String(repeating: "0", count: 3 - count)
                }
                x.replaceSubrange(digitsRange, with: fixed)
            }
        }
        return x
    }
}