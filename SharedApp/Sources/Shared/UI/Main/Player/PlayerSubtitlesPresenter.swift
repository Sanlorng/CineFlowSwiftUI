import Foundation
import ComposableArchitecture
import RemoteMediaLibrary
import SubtitleRendererCore

@Reducer
struct PlayerSubtitlesPresenter {
    @Dependency(\.remoteMediaLibraryClient) var remoteClient
    @Dependency(\.subtitleExtractionClient) var extractor
    @Dependency(\.uuid) var uuid
    @Dependency(\.subtitleLanguagePreferences) var languagePreferences

    private enum CancelID: CaseIterable { case subtitleList, embeddedTracks, subtitleContent, embeddedWindow }
    private var cancelPlaybackEffects: Effect<Action> {
        .merge(CancelID.allCases.map { .cancel(id: $0) })
    }

    @ObservableState
    struct State: Equatable {
        let context: PlaybackAttachmentContext
        var hasLoaded = false
        var hasReceivedBackendTracks = false
        var hasManualSelection = false
        struct LoadedSubtitle: Equatable, Sendable {
            let fileName: String
            let document: SubtitleDocument
        }

        struct EmbeddedSubtitleWindowRequest: Equatable {
            let requestID: UUID
            let trackID: SubtitleTrack.ID
            let window: ClosedRange<TimeInterval>
        }

        struct SubtitleListRequest: Equatable {
            let id: UUID
        }

        struct EmbeddedSubtitleTracksRequest: Equatable {
            let id: UUID
        }

        struct SubtitleContentRequest: Equatable {
            let id: UUID
            let subtitleID: RemoteMediaLibraryClient.Subtitle.ID
        }

        var isLoadingSubtitles = false
        var isLoadingEmbeddedSubtitles = false
        var availableSubtitles: [RemoteMediaLibraryClient.Subtitle] = []
        var availableEmbeddedSubtitles: [SubtitleTrack] = []
        var selectedSubtitle: RemoteMediaLibraryClient.Subtitle?
        var selectedEmbeddedSubtitleTrackID: SubtitleTrack.ID?
        var subtitleError: String?
        var activeSubtitle: LoadedSubtitle?
        var areSubtitlesSuppressed = false
        var isLoadingSelectedSubtitle = false
        var currentPlaybackTime: TimeInterval = 0
        var loadedEmbeddedSubtitleWindow: ClosedRange<TimeInterval>?
        var inFlightEmbeddedSubtitleWindowRequest: EmbeddedSubtitleWindowRequest?
        var subtitleListRequest: SubtitleListRequest?
        var embeddedSubtitleTracksRequest: EmbeddedSubtitleTracksRequest?
        var subtitleContentRequest: SubtitleContentRequest?

        var configuration: MediaLibraryConfiguration { context.configuration }
        var currentItem: PlaybackItem? { context.item }
        var currentFileID: String? { currentItem?.file.id }
        var playbackContextID: UUID { context.id }

        var selectedEmbeddedSubtitle: SubtitleTrack? {
            guard let selectedEmbeddedSubtitleTrackID else { return nil }
            return availableEmbeddedSubtitles.first { $0.id == selectedEmbeddedSubtitleTrackID }
        }

        var canAutomaticallySelect: Bool {
            !hasManualSelection && !areSubtitlesSuppressed && !isLoadingSelectedSubtitle
                && selectedSubtitle == nil && selectedEmbeddedSubtitleTrackID == nil && activeSubtitle == nil
        }
    }

