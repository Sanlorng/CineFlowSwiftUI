import Foundation
import RemoteMediaLibrary

enum PlaylistBuilder {
    static func build(
        detail: Components.Schemas.LibraryBangumiDetailsResponse,
        baseURL: URL,
        token: String?,
        configuration: MediaLibraryConfiguration,
        seriesTitle: String?,
        coverURL: URL?,
        selectedEpisode: Components.Schemas.LibraryBangumiEpisode,
        selectedFile: Components.Schemas.LibraryBangumiMatchedFile,
        makeStream: (URL, String?, String) -> RemoteMediaLibraryClient.StreamContext
    ) throws -> PlaybackRequest {
        guard let episodes = detail.episodes, !episodes.isEmpty else {
            throw PlaybackPreparationError.missingEpisodes
        }

        let referenceName = selectedFile.name ?? selectedFile.path ?? ""

        let episodeFiles = Dictionary(
            uniqueKeysWithValues: episodes.compactMap { episode -> (Components.Schemas.LibraryBangumiEpisode, [Components.Schemas.LibraryBangumiMatchedFile])? in
                guard let files = episode.localMatchedFiles, !files.isEmpty else {
                    return nil
                }
                return (episode, files)
            }
        )

        var playlistItems: [PlaybackItem] = []
        var currentIndex = 0

        for episode in episodes {
            guard let files = episodeFiles[episode] else { continue }

            let chosenFile: Components.Schemas.LibraryBangumiMatchedFile
            if episode == selectedEpisode {
                chosenFile = selectedFile
            } else if files.count == 1 {
                chosenFile = files[0]
            } else {
                chosenFile = bestMatchingFile(
                    referenceName: referenceName,
                    files: files
                ) ?? files[0]
            }

            guard let fileID = chosenFile.id, !fileID.isEmpty else {
                throw PlaybackPreparationError.missingStream("文件 \(chosenFile.name ?? "未知") 缺少标识符。")
            }

            let stream = makeStream(baseURL, token, fileID)
            let item = PlaybackItem(
                episode: episode,
                file: chosenFile,
                stream: stream
            )
            if episode == selectedEpisode {
                currentIndex = playlistItems.count
            }
            playlistItems.append(item)
        }

        guard !playlistItems.isEmpty else {
            throw PlaybackPreparationError.missingEpisodes
        }

        return PlaybackRequest(
            id: UUID(),
            configuration: configuration,
            seriesTitle: seriesTitle,
            coverURL: coverURL,
            playlist: playlistItems,
            currentIndex: currentIndex,
            allEpisodeFiles: episodeFiles
        )
    }

    private static func bestMatchingFile(
        referenceName: String,
        files: [Components.Schemas.LibraryBangumiMatchedFile]
    ) -> Components.Schemas.LibraryBangumiMatchedFile? {
        guard !referenceName.isEmpty else {
            return files.first
        }

        let loweredReference = referenceName.lowercased()
        return files.max { lhs, rhs in
            similarity(
                loweredReference,
                lhs.name?.lowercased() ?? lhs.path?.lowercased() ?? ""
            ) < similarity(
                loweredReference,
                rhs.name?.lowercased() ?? rhs.path?.lowercased() ?? ""
            )
        }
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let distance = levenshtein(lhs, rhs)
        let maxCount = max(lhs.count, rhs.count)
        if maxCount == 0 { return 1 }
        return 1 - (Double(distance) / Double(maxCount))
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhsArray = Array(lhs)
        let rhsArray = Array(rhs)
        let lhsCount = lhsArray.count
        let rhsCount = rhsArray.count

        var distances = Array(repeating: Array(repeating: 0, count: rhsCount + 1), count: lhsCount + 1)

        for i in 0...lhsCount {
            distances[i][0] = i
        }
        for j in 0...rhsCount {
            distances[0][j] = j
        }

        for i in 1...lhsCount {
            for j in 1...rhsCount {
                let cost = lhsArray[i - 1] == rhsArray[j - 1] ? 0 : 1
                distances[i][j] = min(
                    distances[i - 1][j] + 1,
                    distances[i][j - 1] + 1,
                    distances[i - 1][j - 1] + cost
                )
            }
        }

        return distances[lhsCount][rhsCount]
    }
}

enum PlaybackPreparationError: Error {
    case missingEpisodes
    case missingStream(String)
}
