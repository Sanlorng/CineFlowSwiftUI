import Foundation
import SubtitleRendererCore
#if canImport(SubtitleFFmpegBridge)
import SubtitleFFmpegBridge

enum EmbeddedSubtitleExtractorError: LocalizedError {
    case extractionFailed(String)
    case invalidTrackIdentifier(String)

    var errorDescription: String? {
        switch self {
        case let .extractionFailed(message):
            return message
        case let .invalidTrackIdentifier(identifier):
            return "无效的字幕轨标识：\(identifier)"
        }
    }
}

struct EmbeddedSubtitleExtractor: SubtitleTrackExtracting {
    private static let documentCache = EmbeddedSubtitleDocumentCache()

    func availableTracks(for mediaURL: URL, headers: [String: String]) async throws -> [SubtitleTrack] {
        let headerValue = makeHeaderValue(headers)
        return try mediaURL.absoluteString.withCString { mediaURLCString in
            try withHeaderCString(headerValue) { headerCString in
                var tracksPointer: UnsafeMutablePointer<SubtitleBridgeTrackInfo>?
                var count: Int32 = 0
                var errorPointer: UnsafeMutablePointer<CChar>?

                defer {
                    if let tracksPointer {
                        subtitle_bridge_free_tracks(tracksPointer, count)
                    }
                    if let errorPointer {
                        subtitle_bridge_free_string(errorPointer)
                    }
                }

                let result = subtitle_bridge_copy_tracks(
                    mediaURLCString,
                    headerCString,
                    &tracksPointer,
                    &count,
                    &errorPointer
                )

                guard result == 0 else {
                    throw EmbeddedSubtitleExtractorError.extractionFailed(string(from: errorPointer) ?? "提取内嵌字幕轨失败。")
                }

                guard let tracksPointer, count > 0 else {
#if DEBUG
                    print("[EmbeddedSubtitleExtractor] No embedded subtitle tracks for \(mediaURL.absoluteString)")
#endif
                    return [SubtitleTrack]()
                }

                let buffer = UnsafeBufferPointer(start: tracksPointer, count: Int(count))
                let tracks: [SubtitleTrack] = buffer.map { item in
                    SubtitleTrack(
                        id: String(item.stream_index),
                        displayName: makeDisplayName(title: item.title, language: item.language, codecName: item.codec_name, streamIndex: item.stream_index),
                        language: item.language.flatMap { String(cString: $0) },
                        formatHint: .ass,
                        kind: .embedded
                    )
                }
#if DEBUG
                let summary = tracks.map { "\($0.id):\($0.displayName)" }.joined(separator: ", ")
                print("[EmbeddedSubtitleExtractor] Tracks => [\(summary)]")
#endif
                return tracks
            }
        }
    }

    func loadDocument(for trackID: SubtitleTrack.ID, from mediaURL: URL, headers: [String: String]) async throws -> SubtitleDocument {
        guard let streamIndex = Int(trackID) else {
            throw EmbeddedSubtitleExtractorError.invalidTrackIdentifier(trackID)
        }

        let headerValue = makeHeaderValue(headers)
        let cacheKey = EmbeddedSubtitleDocumentCache.Key(
            mediaURL: mediaURL.absoluteString,
            headerValue: headerValue ?? "",
            trackID: trackID
        )
        return try await Self.documentCache.document(for: cacheKey) {
            try mediaURL.absoluteString.withCString { mediaURLCString in
                try withHeaderCString(headerValue) { headerCString in
                    var documentPointer: UnsafeMutablePointer<CChar>?
                    var errorPointer: UnsafeMutablePointer<CChar>?

                    defer {
                        if let documentPointer {
                            subtitle_bridge_free_string(documentPointer)
                        }
                        if let errorPointer {
                            subtitle_bridge_free_string(errorPointer)
                        }
                    }

                    let result = subtitle_bridge_copy_ass_document(
                        mediaURLCString,
                        headerCString,
                        Int32(streamIndex),
                        &documentPointer,
                        &errorPointer
                    )

                    guard result == 0, let documentPointer else {
                        throw EmbeddedSubtitleExtractorError.extractionFailed(string(from: errorPointer) ?? "提取内嵌字幕失败。")
                    }

#if DEBUG
                    print("[EmbeddedSubtitleExtractor] Loaded embedded subtitle track \(streamIndex)")
#endif
                    return .ass(
                        String(cString: documentPointer),
                        fileName: "embedded-\(streamIndex).ass"
                    )
                }
            }
        }
    }
    private func makeHeaderValue(_ headers: [String: String]) -> String? {
        guard !headers.isEmpty else { return nil }
        return headers
            .map { "\($0): \($1)" }
            .joined(separator: "\r\n") + "\r\n"
    }

    private func makeDisplayName(
        title: UnsafeMutablePointer<CChar>?,
        language: UnsafeMutablePointer<CChar>?,
        codecName: UnsafeMutablePointer<CChar>?,
        streamIndex: Int32
    ) -> String {
        let titleString = title.map { String(cString: $0) }
        let languageString = language.map { String(cString: $0) }
        let codecString = codecName.map { String(cString: $0) }

        if let titleString, !titleString.isEmpty,
           let languageString, !languageString.isEmpty {
            return "\(titleString) (\(languageString))"
        }
        if let titleString, !titleString.isEmpty {
            return titleString
        }
        if let languageString, !languageString.isEmpty,
           let codecString, !codecString.isEmpty {
            return "\(languageString) [\(codecString)]"
        }
        if let codecString, !codecString.isEmpty {
            return "内嵌字幕 #\(streamIndex) [\(codecString)]"
        }
        return "内嵌字幕 #\(streamIndex)"
    }
}

private func withHeaderCString<R>(_ value: String?, _ body: (UnsafePointer<CChar>?) throws -> R) throws -> R {
    guard let value, !value.isEmpty else {
        return try body(nil)
    }
    return try value.withCString(body)
}

private func string(from pointer: UnsafeMutablePointer<CChar>?) -> String? {
    guard let pointer else { return nil }
    return String(cString: pointer)
}

private actor EmbeddedSubtitleDocumentCache {
    struct Key: Hashable, Sendable {
        let mediaURL: String
        let headerValue: String
        let trackID: SubtitleTrack.ID
    }

    private var cachedDocuments: [Key: SubtitleDocument] = [:]
    private var inFlightLoads: [Key: Task<SubtitleDocument, Error>] = [:]

    func document(
        for key: Key,
        loader: @escaping @Sendable () async throws -> SubtitleDocument
    ) async throws -> SubtitleDocument {
        if let cachedDocument = cachedDocuments[key] {
            return cachedDocument
        }
        if let inFlightLoad = inFlightLoads[key] {
            return try await inFlightLoad.value
        }

        let task = Task {
            try await loader()
        }
        inFlightLoads[key] = task

        do {
            let document = try await task.value
            cachedDocuments[key] = document
            inFlightLoads[key] = nil
            return document
        } catch {
            inFlightLoads[key] = nil
            throw error
        }
    }
}
#else
enum EmbeddedSubtitleExtractorError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "当前默认播放器后端未启用内嵌字幕提取。"
        }
    }
}

struct EmbeddedSubtitleExtractor: SubtitleTrackExtracting {
    func availableTracks(for mediaURL: URL, headers: [String: String]) async throws -> [SubtitleTrack] {
        []
    }

    func loadDocument(for trackID: SubtitleTrack.ID, from mediaURL: URL, headers: [String: String]) async throws -> SubtitleDocument {
        throw EmbeddedSubtitleExtractorError.unavailable
    }
}
#endif