    enum Action: Equatable {
        case load
        case stop
        case playbackTimeUpdated(TimeInterval)
        case playerTracksChanged([PlayerTrack])
        case subtitleListResponse(UUID, TaskResult<[RemoteMediaLibraryClient.Subtitle]>)
        case embeddedSubtitleTracksResponse(UUID, TaskResult<[SubtitleTrack]>)
        case subtitleSelected(RemoteMediaLibraryClient.Subtitle)
        case automaticallySelectExternalSubtitle(RemoteMediaLibraryClient.Subtitle)
        case subtitleContentResponse(UUID, RemoteMediaLibraryClient.Subtitle, TaskResult<State.LoadedSubtitle>)
        case localSubtitleLoaded(fileName: String, content: String)
        case localSubtitleLoadFailed(String)
        case embeddedSubtitleSelected(SubtitleTrack.ID)
        case automaticallySelectEmbeddedSubtitle(SubtitleTrack.ID)
        case embeddedSubtitleContentResponse(SubtitleTrack.ID, UUID, ClosedRange<TimeInterval>, TaskResult<State.LoadedSubtitle>)
        case subtitleCleared
        case setSubtitlesSuppressed(Bool)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .load:
                guard !state.hasLoaded else { return .none }
                state.hasLoaded = true
                return loadSubtitles(for: &state)
            case .stop:
                state.hasLoaded = false
                state.subtitleListRequest = nil
                state.embeddedSubtitleTracksRequest = nil
                state.subtitleContentRequest = nil
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                state.isLoadingSubtitles = false
                state.isLoadingEmbeddedSubtitles = false
                state.isLoadingSelectedSubtitle = false
                return cancelPlaybackEffects
            case let .playbackTimeUpdated(playbackTime):
                state.currentPlaybackTime = max(playbackTime, 0)
                return refreshEmbeddedSubtitleWindowIfNeeded(for: &state, force: false)

            case let .playerTracksChanged(tracks):
                debugLogPlayerFlow(
                    "playerTracksChanged fileID=\(state.currentFileID ?? "<none>") total=\(tracks.count) audio=\(tracks.filter { $0.kind == .audio }.count) subtitle=\(tracks.filter { $0.kind == .subtitle }.count)"
                )
                state.isLoadingEmbeddedSubtitles = false
                state.hasReceivedBackendTracks = true
                let backendSubtitleTracks = tracks
                    .filter { $0.kind == .subtitle && !$0.isExternal }
                    .compactMap(makeEmbeddedSubtitleTrack(from:))
                state.availableEmbeddedSubtitles = mergeEmbeddedSubtitleTracks(
                    existing: state.availableEmbeddedSubtitles,
                    incoming: backendSubtitleTracks,
                    preferIncoming: false
                )
                if !backendSubtitleTracks.isEmpty {
                    debugLogEmbeddedSubtitlePlayback(
                        "backend track list updated fileID=\(state.currentFileID ?? "<none>") count=\(backendSubtitleTracks.count) tracks=[\(describeEmbeddedSubtitleTracks(backendSubtitleTracks))]"
                    )
                }
                if let selectedEmbeddedSubtitleTrackID = state.selectedEmbeddedSubtitleTrackID,
                   state.availableEmbeddedSubtitles.contains(where: { $0.id == selectedEmbeddedSubtitleTrackID }) == false {
                    state.selectedEmbeddedSubtitleTrackID = nil
                }
                return autoSelectSubtitleIfNeeded(for: &state)

            case let .subtitleListResponse(requestID, .success(subtitles)):
                guard state.subtitleListRequest?.id == requestID else {
                    debugLogPlayerFlow(
                        "subtitleListResponse ignored requestID=\(requestID) expected=\(state.subtitleListRequest?.id.uuidString ?? "<none>") currentFileID=\(state.currentFileID ?? "<none>")"
                    )
                    return .none
                }
                debugLogPlayerFlow(
                    "subtitleListResponse success requestID=\(requestID) count=\(subtitles.count) fileID=\(state.currentFileID ?? "<none>")"
                )
                state.isLoadingSubtitles = false
                state.subtitleListRequest = nil
                state.availableSubtitles = subtitles
                state.subtitleError = nil
                return autoSelectSubtitleIfNeeded(for: &state)

            case let .subtitleListResponse(requestID, .failure(error)):
                guard state.subtitleListRequest?.id == requestID else {
                    debugLogPlayerFlow(
                        "subtitleListResponse failure ignored requestID=\(requestID) expected=\(state.subtitleListRequest?.id.uuidString ?? "<none>") currentFileID=\(state.currentFileID ?? "<none>") error=\(error.localizedDescription)"
                    )
                    return .none
                }
                debugLogPlayerFlow(
                    "subtitleListResponse failure requestID=\(requestID) fileID=\(state.currentFileID ?? "<none>") error=\(error.localizedDescription)"
                )
                state.isLoadingSubtitles = false
                state.subtitleListRequest = nil
                state.availableSubtitles = []
                state.subtitleError = error.localizedDescription
                return autoSelectSubtitleIfNeeded(for: &state)

