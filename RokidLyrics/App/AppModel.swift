import Foundation
import Observation
import RokidLyricsCore
import RokidLyricsServices

enum AppTab: Hashable {
    case home
    case nowPlaying
    case connection
    case search
    case settings
}

@MainActor
@Observable
final class AppModel {
    var settings: AppSettings

    var selectedTab: AppTab = .home
    private(set) var synchronizationState: LyricsSynchronizationState = .idle
    private(set) var connectionState: RokidConnectionState = .disconnected
    private(set) var currentTrack: TrackIdentity?
    private(set) var timelinePosition: LyricTimelinePosition?
    private(set) var playbackPosition: TimeInterval = 0
    private(set) var syncOffsetSeconds: TimeInterval = 0
    private(set) var isMicrophoneActive = false
    private(set) var currentDisplayModel: GlassesDisplayModel?
    private(set) var lastGlassesPayload: GlassesDisplayModel?
    private(set) var providerResultSummary = "No request yet"
    private(set) var lastError: String?
    private(set) var statusMessage = "Ready"
    private(set) var searchResults: [ScoredLyricsCandidate] = []
    private(set) var isSearching = false
    var manualSearchTitle = ""
    var manualSearchArtist = ""
    var pendingSharedURL: URL?

    private var audioCapture: any AudioCaptureService
    private let identificationService: any TrackIdentificationService
    private let lyricsProvider: any LyricsProvider
    private let scorer: LyricsMatchScorer
    private let parser: LRCParser
    private let engine: LyricsSynchronizationEngine
    private let sharedInbox: SharedTrackInbox
    private var transport: any RokidDisplayTransport
    #if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
        private var rokidCoordinator: RokidCXRCoordinator?
    #endif

    private var pipelineTask: Task<Void, Never>?
    private var displayTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var lastTransportContent: TransportContent?
    private var lastTransportSendTime: TimeInterval = 0
    private var lastReconnectAttemptTime: TimeInterval = 0
    /// Automatic Shazam ambiguity keeps the recognition clock; a new manual or
    /// shared search must not accidentally reuse stale recognized metadata.
    private var searchSelectionUsesIdentifiedTrack = false

    init(
        settings: AppSettings? = nil,
        audioCapture: (any AudioCaptureService)? = nil,
        identificationService: (any TrackIdentificationService)? = nil,
        lyricsProvider: (any LyricsProvider)? = nil,
        engine: LyricsSynchronizationEngine? = nil,
        sharedInbox: SharedTrackInbox? = nil,
        transport: (any RokidDisplayTransport)? = nil
    ) {
        let settings = settings ?? AppSettings()
        let cacheRoot =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let cache = DiskLyricsCache(
            directoryURL: cacheRoot.appendingPathComponent("RokidLyrics/LRCLIB", isDirectory: true)
        )
        let correctionStore = UserDefaultsSyncCorrectionStore()

        self.settings = settings

        #if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
            var resolvedCoordinator: RokidCXRCoordinator?
            var adapterInitializationError: String?
            if audioCapture == nil, transport == nil, !settings.mockMode {
                do {
                    resolvedCoordinator = try RokidCXRCoordinator()
                } catch {
                    settings.mockMode = true
                    adapterInitializationError = error.localizedDescription
                }
            }
            rokidCoordinator = resolvedCoordinator
            self.audioCapture =
                audioCapture
                ?? resolvedCoordinator.map { RokidMicrophoneAudioCaptureService(coordinator: $0) }
                ?? PhoneMicrophoneAudioCaptureService()
            self.transport =
                transport
                ?? resolvedCoordinator.map { CXRLRokidDisplayTransport(coordinator: $0) }
                ?? MockRokidDisplayTransport()
        #else
            if !settings.mockMode { settings.mockMode = true }
            self.audioCapture = audioCapture ?? PhoneMicrophoneAudioCaptureService()
            self.transport = transport ?? MockRokidDisplayTransport()
        #endif

        self.identificationService = identificationService ?? ShazamTrackIdentificationService()
        self.lyricsProvider = lyricsProvider ?? LRCLibLyricsProvider(cache: cache)
        scorer = LyricsMatchScorer()
        parser = LRCParser()
        self.engine = engine ?? LyricsSynchronizationEngine(correctionStore: correctionStore)
        self.sharedInbox = sharedInbox ?? SharedTrackInbox()
        #if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
            if let adapterInitializationError {
                lastError = "Rokid SDK initialization failed: \(adapterInitializationError)"
            }
        #endif
    }

