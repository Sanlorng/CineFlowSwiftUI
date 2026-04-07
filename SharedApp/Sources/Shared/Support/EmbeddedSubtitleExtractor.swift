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
        let startedAt = Date()
        let headerValue = makeHeaderValue(headers)
        debugLogEmbeddedSubtitleExtractor(
            "availableTracks start url=\(mediaURL.absoluteString) headerBytes=\(headerValue?.utf8.count ?? 0) headerKeys=\(describeHeaderKeys(headers))"
        )
        do {
            let tracks = try mediaURL.absoluteString.withCString { mediaURLCString in
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

                    let bridgeStartedAt = Date()
                    debugLogEmbeddedSubtitleExtractor(
                        "availableTracks bridge_copy_tracks start url=\(mediaURL.absoluteString)"
                    )
                    let result = subtitle_bridge_copy_tracks(
                        mediaURLCString,
                        headerCString,
                        &tracksPointer,
                        &count,
                        &errorPointer
                    )
                    debugLogEmbeddedSubtitleExtractor(
                        "availableTracks bridge_copy_tracks finished result=\(result) count=\(count) elapsed=\(debugElapsedMilliseconds(since: bridgeStartedAt))"
                    )

                    guard result == 0 else {
                        throw EmbeddedSubtitleExtractorError.extractionFailed(string(from: errorPointer) ?? "提取内嵌字幕轨失败。")
                    }

                    guard let tracksPointer, count > 0 else {
                        return [SubtitleTrack]()
                    }

                    let buffer = UnsafeBufferPointer(start: tracksPointer, count: Int(count))
                    return buffer.map { item in
                        SubtitleTrack(
                            id: String(item.stream_index),
                            displayName: makeDisplayName(title: item.title, language: item.language, codecName: item.codec_name, streamIndex: item.stream_index),
                            language: item.language.flatMap { String(cString: $0) },
                            formatHint: .ass,
                            kind: .embedded
                        )
                    }
                }
            }
            debugLogEmbeddedSubtitleExtractor(
                "availableTracks success count=\(tracks.count) tracks=[\(describeTracks(tracks))] elapsed=\(debugElapsedMilliseconds(since: startedAt))"
            )
            return tracks
        } catch {
            debugLogEmbeddedSubtitleExtractor(
                "availableTracks failed elapsed=\(debugElapsedMilliseconds(since: startedAt)) error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    func loadDocument(for trackID: SubtitleTrack.ID, from mediaURL: URL, headers: [String: String]) async throws -> SubtitleDocument {
        let startedAt = Date()
        let headerValue = makeHeaderValue(headers)
        debugLogEmbeddedSubtitleExtractor(
            "loadDocument start trackID=\(trackID) url=\(mediaURL.absoluteString) headerBytes=\(headerValue?.utf8.count ?? 0) headerKeys=\(describeHeaderKeys(headers))"
        )
        guard let streamIndex = Int(trackID) else {
            debugLogEmbeddedSubtitleExtractor("loadDocument invalid track identifier trackID=\(trackID)")
            throw EmbeddedSubtitleExtractorError.invalidTrackIdentifier(trackID)
        }

        let cacheKey = makeCacheKey(
            mediaURL: mediaURL,
            headerValue: headerValue,
            trackID: trackID,
            window: nil
        )
        do {
            let document = try await Self.documentCache.document(for: cacheKey) {
                let bridgeStartedAt = Date()
                debugLogEmbeddedSubtitleExtractor(
                    "loadDocument bridge_copy_ass_document start trackID=\(trackID) streamIndex=\(streamIndex)"
                )
                return try mediaURL.absoluteString.withCString { mediaURLCString in
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
                            debugLogEmbeddedSubtitleExtractor(
                                "loadDocument bridge_copy_ass_document failed trackID=\(trackID) result=\(result) elapsed=\(debugElapsedMilliseconds(since: bridgeStartedAt)) error=\(string(from: errorPointer) ?? "提取内嵌字幕失败。")"
                            )
                            throw EmbeddedSubtitleExtractorError.extractionFailed(string(from: errorPointer) ?? "提取内嵌字幕失败。")
                        }

                        let documentString = String(cString: documentPointer)
                        debugLogEmbeddedSubtitleExtractor(
                            "loadDocument bridge_copy_ass_document succeeded trackID=\(trackID) bytes=\(documentString.utf8.count) elapsed=\(debugElapsedMilliseconds(since: bridgeStartedAt))"
                        )
                        return .ass(
                            documentString,
                            fileName: "embedded-\(streamIndex).ass"
                        )
                    }
                }
            }
            debugLogEmbeddedSubtitleExtractor(
                "loadDocument success trackID=\(trackID) fileName=\(document.fileName ?? "embedded-\(trackID).ass") elapsed=\(debugElapsedMilliseconds(since: startedAt))"
            )
            return document
        } catch {
            debugLogEmbeddedSubtitleExtractor(
                "loadDocument failed trackID=\(trackID) elapsed=\(debugElapsedMilliseconds(since: startedAt)) error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    func loadDocument(
        for trackID: SubtitleTrack.ID,
        from mediaURL: URL,
        headers: [String: String],
        window: ClosedRange<TimeInterval>
    ) async throws -> SubtitleDocument {
        let startedAt = Date()
        let headerValue = makeHeaderValue(headers)
        let normalizedWindow = normalizeSubtitleWindow(window)
        debugLogEmbeddedSubtitleExtractor(
            "loadDocumentWindow start trackID=\(trackID) url=\(mediaURL.absoluteString) window=\(describeWindow(normalizedWindow)) headerBytes=\(headerValue?.utf8.count ?? 0) headerKeys=\(describeHeaderKeys(headers))"
        )
        guard let streamIndex = Int(trackID) else {
            debugLogEmbeddedSubtitleExtractor("loadDocumentWindow invalid track identifier trackID=\(trackID)")
            throw EmbeddedSubtitleExtractorError.invalidTrackIdentifier(trackID)
        }

        let cacheKey = makeCacheKey(
            mediaURL: mediaURL,
            headerValue: headerValue,
            trackID: trackID,
            window: normalizedWindow
        )
        do {
            let document = try await Self.documentCache.document(for: cacheKey) {
                let bridgeStartedAt = Date()
                debugLogEmbeddedSubtitleExtractor(
                    "loadDocumentWindow bridge_copy_ass_document_window start trackID=\(trackID) streamIndex=\(streamIndex) window=\(describeWindow(normalizedWindow))"
                )
                return try mediaURL.absoluteString.withCString { mediaURLCString in
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

                        let result = subtitle_bridge_copy_ass_document_window(
                            mediaURLCString,
                            headerCString,
                            Int32(streamIndex),
                            Int64((normalizedWindow.lowerBound * 1000).rounded(.down)),
                            Int64((normalizedWindow.upperBound * 1000).rounded(.up)),
                            &documentPointer,
                            &errorPointer
                        )

                        guard result == 0, let documentPointer else {
                            debugLogEmbeddedSubtitleExtractor(
                                "loadDocumentWindow bridge_copy_ass_document_window failed trackID=\(trackID) window=\(describeWindow(normalizedWindow)) result=\(result) elapsed=\(debugElapsedMilliseconds(since: bridgeStartedAt)) error=\(string(from: errorPointer) ?? "提取内嵌字幕失败。")"
                            )
                            throw EmbeddedSubtitleExtractorError.extractionFailed(string(from: errorPointer) ?? "提取内嵌字幕失败。")
                        }

                        let documentString = String(cString: documentPointer)
                        debugLogEmbeddedSubtitleExtractor(
                            "loadDocumentWindow bridge_copy_ass_document_window succeeded trackID=\(trackID) window=\(describeWindow(normalizedWindow)) bytes=\(documentString.utf8.count) elapsed=\(debugElapsedMilliseconds(since: bridgeStartedAt))"
                        )
                        return .ass(
                            documentString,
                            fileName: "embedded-\(streamIndex).ass"
                        )
                    }
                }
            }
            debugLogEmbeddedSubtitleExtractor(
                "loadDocumentWindow success trackID=\(trackID) window=\(describeWindow(normalizedWindow)) fileName=\(document.fileName ?? "embedded-\(trackID).ass") elapsed=\(debugElapsedMilliseconds(since: startedAt))"
            )
            return document
        } catch {
            debugLogEmbeddedSubtitleExtractor(
                "loadDocumentWindow failed trackID=\(trackID) window=\(describeWindow(normalizedWindow)) elapsed=\(debugElapsedMilliseconds(since: startedAt)) error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    private func makeHeaderValue(_ headers: [String: String]) -> String? {
        guard !headers.isEmpty else { return nil }
        return headers
            .map { "\($0): \($1)" }
            .joined(separator: "\r\n") + "\r\n"
    }

    private func makeCacheKey(
        mediaURL: URL,
        headerValue: String?,
        trackID: SubtitleTrack.ID,
        window: ClosedRange<TimeInterval>?
    ) -> EmbeddedSubtitleDocumentCache.Key {
        EmbeddedSubtitleDocumentCache.Key(
            mediaURL: mediaURL.absoluteString,
            headerValue: headerValue ?? "",
            trackID: trackID,
            windowStartMilliseconds: window.map { Int(($0.lowerBound * 1000).rounded(.down)) },
            windowEndMilliseconds: window.map { Int(($0.upperBound * 1000).rounded(.up)) }
        )
    }

    private func normalizeSubtitleWindow(_ window: ClosedRange<TimeInterval>) -> ClosedRange<TimeInterval> {
        let lowerBound = max(window.lowerBound, 0)
        let upperBound = max(window.upperBound, lowerBound)
        return lowerBound...upperBound
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
        let windowStartMilliseconds: Int?
        let windowEndMilliseconds: Int?
    }

    private var cachedDocuments: [Key: SubtitleDocument] = [:]
    private var inFlightLoads: [Key: Task<SubtitleDocument, Error>] = [:]

    func document(
        for key: Key,
        loader: @escaping @Sendable () async throws -> SubtitleDocument
    ) async throws -> SubtitleDocument {
        if let cachedDocument = cachedDocuments[key] {
            debugLogEmbeddedSubtitleExtractor(
                "documentCache hit trackID=\(key.trackID) url=\(key.mediaURL) window=\(describeWindow(key))"
            )
            return cachedDocument
        }
        if let inFlightLoad = inFlightLoads[key] {
            debugLogEmbeddedSubtitleExtractor(
                "documentCache join in-flight load trackID=\(key.trackID) url=\(key.mediaURL) window=\(describeWindow(key))"
            )
            return try await inFlightLoad.value
        }

        let startedAt = Date()
        debugLogEmbeddedSubtitleExtractor(
            "documentCache miss trackID=\(key.trackID) url=\(key.mediaURL) window=\(describeWindow(key))"
        )
        let task = Task {
            try await loader()
        }
        inFlightLoads[key] = task

        do {
            let document = try await task.value
            cachedDocuments[key] = document
            inFlightLoads[key] = nil
            debugLogEmbeddedSubtitleExtractor(
                "documentCache stored trackID=\(key.trackID) url=\(key.mediaURL) window=\(describeWindow(key)) elapsed=\(debugElapsedMilliseconds(since: startedAt))"
            )
            return document
        } catch {
            inFlightLoads[key] = nil
            debugLogEmbeddedSubtitleExtractor(
                "documentCache failed trackID=\(key.trackID) url=\(key.mediaURL) window=\(describeWindow(key)) elapsed=\(debugElapsedMilliseconds(since: startedAt)) error=\(error.localizedDescription)"
            )
            throw error
        }
    }
}

private func debugLogEmbeddedSubtitleExtractor(_ message: @autoclosure () -> String) {
#if DEBUG
    print("[EmbeddedSubtitleExtractor] \(message())")
#endif
}

private func debugElapsedMilliseconds(since startedAt: Date) -> String {
    String(format: "%.1fms", Date().timeIntervalSince(startedAt) * 1000)
}

private func describeHeaderKeys(_ headers: [String: String]) -> String {
    guard !headers.isEmpty else { return "<none>" }
    return headers.keys.sorted().joined(separator: ",")
}

private func describeTracks(_ tracks: [SubtitleTrack]) -> String {
    guard !tracks.isEmpty else { return "<empty>" }
    return tracks.map { "\($0.id):\($0.displayName)" }.joined(separator: ", ")
}

private func describeWindow(_ window: ClosedRange<TimeInterval>) -> String {
    "\(Int((window.lowerBound * 1000).rounded(.down)))...\(Int((window.upperBound * 1000).rounded(.up)))"
}

private func describeWindow(_ key: EmbeddedSubtitleDocumentCache.Key) -> String {
    guard let start = key.windowStartMilliseconds,
          let end = key.windowEndMilliseconds else {
        return "<full>"
    }
    return "\(start)...\(end)"
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

    func loadDocument(
        for trackID: SubtitleTrack.ID,
        from mediaURL: URL,
        headers: [String: String],
        window: ClosedRange<TimeInterval>
    ) async throws -> SubtitleDocument {
        throw EmbeddedSubtitleExtractorError.unavailable
    }
}
#endif