            case let .embeddedSubtitleTracksResponse(requestID, .success(tracks)):
                guard state.embeddedSubtitleTracksRequest?.id == requestID else {
                    debugLogPlayerFlow(
                        "embeddedSubtitleTracksResponse ignored requestID=\(requestID) expected=\(state.embeddedSubtitleTracksRequest?.id.uuidString ?? "<none>") currentFileID=\(state.currentFileID ?? "<none>")"
                    )
                    return .none
                }
                debugLogPlayerFlow(
                    "embeddedSubtitleTracksResponse success requestID=\(requestID) count=\(tracks.count) fileID=\(state.currentFileID ?? "<none>")"
                )
                state.isLoadingEmbeddedSubtitles = false
                state.embeddedSubtitleTracksRequest = nil
                state.availableEmbeddedSubtitles = mergeEmbeddedSubtitleTracks(
                    existing: state.availableEmbeddedSubtitles,
                    incoming: tracks,
                    preferIncoming: true
                )
                debugLogEmbeddedSubtitlePlayback(
                    "extractor track list loaded requestID=\(requestID) count=\(tracks.count) tracks=[\(describeEmbeddedSubtitleTracks(tracks))]"
                )
                if let selectedEmbeddedSubtitleTrackID = state.selectedEmbeddedSubtitleTrackID,
                   state.availableEmbeddedSubtitles.contains(where: { $0.id == selectedEmbeddedSubtitleTrackID }) == false {
                    state.selectedEmbeddedSubtitleTrackID = nil
                }
                state.subtitleError = nil
                return autoSelectSubtitleIfNeeded(for: &state)

            case let .embeddedSubtitleTracksResponse(requestID, .failure(error)):
                guard state.embeddedSubtitleTracksRequest?.id == requestID else {
                    debugLogPlayerFlow(
                        "embeddedSubtitleTracksResponse failure ignored requestID=\(requestID) expected=\(state.embeddedSubtitleTracksRequest?.id.uuidString ?? "<none>") currentFileID=\(state.currentFileID ?? "<none>") error=\(error.localizedDescription)"
                    )
                    return .none
                }
                debugLogPlayerFlow(
                    "embeddedSubtitleTracksResponse failure requestID=\(requestID) fileID=\(state.currentFileID ?? "<none>") error=\(error.localizedDescription)"
                )
                state.isLoadingEmbeddedSubtitles = false
                state.embeddedSubtitleTracksRequest = nil
                state.availableEmbeddedSubtitles = []
                debugLogEmbeddedSubtitlePlayback(
                    "extractor track list failed requestID=\(requestID) error=\(error.localizedDescription)"
                )
                state.subtitleError = error.localizedDescription
                return autoSelectSubtitleIfNeeded(for: &state)

            case let .subtitleSelected(subtitle), let .automaticallySelectExternalSubtitle(subtitle):
                if case .automaticallySelectExternalSubtitle = action {
                    guard state.canAutomaticallySelect else { return .none }
                } else {
                    state.hasManualSelection = true
                }
                guard let currentItem = state.currentItem,
                      let fileID = currentItem.file.id,
                      !fileID.isEmpty else {
                    return .none
                }
                guard let baseURL = state.configuration.baseURL else {
                    state.subtitleError = "媒体库地址无效。"
                    return .none
                }
                state.areSubtitlesSuppressed = false
                state.selectedSubtitle = subtitle
                state.selectedEmbeddedSubtitleTrackID = nil
                state.subtitleError = nil
                state.activeSubtitle = nil
                state.isLoadingSelectedSubtitle = true
                state.loadedEmbeddedSubtitleWindow = nil
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                let requestID = uuid()
                state.subtitleContentRequest = .init(id: requestID, subtitleID: subtitle.id)
                debugLogPlayerFlow(
                    "subtitleSelected fileID=\(fileID) subtitleID=\(subtitle.id) requestID=\(requestID) fileName=\(subtitle.fileName)"
                )
                let token = state.configuration.apiToken
                return .run { [remoteClient] send in
                    await send(
                        .subtitleContentResponse(
                            requestID,
                            subtitle,
                            TaskResult {
                                let content = try await remoteClient.fetchSubtitleFile(baseURL, token, fileID, subtitle.fileName)
                                return try makeLoadedSubtitle(rawText: content, fileName: subtitle.fileName)
                            }
                        )
                    )
                }
                .cancellable(id: CancelID.subtitleContent, cancelInFlight: true)
                .merge(with: .cancel(id: CancelID.embeddedWindow))