    func bootstrap() async {
        await consumeSharedDraft()
        if settings.automaticReconnect {
            await connectTransport(reportErrors: false)
        } else {
            await refreshConnectionState()
        }
    }

    func consumeSharedDraft() async {
        guard let draft = await sharedInbox.take() else { return }
        searchSelectionUsesIdentifiedTrack = false
        manualSearchTitle = draft.title ?? ""
        manualSearchArtist = draft.artist ?? ""
        pendingSharedURL = draft.url
        statusMessage =
            draft.requiresConfirmation
            ? "Confirm the shared song details"
            : "Shared song ready to search"
        selectedTab = .search
    }

    func startLyrics() {
        guard pipelineTask == nil else { return }
        if settings.recognitionBehavior == .manualSearch {
            selectedTab = .search
            statusMessage = "Enter a song to use manual search"
            return
        }

        lastError = nil
        pipelineTask = Task { [weak self] in
            await self?.runRecognitionPipeline()
        }
    }

    func stopLyrics() {
        pipelineTask?.cancel()
        pipelineTask = nil
        searchTask?.cancel()
        searchTask = nil
        displayTask?.cancel()
        displayTask = nil
        isMicrophoneActive = false
        statusMessage = "Stopping"

        Task { [weak self] in
            guard let self else { return }
            await audioCapture.stopCapture()
            if connectionState == .connected {
                try? await transport.clearDisplay()
            }
            await engine.stop()
            lastTransportContent = nil
            lastGlassesPayload = nil
            await refreshFromEngine()
            statusMessage = "Stopped"
        }
    }

    func togglePause() {
        Task { [weak self] in
            guard let self else { return }
            do {
                if synchronizationState == .playing {
                    try await engine.pause()
                } else if synchronizationState == .paused {
                    try await engine.play()
                }
                await refreshFromEngine()
                await pushCurrentDisplay(force: true)
            } catch {
                report(error)
            }
        }
    }