            case let .subtitleContentResponse(requestID, subtitle, .success(loadedSubtitle)):
                guard state.subtitleContentRequest == .init(id: requestID, subtitleID: subtitle.id) else {
                    debugLogPlayerFlow(
                        "subtitleContentResponse success ignored requestID=\(requestID) subtitleID=\(subtitle.id) expectedRequest=\(state.subtitleContentRequest?.id.uuidString ?? "<none>") expectedSubtitleID=\(state.subtitleContentRequest?.subtitleID ?? "<none>") currentFileID=\(state.currentFileID ?? "<none>")"
                    )
                    return .none
                }
                debugLogPlayerFlow(
                    "subtitleContentResponse success requestID=\(requestID) subtitleID=\(subtitle.id) fileID=\(state.currentFileID ?? "<none>") fileName=\(loadedSubtitle.fileName)"
                )
                state.isLoadingSelectedSubtitle = false
                state.subtitleContentRequest = nil
                state.subtitleError = nil
                state.activeSubtitle = loadedSubtitle
                return .none

            case let .subtitleContentResponse(requestID, subtitle, .failure(error)):
                guard state.subtitleContentRequest == .init(id: requestID, subtitleID: subtitle.id) else {
                    debugLogPlayerFlow(
                        "subtitleContentResponse failure ignored requestID=\(requestID) subtitleID=\(subtitle.id) expectedRequest=\(state.subtitleContentRequest?.id.uuidString ?? "<none>") expectedSubtitleID=\(state.subtitleContentRequest?.subtitleID ?? "<none>") currentFileID=\(state.currentFileID ?? "<none>") error=\(error.localizedDescription)"
                    )
                    return .none
                }
                debugLogPlayerFlow(
                    "subtitleContentResponse failure requestID=\(requestID) subtitleID=\(subtitle.id) fileID=\(state.currentFileID ?? "<none>") error=\(error.localizedDescription)"
                )
                state.isLoadingSelectedSubtitle = false
                state.subtitleContentRequest = nil
                state.subtitleError = error.localizedDescription
                state.activeSubtitle = nil
                return .none

            case let .localSubtitleLoaded(fileName, content):
                state.hasManualSelection = true
                state.areSubtitlesSuppressed = false
                state.selectedSubtitle = nil
                state.selectedEmbeddedSubtitleTrackID = nil
                state.subtitleError = nil
                state.isLoadingSelectedSubtitle = false
                state.loadedEmbeddedSubtitleWindow = nil
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                state.subtitleContentRequest = nil
                do {
                    state.activeSubtitle = try makeLoadedSubtitle(rawText: content, fileName: fileName)
                } catch {
                    state.activeSubtitle = nil
                    state.subtitleError = error.localizedDescription
                }
                return .merge(.cancel(id: CancelID.subtitleContent), .cancel(id: CancelID.embeddedWindow))

            case let .localSubtitleLoadFailed(message):
                state.subtitleError = message
                return .none

            case let .embeddedSubtitleSelected(trackID), let .automaticallySelectEmbeddedSubtitle(trackID):
                let isAutomatic: Bool
                if case .automaticallySelectEmbeddedSubtitle = action {
                    guard state.canAutomaticallySelect else { return .none }
                    isAutomatic = true
                } else {
                    isAutomatic = false
                }
                guard state.availableEmbeddedSubtitles.contains(where: { $0.id == trackID }),
                      let currentItem = state.currentItem,
                      let fileID = currentItem.file.id,
                      !fileID.isEmpty else {
                    return .none
                }
                let selectedTrack = state.availableEmbeddedSubtitles.first { $0.id == trackID }
                if !isAutomatic {
                    state.hasManualSelection = true
                    if let selectedTrack, let key = SubtitleLanguagePreferences.key(for: selectedTrack) {
                        languagePreferences.remember(key)
                    }
                }
                state.areSubtitlesSuppressed = false
                state.selectedSubtitle = nil
                state.selectedEmbeddedSubtitleTrackID = trackID
                state.subtitleError = nil
                state.activeSubtitle = nil
                state.loadedEmbeddedSubtitleWindow = nil
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                state.subtitleContentRequest = nil
                let usesNativeEmbeddedSubtitleSelection =
                    state.context.capabilities.contains(.embeddedSubtitleTracks)
                    && selectedTrack?.backendTrackID != nil
                state.isLoadingSelectedSubtitle = !usesNativeEmbeddedSubtitleSelection

                if usesNativeEmbeddedSubtitleSelection {
                    debugLogEmbeddedSubtitlePlayback(
                        "embedded subtitle selected for native backend fileID=\(fileID) trackID=\(trackID) backendTrackID=\(selectedTrack?.backendTrackID ?? "<none>")"
                    )
                    return .merge(.cancel(id: CancelID.subtitleContent), .cancel(id: CancelID.embeddedWindow))
                }

                debugLogEmbeddedSubtitlePlayback(
                    "embedded subtitle selected fileID=\(fileID) trackID=\(trackID) streamURL=\(currentItem.stream.url.absoluteString)"
                )
                return refreshEmbeddedSubtitleWindowIfNeeded(for: &state, force: true)
                    .merge(with: .cancel(id: CancelID.subtitleContent))

            case let .embeddedSubtitleContentResponse(trackID, requestID, window, .success(loadedSubtitle)):
                guard state.selectedEmbeddedSubtitleTrackID == trackID,
                      state.inFlightEmbeddedSubtitleWindowRequest?.requestID == requestID else {
                    debugLogPlayerFlow(
                        "embeddedSubtitleContentResponse success ignored requestID=\(requestID) trackID=\(trackID) selectedTrackID=\(state.selectedEmbeddedSubtitleTrackID ?? "<none>") expectedRequest=\(state.inFlightEmbeddedSubtitleWindowRequest?.requestID.uuidString ?? "<none>") currentFileID=\(state.currentFileID ?? "<none>")"
                    )
                    return .none
                }
                debugLogPlayerFlow(
                    "embeddedSubtitleContentResponse success requestID=\(requestID) trackID=\(trackID) fileID=\(state.currentFileID ?? "<none>") window=\(describeEmbeddedSubtitleWindow(window))"
                )
                state.isLoadingSelectedSubtitle = false
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                state.loadedEmbeddedSubtitleWindow = window
                debugLogEmbeddedSubtitlePlayback(
                    "embedded subtitle render attached fileID=\(state.currentFileID ?? "<none>") trackID=\(trackID) window=\(describeEmbeddedSubtitleWindow(window)) fileName=\(loadedSubtitle.fileName)"
                )
                state.subtitleError = nil
                state.activeSubtitle = loadedSubtitle
                return .none

            case let .embeddedSubtitleContentResponse(trackID, requestID, window, .failure(error)):
                guard state.selectedEmbeddedSubtitleTrackID == trackID,
                      state.inFlightEmbeddedSubtitleWindowRequest?.requestID == requestID else {
                    debugLogPlayerFlow(
                        "embeddedSubtitleContentResponse failure ignored requestID=\(requestID) trackID=\(trackID) selectedTrackID=\(state.selectedEmbeddedSubtitleTrackID ?? "<none>") expectedRequest=\(state.inFlightEmbeddedSubtitleWindowRequest?.requestID.uuidString ?? "<none>") currentFileID=\(state.currentFileID ?? "<none>") error=\(error.localizedDescription)"
                    )
                    return .none
                }
                debugLogPlayerFlow(
                    "embeddedSubtitleContentResponse failure requestID=\(requestID) trackID=\(trackID) fileID=\(state.currentFileID ?? "<none>") error=\(error.localizedDescription)"
                )
                state.isLoadingSelectedSubtitle = false
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                debugLogEmbeddedSubtitlePlayback(
                    "embedded subtitle render failed fileID=\(state.currentFileID ?? "<none>") trackID=\(trackID) window=\(describeEmbeddedSubtitleWindow(window)) error=\(error.localizedDescription)"
                )
                state.subtitleError = error.localizedDescription
                state.activeSubtitle = nil
                return .none

            case .subtitleCleared:
                state.hasManualSelection = true
                state.selectedSubtitle = nil
                state.selectedEmbeddedSubtitleTrackID = nil
                state.activeSubtitle = nil
                state.subtitleError = nil
                state.areSubtitlesSuppressed = true
                state.isLoadingSelectedSubtitle = false
                state.loadedEmbeddedSubtitleWindow = nil
                state.inFlightEmbeddedSubtitleWindowRequest = nil
                state.subtitleContentRequest = nil
                return .merge(.cancel(id: CancelID.subtitleContent), .cancel(id: CancelID.embeddedWindow))