    func adjustOffset(by seconds: TimeInterval) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.adjustSyncOffset(by: seconds)
                await refreshFromEngine()
                await pushCurrentDisplay(force: true)
            } catch {
                report(error)
            }
        }
    }

    func syncActiveLineNow() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.syncActiveLineNow()
                await refreshFromEngine()
                statusMessage = "Current lyric aligned to now"
                await pushCurrentDisplay(force: true)
            } catch {
                report(error)
            }
        }
    }

    func moveToPreviousLine() {
        moveLine { engine in try await engine.moveToPreviousLine() }
    }

    func moveToNextLine() {
        moveLine { engine in try await engine.moveToNextLine() }
    }

    func connectRokid() {
        Task { [weak self] in await self?.connectTransport(reportErrors: true) }
    }

    func disconnectRokid() {
        Task { [weak self] in
            guard let self else { return }
            await transport.disconnect()
            lastTransportContent = nil
            await refreshConnectionState()
        }
    }

    func updateMockMode(_ enabled: Bool) {
        guard synchronizationState == .idle else {
            lastError = "Stop lyrics before changing the display transport."
            return
        }
        guard enabled != settings.mockMode else { return }

        #if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
            let previousTransport = transport
            let previousAudioCapture = audioCapture
            Task {
                await previousAudioCapture.stopCapture()
                await previousTransport.disconnect()
            }

            if enabled {
                settings.mockMode = true
                rokidCoordinator = nil
                transport = MockRokidDisplayTransport()
                audioCapture = PhoneMicrophoneAudioCaptureService()
                connectionState = .disconnected
            } else {
                do {
                    let coordinator = try RokidCXRCoordinator()
                    rokidCoordinator = coordinator
                    transport = CXRLRokidDisplayTransport(coordinator: coordinator)
                    audioCapture = RokidMicrophoneAudioCaptureService(coordinator: coordinator)
                    settings.mockMode = false
                    connectionState = .disconnected
                } catch {
                    settings.mockMode = true
                    lastError = "Rokid SDK initialization failed: \(error.localizedDescription)"
                }
            }
        #else
            if !enabled {
                settings.mockMode = true
                lastError = "This build does not include the optional RGCxrClient adapter."
                return
            }
            settings.mockMode = true
        #endif
        lastTransportContent = nil
        lastGlassesPayload = nil
    }

    var isRealRokidSDKCompiled: Bool {
        #if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
            true
        #else
            false
        #endif
    }

    func handleRokidOpenURL(_ url: URL) {
        #if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
            _ = rokidCoordinator?.handleOpenURL(url)
        #endif
    }

    func dismissError() {
        lastError = nil
    }

    func searchLyrics() {
        let title = manualSearchTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = manualSearchArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else {
            lastError = "Enter both a song title and artist."
            return
        }

        searchTask?.cancel()
        searchSelectionUsesIdentifiedTrack = false
        isSearching = true
        searchResults = []
        lastError = nil
        searchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isSearching = false
                searchTask = nil
            }
            do {
                let query = LyricsQuery(title: title, artist: artist)
                let candidates = try await lyricsProvider.searchLyrics(for: query)
                searchResults = scorer.rank(query: query, candidates: candidates)
                providerResultSummary = "LRCLIB search returned \(candidates.count) candidate(s)"
                if candidates.isEmpty {
                    lastError = "LRCLIB found no matching lyrics."
                }
            } catch is CancellationError {
                return
            } catch {
                report(error)
            }
        }
    }

    func selectSearchResult(_ scored: ScoredLyricsCandidate) {
        searchTask?.cancel()
        let usesIdentifiedTrack = searchSelectionUsesIdentifiedTrack
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                if usesIdentifiedTrack,
                    currentTrack != nil,
                    synchronizationState == .fetchingLyrics
                {
                    try await activate(candidate: scored.candidate)
                } else {
                    try await activateManual(candidate: scored.candidate)
                }
                selectedTab = .nowPlaying
                searchResults = []
                searchSelectionUsesIdentifiedTrack = false
                pendingSharedURL = nil
            } catch {
                report(error)
            }
            searchTask = nil
        }
    }

    var connectionStateText: String {
        switch connectionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return settings.mockMode ? "Connected (Mock)" : "Connected"
        case .disconnecting: return "Disconnecting"
        case let .failed(message): return "Failed: \(message)"
        }
    }

    var recognitionStateText: String {
        synchronizationState.rawValue
            .replacingOccurrences(of: "Lyrics", with: " lyrics")
            .capitalized
    }

    var normalizedMetadataText: String {
        guard let track = currentTrack else { return "No track identified" }
        let normalized = LyricsMetadataNormalizer().normalize(
            title: track.title,
            artist: track.artist,
            album: track.album
        )
        return
            "title=\(normalized.title); coreTitle=\(normalized.coreTitle); artist=\(normalized.artist); coreArtist=\(normalized.coreArtist)"
    }

    var diagnosticsJSON: String {
        let trackPayload: Any
        if let track = currentTrack {
            trackPayload = [
                "id": track.id,
                "title": track.title,
                "artist": track.artist,
                "album": jsonValue(track.album),
                "source": track.identification.source,
                "confidence": jsonValue(track.identification.confidence),
            ]
        } else {
            trackPayload = NSNull()
        }

        let glassesPayload: Any
        if let display = lastGlassesPayload {
            glassesPayload = [
                "trackTitle": display.trackTitle,
                "artist": display.artist,
                "previousLine": jsonValue(display.previousLine),
                "activeLine": display.activeLine,
                "nextLine": jsonValue(display.nextLine),
                "progress": jsonValue(display.progress),
                "status": display.status.rawValue,
            ]
        } else {
            glassesPayload = NSNull()
        }

        let payload: [String: Any] = [
            "rokidConnectionState": connectionStateText,
            "mockMode": settings.mockMode,
            "realRokidSDKCompiled": isRealRokidSDKCompiled,
            "recognitionState": synchronizationState.rawValue,
            "microphoneActive": isMicrophoneActive,
            "track": trackPayload,
            "normalizedMetadata": normalizedMetadataText,
            "lyricsProviderResult": providerResultSummary,
            "timelinePositionSeconds": playbackPosition,
            "activeLyricTimestamp": jsonValue(timelinePosition?.activeLine?.timestamp),
            "syncOffsetSeconds": syncOffsetSeconds,
            "lastGlassesPayload": glassesPayload,
            "lastError": jsonValue(lastError),
        ]
        guard JSONSerialization.isValidJSONObject(payload),
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else { return "{\"error\":\"Diagnostics serialization failed\"}" }
        return string
    }

    private func runRecognitionPipeline() async {
        defer { pipelineTask = nil }
        do {
            await engine.stop()
            try await engine.startListening()
            statusMessage = "Microphone starting"
            await refreshFromEngine()

            isMicrophoneActive = true
            try await engine.beginIdentification()
            statusMessage = "Listening for about 8 seconds"
            await refreshFromEngine()

            let track = try await identificationService.identifyTrack(using: audioCapture)
            isMicrophoneActive = false
            try await engine.setIdentifiedTrack(track)
            statusMessage = "Identified \(track.title)"
            await refreshFromEngine()

            try await engine.beginFetchingLyrics()
            statusMessage = "Searching LRCLIB"
            await refreshFromEngine()

            let query = LyricsQuery(track: track)
            let candidates = try await lyricsProvider.searchLyrics(for: query)
            providerResultSummary = "LRCLIB returned \(candidates.count) candidate(s) for \(track.title)"
            let synchronizedCandidates = candidates.filter {
                !$0.isInstrumental && $0.synchronizedLyrics?.isEmpty == false
            }
            switch scorer.selectBest(query: query, candidates: synchronizedCandidates) {
            case let .match(result):
                try await activate(candidate: result.candidate)
                selectedTab = .nowPlaying
            case let .ambiguous(results):
                searchResults = results
                searchSelectionUsesIdentifiedTrack = true
                manualSearchTitle = track.title
                manualSearchArtist = track.artist
                statusMessage = "Choose between \(results.count) close lyric matches"
                selectedTab = .search
            case let .noMatch(results):
                searchResults =
                    results.isEmpty
                    ? scorer.rank(query: query, candidates: candidates)
                    : results
                searchSelectionUsesIdentifiedTrack = true
                manualSearchTitle = track.title
                manualSearchArtist = track.artist
                statusMessage = "No safe automatic lyric match"
                lastError = "Review the LRCLIB results or refine the manual search."
                selectedTab = .search
            }
        } catch is CancellationError {
            isMicrophoneActive = false
            await audioCapture.stopCapture()
        } catch {
            isMicrophoneActive = false
            await audioCapture.stopCapture()
            await engine.fail(error.localizedDescription)
            report(error)
            await refreshFromEngine()
        }
    }

    private func activate(candidate: LyricsCandidate) async throws {
        if candidate.isInstrumental {
            throw SessionPresentationError.instrumental
        }
        guard let synchronized = candidate.synchronizedLyrics, !synchronized.isEmpty else {
            throw SessionPresentationError.synchronizedLyricsUnavailable
        }
        let document = parser.parse(synchronized)
        guard !document.lines.isEmpty else { throw SessionPresentationError.invalidSynchronizedLyrics }

        try await engine.setLyrics(document)
        let storedOffset = await engine.snapshot().syncOffsetSeconds
        if settings.defaultLyricOffset != 0, storedOffset == 0 {
            try await engine.setSyncOffset(settings.defaultLyricOffset)
        }
        try await engine.play()
        statusMessage = "Lyrics playing"
        await refreshFromEngine()
        startDisplayLoop()
        await pushCurrentDisplay(force: true)
    }

    private func activateManual(candidate: LyricsCandidate) async throws {
        let track = TrackIdentity(
            id: "lrclib:\(candidate.id)",
            title: candidate.trackTitle,
            artist: candidate.artistName,
            album: candidate.albumName,
            artworkURL: nil,
            duration: candidate.duration,
            recognizedAt: Date(),
            playbackPositionAtRecognition: 0,
            identification: TrackIdentificationMetadata(
                source: "Manual LRCLIB selection",
                sourceIdentifier: candidate.id
            )
        )
        await engine.stop()
        try await engine.startListening()
        try await engine.beginIdentification()
        try await engine.setIdentifiedTrack(track)
        try await engine.beginFetchingLyrics()
        try await activate(candidate: candidate)
    }

    private func startDisplayLoop() {
        displayTask?.cancel()
        displayTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refreshFromEngine()
                await pushCurrentDisplay(force: false)
                await reconnectIfNeeded()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func refreshFromEngine() async {
        let snapshot = await engine.snapshot()
        synchronizationState = snapshot.state
        currentTrack = snapshot.track
        timelinePosition = snapshot.timelinePosition
        playbackPosition = snapshot.playbackPosition
        syncOffsetSeconds = snapshot.syncOffsetSeconds
        currentDisplayModel = await engine.glassesDisplayModel().map(displayModelForSettings)
    }

    private func displayModelForSettings(_ model: GlassesDisplayModel) -> GlassesDisplayModel {
        let previous =
            settings.lineCount >= 3 && settings.showPreviousLine
            ? model.previousLine : nil
        let next =
            settings.lineCount >= 2 && settings.showNextLine
            ? model.nextLine : nil
        return GlassesDisplayModel(
            trackTitle: model.trackTitle,
            artist: model.artist,
            previousLine: previous,
            activeLine: model.activeLine,
            nextLine: next,
            progress: model.progress,
            status: model.status,
            preferences: GlassesDisplayPreferences(
                fontScale: settings.fontScale,
                visibleLineCount: settings.lineCount,
                verticalPosition: settings.verticalPosition,
                showPreviousLine: settings.showPreviousLine,
                showNextLine: settings.showNextLine
            )
        )
    }

    private func pushCurrentDisplay(force: Bool) async {
        guard let display = currentDisplayModel else { return }
        await refreshConnectionState()
        guard connectionState == .connected else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let content = TransportContent(display)
        let contentChanged = content != lastTransportContent
        let slowProgressRefreshDue = now - lastTransportSendTime >= 5
        guard force || contentChanged || slowProgressRefreshDue else { return }

        do {
            try await transport.sendDisplayState(display)
            lastGlassesPayload = display
            lastTransportContent = content
            lastTransportSendTime = now
        } catch {
            lastError = "Display update failed: \(error.localizedDescription)"
            await refreshConnectionState()
        }
    }

    private func connectTransport(reportErrors: Bool) async {
        do {
            try await transport.connect()
            await refreshConnectionState()
            if currentDisplayModel != nil { await pushCurrentDisplay(force: true) }
        } catch {
            await refreshConnectionState()
            if reportErrors { self.report(error) }
        }
    }

    private func reconnectIfNeeded() async {
        guard settings.automaticReconnect, connectionState != .connected else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastReconnectAttemptTime >= 5 else { return }
        lastReconnectAttemptTime = now
        await connectTransport(reportErrors: false)
    }

    private func refreshConnectionState() async {
        connectionState = await transport.connectionState
    }

    private func moveLine(
        operation: @escaping @Sendable (LyricsSynchronizationEngine) async throws -> Void
    ) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await operation(engine)
                await refreshFromEngine()
                await pushCurrentDisplay(force: true)
            } catch {
                report(error)
            }
        }
    }

    private func report(_ error: Error) {
        lastError = error.localizedDescription
        statusMessage = "Action needs attention"
    }

    private func jsonValue(_ value: Any?) -> Any {
        value ?? NSNull()
    }
}

private struct TransportContent: Equatable {
    let trackTitle: String
    let artist: String
    let previousLine: String?
    let activeLine: String
    let nextLine: String?
    let status: GlassesDisplayStatus
    let preferences: GlassesDisplayPreferences

    init(_ model: GlassesDisplayModel) {
        trackTitle = model.trackTitle
        artist = model.artist
        previousLine = model.previousLine
        activeLine = model.activeLine
        nextLine = model.nextLine
        status = model.status
        preferences = model.preferences
    }
}

private enum SessionPresentationError: Error, LocalizedError {
    case instrumental
    case synchronizedLyricsUnavailable
    case invalidSynchronizedLyrics

    var errorDescription: String? {
        switch self {
        case .instrumental:
            return "LRCLIB marks this track as instrumental."
        case .synchronizedLyricsUnavailable:
            return "This LRCLIB result has plain lyrics but no synchronized timeline."
        case .invalidSynchronizedLyrics:
            return "The synchronized lyrics contained no usable timestamps."
        }
    }
}