            case let .setSubtitlesSuppressed(suppressed):
                state.areSubtitlesSuppressed = suppressed
                if suppressed {
                    state.selectedSubtitle = nil
                    state.selectedEmbeddedSubtitleTrackID = nil
                    state.activeSubtitle = nil
                    state.isLoadingSelectedSubtitle = false
                    state.loadedEmbeddedSubtitleWindow = nil
                    state.inFlightEmbeddedSubtitleWindowRequest = nil
                    state.subtitleContentRequest = nil
                }
                state.subtitleError = nil
                return suppressed ? .merge(.cancel(id: CancelID.subtitleContent), .cancel(id: CancelID.embeddedWindow)) : .none
            }
        }
    }

    private func loadSubtitles(for state: inout State) -> Effect<Action> {
        state.subtitleListRequest = nil
        state.embeddedSubtitleTracksRequest = nil
        state.subtitleContentRequest = nil
        debugLogPlayerFlow(
            "loadSubtitles reset contextID=\(state.playbackContextID) nextFileID=\(state.currentItem?.file.id ?? "<none>") playbackContextID=\(state.playbackContextID)"
        )

        guard let currentItem = state.currentItem,
              let fileID = currentItem.file.id,
              !fileID.isEmpty else {
            debugLogPlayerFlow("loadSubtitles aborted missing fileID contextID=\(state.playbackContextID)")
            state.availableSubtitles = []
            state.availableEmbeddedSubtitles = []
            state.selectedSubtitle = nil
            state.selectedEmbeddedSubtitleTrackID = nil
            state.activeSubtitle = nil
            state.isLoadingSubtitles = false
            state.isLoadingEmbeddedSubtitles = false
            state.areSubtitlesSuppressed = false
            state.isLoadingSelectedSubtitle = false
            state.currentPlaybackTime = 0
            state.loadedEmbeddedSubtitleWindow = nil
            state.inFlightEmbeddedSubtitleWindowRequest = nil
            return cancelPlaybackEffects
        }
        let stream = currentItem.stream
        let prefersBackendEmbeddedTracks = state.context.capabilities.contains(.embeddedSubtitleTracks)
        state.isLoadingSubtitles = state.configuration.baseURL != nil
        state.isLoadingEmbeddedSubtitles = prefersBackendEmbeddedTracks && !state.hasReceivedBackendTracks
        state.availableSubtitles = []
        if !state.hasManualSelection {
            state.selectedSubtitle = nil
            state.selectedEmbeddedSubtitleTrackID = nil
            state.activeSubtitle = nil
            state.subtitleError = nil
            state.areSubtitlesSuppressed = false
            state.isLoadingSelectedSubtitle = false
        }
        state.currentPlaybackTime = 0
        state.loadedEmbeddedSubtitleWindow = nil
        state.inFlightEmbeddedSubtitleWindowRequest = nil

        let subtitleListEffect: Effect<Action>
        if let baseURL = state.configuration.baseURL {
            let requestID = uuid()
            state.subtitleListRequest = .init(id: requestID)
            debugLogPlayerFlow(
                "subtitleList request created requestID=\(requestID) fileID=\(fileID)"
            )
            let token = state.configuration.apiToken
            subtitleListEffect = .run { [remoteClient] send in
                await send(
                    .subtitleListResponse(
                        requestID,
                        TaskResult {
                            try await remoteClient.fetchSubtitleInfo(baseURL, token, fileID)
                        }
                    )
                )
            }
            .cancellable(id: CancelID.subtitleList, cancelInFlight: true)
        } else {
            subtitleListEffect = .none
        }

        let embeddedTracksEffect: Effect<Action>
        if prefersBackendEmbeddedTracks {
            embeddedTracksEffect = .none
        } else {
            state.isLoadingEmbeddedSubtitles = true
            let requestID = uuid()
            state.embeddedSubtitleTracksRequest = .init(id: requestID)
            debugLogPlayerFlow(
                "embeddedSubtitleTracks request created requestID=\(requestID) fileID=\(fileID) streamURL=\(stream.url.absoluteString)"
            )
            embeddedTracksEffect = .run { [extractor] send in
                debugLogEmbeddedSubtitlePlayback(
                    "extractor track scan start fileID=\(fileID) streamURL=\(stream.url.absoluteString)"
                )
                await send(
                    .embeddedSubtitleTracksResponse(
                        requestID,
                        TaskResult {
                            try await extractor.availableTracks(stream.url, stream.headers)
                        }
                    )
                )
            }
            .cancellable(id: CancelID.embeddedTracks, cancelInFlight: true)
        }

        return .concatenate(
            cancelPlaybackEffects,
            .merge(subtitleListEffect, embeddedTracksEffect, autoSelectSubtitleIfNeeded(for: &state))
        )
    }

    private func refreshEmbeddedSubtitleWindowIfNeeded(
        for state: inout State,
        force: Bool
    ) -> Effect<Action> {
        guard let currentItem = state.currentItem,
              let selectedTrackID = state.selectedEmbeddedSubtitleTrackID,
              let selectedTrack = state.availableEmbeddedSubtitles.first(where: { $0.id == selectedTrackID }),
              !state.areSubtitlesSuppressed,
              state.selectedSubtitle == nil else {
            return .none
        }

        let usesNativeEmbeddedSubtitleSelection =
            state.context.capabilities.contains(.embeddedSubtitleTracks)
            && selectedTrack.backendTrackID != nil
        guard !usesNativeEmbeddedSubtitleSelection else {
            return .none
        }

        let targetWindow = embeddedSubtitleWindow(around: state.currentPlaybackTime)

        if !force {
            if let inFlightRequest = state.inFlightEmbeddedSubtitleWindowRequest,
               inFlightRequest.trackID == selectedTrackID,
               inFlightRequest.window.contains(state.currentPlaybackTime) {
                return .none
            }

            if let loadedWindow = state.loadedEmbeddedSubtitleWindow,
               state.activeSubtitle != nil,
               embeddedSubtitleWindowStillValid(loadedWindow, for: state.currentPlaybackTime) {
                return .none
            }
        }

        let requestID = uuid()
        state.isLoadingSelectedSubtitle = true
        state.subtitleError = nil
        state.inFlightEmbeddedSubtitleWindowRequest = .init(
            requestID: requestID,
            trackID: selectedTrackID,
            window: targetWindow
        )
        debugLogPlayerFlow(
            "embeddedSubtitleWindow request created requestID=\(requestID) fileID=\(currentItem.file.id ?? "<none>") trackID=\(selectedTrackID) window=\(describeEmbeddedSubtitleWindow(targetWindow))"
        )

        let stream = currentItem.stream
        let fileID = currentItem.file.id ?? "<none>"
        debugLogEmbeddedSubtitlePlayback(
            "load embedded subtitle window start fileID=\(fileID) trackID=\(selectedTrackID) window=\(describeEmbeddedSubtitleWindow(targetWindow)) streamURL=\(stream.url.absoluteString)"
        )
        return .run { [extractor] send in
            await send(
                .embeddedSubtitleContentResponse(
                    selectedTrackID,
                    requestID,
                    targetWindow,
                    TaskResult {
                        let document = try await extractor.loadWindow(
                            selectedTrackID,
                            stream.url,
                            stream.headers,
                            targetWindow
                        )
                        debugLogEmbeddedSubtitlePlayback(
                            "embedded subtitle window document ready fileID=\(fileID) trackID=\(selectedTrackID) window=\(describeEmbeddedSubtitleWindow(targetWindow)) fileName=\(document.fileName ?? "embedded-\(selectedTrackID).ass")"
                        )
                        let loadedSubtitle = makeLoadedSubtitle(
                            document: document,
                            fallbackFileName: "embedded-\(selectedTrackID).ass"
                        )
                        debugLogEmbeddedSubtitlePlayback(
                            "embedded subtitle render payload ready fileID=\(fileID) trackID=\(selectedTrackID) window=\(describeEmbeddedSubtitleWindow(targetWindow)) fileName=\(loadedSubtitle.fileName)"
                        )
                        return loadedSubtitle
                    }
                )
            )
        }
        .cancellable(id: CancelID.embeddedWindow, cancelInFlight: true)
    }

    private func autoSelectSubtitleIfNeeded(for state: inout State) -> Effect<Action> {
        guard state.canAutomaticallySelect else { return .none }
        let queue = languagePreferences.read()
        if !queue.isEmpty {
            // Do not let an earlier external-subtitle response bypass the queue
            // while the embedded track scan is still in flight.
            guard !state.isLoadingEmbeddedSubtitles else { return .none }
            if let track = SubtitleLanguagePreferences.preferredTrack(in: state.availableEmbeddedSubtitles, queue: queue) {
                return .send(.automaticallySelectEmbeddedSubtitle(track.id))
            }
        }

        if !state.isLoadingEmbeddedSubtitles,
           let embeddedSubtitle = state.availableEmbeddedSubtitles.first {
            return .send(.automaticallySelectEmbeddedSubtitle(embeddedSubtitle.id))
        }

        if !state.isLoadingSubtitles,
           let externalSubtitle = state.availableSubtitles.first {
            return .send(.automaticallySelectExternalSubtitle(externalSubtitle))
        }

        return .none
    }
}

private enum PlayerSubtitleLoadError: LocalizedError {
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(fileName):
            return "暂不支持渲染字幕文件：\(fileName)"
        }
    }
}

private func makeLoadedSubtitle(rawText: String, fileName: String) throws -> PlayerSubtitlesPresenter.State.LoadedSubtitle {
    guard let document = SubtitleDocument.detecting(rawText: rawText, fileName: fileName) else {
        throw PlayerSubtitleLoadError.unsupportedFormat(fileName)
    }
    return .init(fileName: fileName, document: document)
}

private func makeLoadedSubtitle(
    document: SubtitleDocument,
    fallbackFileName: String
) -> PlayerSubtitlesPresenter.State.LoadedSubtitle {
    .init(
        fileName: document.fileName ?? fallbackFileName,
        document: document
    )
}

private func makeEmbeddedSubtitleTrack(from track: PlayerTrack) -> SubtitleTrack? {
    let trackID: String
    if let streamIndex = track.streamIndex {
        trackID = String(streamIndex)
    } else if Int(track.id) != nil {
        trackID = track.id
    } else {
        return nil
    }

    return SubtitleTrack(
        id: trackID,
        displayName: track.displayName,
        language: track.language,
        formatHint: subtitleFormatHint(for: track.codec),
        kind: .embedded,
        backendTrackID: track.id
    )
}

private func subtitleFormatHint(for codec: String?) -> SubtitleFormat? {
    guard let codec = codec?.lowercased() else { return nil }
    switch codec {
    case "ass", "ssa":
        return .ass
    case "subrip", "srt", "mov_text", "text":
        return .srt
    case "webvtt":
        return .webvtt
    default:
        return nil
    }
}

private func mergeEmbeddedSubtitleTracks(
    existing: [SubtitleTrack],
    incoming: [SubtitleTrack],
    preferIncoming: Bool
) -> [SubtitleTrack] {
    var merged: [String: SubtitleTrack] = [:]

    for track in preferIncoming ? existing : incoming {
        merged[track.id] = track
    }
    for track in preferIncoming ? incoming : existing {
        merged[track.id] = track
    }

    return merged.values.sorted { lhs, rhs in
        let lhsID = Int(lhs.id) ?? .max
        let rhsID = Int(rhs.id) ?? .max
        if lhsID != rhsID {
            return lhsID < rhsID
        }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}

private func debugLogEmbeddedSubtitlePlayback(_ message: @autoclosure () -> String) {
#if DEBUG
    print("[PlayerPresenter][EmbeddedSubtitle] \(message())")
#endif
}

private func debugLogPlayerFlow(_ message: @autoclosure () -> String) {
#if DEBUG
    print("[PlayerPresenter][Flow] \(message())")
#endif
}

private func describeEmbeddedSubtitleTracks(_ tracks: [SubtitleTrack]) -> String {
    guard !tracks.isEmpty else { return "<empty>" }
    return tracks.map { "\($0.id):\($0.displayName)" }.joined(separator: ", ")
}

private func embeddedSubtitleWindow(around playbackTime: TimeInterval) -> ClosedRange<TimeInterval> {
    let lookBehind: TimeInterval = 20
    let lookAhead: TimeInterval = 180
    let lowerBound = max(playbackTime - lookBehind, 0)
    let upperBound = max(playbackTime + lookAhead, lowerBound + 30)
    return lowerBound...upperBound
}

private func embeddedSubtitleWindowStillValid(
    _ window: ClosedRange<TimeInterval>,
    for playbackTime: TimeInterval
) -> Bool {
    let safeLeadingPadding: TimeInterval = 10
    let safeTrailingPadding: TimeInterval = 45
    return playbackTime >= window.lowerBound + safeLeadingPadding
        && playbackTime <= window.upperBound - safeTrailingPadding
}

private func describeEmbeddedSubtitleWindow(_ window: ClosedRange<TimeInterval>) -> String {
    "\(Int((window.lowerBound * 1000).rounded(.down)))...\(Int((window.upperBound * 1000).rounded(.up)))"
}
