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
    private(set) var recognitionDiagnostics = RecognitionDiagnosticState()
    private(set) var lyricsDiagnostics = LyricsProviderDiagnosticState()
    private(set) var liveLyricsDiagnostics = LyricsProviderDiagnosticState()
    private(set) var liveLyricsCandidates: [LyricsCandidateDiagnostic] = []
    private(set) var isLiveLyricsTestRunning = false
    private(set) var rokidHardwareDiagnostics = RokidHardwareDiagnosticSnapshot()
    private(set) var hardwareTestLastSyntheticText: String?
    private(set) var hardwareTestCounter = 0
    private(set) var glassesMicrophoneDiagnostics = GlassesMicrophoneDiagnosticState()
    var musicCoexistenceDiagnostics = MusicCoexistenceDiagnosticState()
    var manualSearchTitle = ""
    var manualSearchArtist = ""
    var liveLyricsTestTitle = ""
    var liveLyricsTestArtist = ""
    var pendingSharedURL: URL?

    let audioSessionDiagnostics: AudioSessionDiagnosticsMonitor

    private var audioCapture: any AudioCaptureService
    private let identificationService: any TrackIdentificationService
    private let lyricsProvider: any LyricsProvider
    private let liveLyricsProvider: any LyricsProvider
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
    private var liveLyricsTask: Task<Void, Never>?
    private var hardwareTestTask: Task<Void, Never>?
    private var glassesMicrophoneTask: Task<Void, Never>?
    private var lastTransportContent: TransportContent?
    private var lastTransportSendTime: TimeInterval = 0
    private var lastReconnectAttemptTime: TimeInterval = 0
    private var coexistenceStartedAtMonotonic: TimeInterval?
    private var hardwareDiagnosticsStartedAt = ProcessInfo.processInfo.systemUptime
    /// Automatic Shazam ambiguity keeps the recognition clock; a new manual or
    /// shared search must not accidentally reuse stale recognized metadata.
    private var searchSelectionUsesIdentifiedTrack = false

    init(
        settings: AppSettings? = nil,
        audioCapture: (any AudioCaptureService)? = nil,
        identificationService: (any TrackIdentificationService)? = nil,
        lyricsProvider: (any LyricsProvider)? = nil,
        liveLyricsProvider: (any LyricsProvider)? = nil,
        engine: LyricsSynchronizationEngine? = nil,
        sharedInbox: SharedTrackInbox? = nil,
        transport: (any RokidDisplayTransport)? = nil,
        audioSessionDiagnostics: AudioSessionDiagnosticsMonitor? = nil
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
        self.liveLyricsProvider = liveLyricsProvider ?? LRCLibLyricsProvider()
        scorer = LyricsMatchScorer()
        parser = LRCParser()
        self.engine = engine ?? LyricsSynchronizationEngine(correctionStore: correctionStore)
        self.sharedInbox = sharedInbox ?? SharedTrackInbox()
        self.audioSessionDiagnostics = audioSessionDiagnostics ?? AudioSessionDiagnosticsMonitor()
        #if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
            if let adapterInitializationError {
                lastError = "Rokid SDK initialization failed: \(adapterInitializationError)"
            }
        #endif
    }

    func bootstrap() async {
        audioSessionDiagnostics.startMonitoring()
        refreshRokidHardwareDiagnostics()
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
            await self?.runRecognitionPipeline(keepCurrentTab: false)
        }
    }

    func stopLyrics() {
        pipelineTask?.cancel()
        pipelineTask = nil
        searchTask?.cancel()
        searchTask = nil
        glassesMicrophoneTask?.cancel()
        glassesMicrophoneTask = nil
        displayTask?.cancel()
        displayTask = nil
        isMicrophoneActive = false
        audioSessionDiagnostics.setCaptureRunning(false, source: activeAudioSourceName)
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
        hardwareDiagnosticsStartedAt = ProcessInfo.processInfo.systemUptime
        rokidHardwareDiagnostics = RokidHardwareDiagnosticSnapshot()
        refreshRokidHardwareDiagnostics()
    }

    var isRealRokidSDKCompiled: Bool {
        #if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
            true
        #else
            false
        #endif
    }

    var compiledBuildModeText: String {
        isRealRokidSDKCompiled ? "ROKID HARDWARE BUILD" : "MOCK BUILD"
    }

    var activeRuntimeModeText: String {
        if isRealRokidSDKCompiled, !settings.mockMode {
            return "Rokid Hardware"
        }
        return isRealRokidSDKCompiled ? "Mock (SDK compiled)" : "Mock"
    }

    var activeAudioSourceName: String {
        isRealRokidSDKCompiled && !settings.mockMode
            ? "Rokid glasses microphone"
            : "iPhone microphone"
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
                let requestStartedAt = ProcessInfo.processInfo.systemUptime
                lyricsDiagnostics = LyricsProviderDiagnosticState(
                    state: "Requesting",
                    requestedTitle: title,
                    requestedArtist: artist
                )
                let candidates = try await lyricsProvider.searchLyrics(for: query)
                searchResults = scorer.rank(query: query, candidates: candidates)
                lyricsDiagnostics.state = candidates.isEmpty ? "No candidates" : "Received candidates"
                lyricsDiagnostics.candidateCount = candidates.count
                lyricsDiagnostics.requestLatency = max(
                    0,
                    ProcessInfo.processInfo.systemUptime - requestStartedAt
                )
                providerResultSummary = "LRCLIB search returned \(candidates.count) candidate(s)"
                if candidates.isEmpty {
                    lastError = "LRCLIB found no matching lyrics."
                }
            } catch is CancellationError {
                return
            } catch {
                lyricsDiagnostics.state = "Error"
                lyricsDiagnostics.error = DiagnosticSanitizer.sanitizedError(error.localizedDescription)
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
                lyricsDiagnostics.selectedResult = candidateDiagnostic(
                    scored.candidate,
                    score: scored.score
                )
                lyricsDiagnostics.synchronizedLyricsAvailable =
                    scored.candidate.synchronizedLyrics?.isEmpty == false
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

    /// Performs an explicit uncached LRCLIB request. It is intentionally
    /// user-triggered and never runs from automated tests or CI.
    func runLiveLRCLibTest() {
        let title = liveLyricsTestTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = liveLyricsTestArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else {
            liveLyricsDiagnostics = LyricsProviderDiagnosticState(
                state: "Input required",
                requestedTitle: title.isEmpty ? nil : title,
                requestedArtist: artist.isEmpty ? nil : artist,
                error: "Enter both a song title and artist."
            )
            return
        }

        liveLyricsTask?.cancel()
        isLiveLyricsTestRunning = true
        liveLyricsCandidates = []
        liveLyricsDiagnostics = LyricsProviderDiagnosticState(
            state: "Requesting live LRCLIB",
            requestedTitle: title,
            requestedArtist: artist
        )
        liveLyricsTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = ProcessInfo.processInfo.systemUptime
            defer {
                isLiveLyricsTestRunning = false
                liveLyricsTask = nil
            }

            do {
                let query = LyricsQuery(title: title, artist: artist)
                let candidates = try await liveLyricsProvider.searchLyrics(for: query)
                let ranked = scorer.rank(query: query, candidates: candidates)
                liveLyricsCandidates = ranked.map {
                    candidateDiagnostic($0.candidate, score: $0.score)
                }
                liveLyricsDiagnostics.state = candidates.isEmpty ? "No candidates" : "Completed"
                liveLyricsDiagnostics.candidateCount = candidates.count
                liveLyricsDiagnostics.requestLatency = max(
                    0,
                    ProcessInfo.processInfo.systemUptime - startedAt
                )

                let synchronizedCandidates = candidates.filter {
                    !$0.isInstrumental && $0.synchronizedLyrics?.isEmpty == false
                }
                if case let .match(result) = scorer.selectBest(
                    query: query,
                    candidates: synchronizedCandidates
                ) {
                    let selected = candidateDiagnostic(result.candidate, score: result.score)
                    liveLyricsDiagnostics.selectedResult = selected
                    liveLyricsDiagnostics.synchronizedLyricsAvailable =
                        result.candidate.synchronizedLyrics?.isEmpty == false
                    if let synchronized = result.candidate.synchronizedLyrics {
                        liveLyricsDiagnostics.lyricLineCount = parser.parse(synchronized).lines.count
                    }
                }
            } catch is CancellationError {
                liveLyricsDiagnostics.state = "Cancelled"
            } catch {
                liveLyricsDiagnostics.state = "Error"
                liveLyricsDiagnostics.requestLatency = max(
                    0,
                    ProcessInfo.processInfo.systemUptime - startedAt
                )
                liveLyricsDiagnostics.error = DiagnosticSanitizer.sanitizedError(
                    error.localizedDescription
                )
            }
        }
    }

    func startMusicCoexistenceTest() {
        guard pipelineTask == nil else {
            lastError = "Stop the current lyrics session before starting the coexistence test."
            return
        }

        audioSessionDiagnostics.beginCoexistenceObservation()
        let audioSnapshot = audioSessionDiagnostics.snapshot
        musicCoexistenceDiagnostics = MusicCoexistenceDiagnosticState(
            state: "Running recognition",
            startedAt: Date(),
            otherAudioWasPlayingAtStart: audioSnapshot.isOtherAudioPlaying,
            otherAudioIsPlayingNow: audioSnapshot.isOtherAudioPlaying
        )
        coexistenceStartedAtMonotonic = ProcessInfo.processInfo.systemUptime
        lastError = nil
        pipelineTask = Task { [weak self] in
            await self?.runRecognitionPipeline(keepCurrentTab: true)
        }
    }

    func hardwareTestConnect() {
        hardwareTestTask?.cancel()
        hardwareTestTask = Task { [weak self] in
            guard let self else { return }
            appendMockHardwareEvent(category: "action", detail: "Connect requested")
            await connectTransport(reportErrors: true)
            refreshRokidHardwareDiagnostics()
            hardwareTestTask = nil
        }
    }

    func hardwareTestDisconnect() {
        hardwareTestTask?.cancel()
        hardwareTestTask = Task { [weak self] in
            guard let self else { return }
            appendMockHardwareEvent(category: "action", detail: "Disconnect requested")
            await transport.disconnect()
            lastTransportContent = nil
            await refreshConnectionState()
            refreshRokidHardwareDiagnostics()
            hardwareTestTask = nil
        }
    }

    func hardwareTestSendText(_ text: String) {
        sendSyntheticHardwareText(text, category: "static-text")
    }

    func hardwareTestSendCounter() {
        hardwareTestCounter += 1
        sendSyntheticHardwareText("Test \(hardwareTestCounter)", category: "counter")
    }

    func hardwareTestSendUnicodeSequence() {
        hardwareTestTask?.cancel()
        hardwareTestTask = Task { [weak self] in
            guard let self else { return }
            for value in ["Hello Rokid", "日本語テスト", "中文测试", "한국어 테스트"] {
                guard !Task.isCancelled else { return }
                do {
                    try await sendSyntheticHardwareTextNow(value, category: "unicode")
                } catch {
                    report(error)
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }
            hardwareTestTask = nil
        }
    }

    func hardwareTestClearDisplay() {
        hardwareTestTask?.cancel()
        hardwareTestTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await transport.clearDisplay()
                currentDisplayModel = nil
                lastGlassesPayload = nil
                lastTransportContent = nil
                hardwareTestLastSyntheticText = nil
                appendMockHardwareEvent(category: "display", detail: "Clear completed")
            } catch {
                report(error)
                appendMockHardwareEvent(category: "display", detail: "Clear failed")
            }
            await refreshConnectionState()
            refreshRokidHardwareDiagnostics()
            hardwareTestTask = nil
        }
    }

    func startGlassesMicrophoneTest() {
        guard isRealRokidSDKCompiled, !settings.mockMode else {
            glassesMicrophoneDiagnostics = GlassesMicrophoneDiagnosticState(
                state: "Unavailable",
                error: "Use the Rokid Hardware build with Mock Mode off."
            )
            return
        }
        guard pipelineTask == nil, glassesMicrophoneTask == nil else {
            glassesMicrophoneDiagnostics.state = "Busy"
            glassesMicrophoneDiagnostics.error = "Stop recognition or the current microphone test first."
            return
        }

        glassesMicrophoneDiagnostics = GlassesMicrophoneDiagnosticState(state: "Starting")
        glassesMicrophoneTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = ProcessInfo.processInfo.systemUptime
            isMicrophoneActive = true
            do {
                let stream = try await audioCapture.startCapture()
                glassesMicrophoneDiagnostics.state = "Waiting for PCM"
                var lastPublishedAt = startedAt
                var byteCount = 0
                var frameCount = 0
                var bufferCount = 0

                for try await frame in stream {
                    try Task.checkCancellation()
                    bufferCount += 1
                    byteCount += frame.samples.count * MemoryLayout<Int16>.size
                    frameCount += frame.samples.count / max(1, frame.channelCount)
                    let now = ProcessInfo.processInfo.systemUptime
                    if !glassesMicrophoneDiagnostics.streamConnected || now - lastPublishedAt >= 0.2 {
                        glassesMicrophoneDiagnostics.state = "Receiving PCM"
                        glassesMicrophoneDiagnostics.streamConnected = true
                        glassesMicrophoneDiagnostics.sampleRate = frame.sampleRate
                        glassesMicrophoneDiagnostics.channelCount = frame.channelCount
                        glassesMicrophoneDiagnostics.decodedByteCount = byteCount
                        glassesMicrophoneDiagnostics.pcmFrameCount = frameCount
                        glassesMicrophoneDiagnostics.bufferCount = bufferCount
                        glassesMicrophoneDiagnostics.duration = max(0, now - startedAt)
                        lastPublishedAt = now
                        refreshRokidHardwareDiagnostics()
                    }
                }
            } catch is CancellationError {
                glassesMicrophoneDiagnostics.state = "Stopped"
            } catch {
                glassesMicrophoneDiagnostics.state = "Error"
                glassesMicrophoneDiagnostics.error = DiagnosticSanitizer.sanitizedError(
                    error.localizedDescription
                )
            }
            await audioCapture.stopCapture()
            isMicrophoneActive = false
            glassesMicrophoneTask = nil
            refreshRokidHardwareDiagnostics()
        }
    }

    func stopGlassesMicrophoneTest() {
        glassesMicrophoneTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            await audioCapture.stopCapture()
            isMicrophoneActive = false
            if glassesMicrophoneDiagnostics.state != "Error" {
                glassesMicrophoneDiagnostics.state = "Stopped"
            }
            refreshRokidHardwareDiagnostics()
        }
    }

    func refreshDeviceDiagnostics() async {
        audioSessionDiagnostics.refresh()
        await refreshConnectionState()
        await refreshFromEngine()
        refreshRokidHardwareDiagnostics()
        if musicCoexistenceDiagnostics.state == "Running recognition" {
            musicCoexistenceDiagnostics.otherAudioIsPlayingNow =
                audioSessionDiagnostics.snapshot.isOtherAudioPlaying
            if let startedAt = coexistenceStartedAtMonotonic {
                musicCoexistenceDiagnostics.elapsedSeconds = max(
                    0,
                    ProcessInfo.processInfo.systemUptime - startedAt
                )
            }
            musicCoexistenceDiagnostics.routeChanged =
                musicCoexistenceDiagnostics.routeChanged
                || audioSessionDiagnostics.snapshot.routeChangeCount > 0
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
        let audio = audioSessionDiagnostics.snapshot
        let report = SafeDeviceDiagnosticReport(
            generatedAt: Date(),
            build: .init(
                compiledMode: compiledBuildModeText,
                activeMode: activeRuntimeModeText,
                sdkAvailable: isRealRokidSDKCompiled
            ),
            audioSession: .init(
                category: audio.category,
                mode: audio.mode,
                categoryOptions: audio.categoryOptions,
                inputPortTypes: audio.inputs.map(\.type),
                outputPortTypes: audio.outputs.map(\.type),
                selectedInputPortType: audio.selectedInput?.type,
                sampleRate: audio.sampleRate,
                inputChannelCount: audio.inputChannelCount,
                outputChannelCount: audio.outputChannelCount,
                captureRunning: audio.isCaptureRunning,
                otherAudioPlaying: audio.isOtherAudioPlaying,
                secondaryAudioShouldBeSilenced: audio.secondaryAudioShouldBeSilenced,
                interruptionState: audio.interruptionState,
                routeChangeCount: audio.routeChangeCount,
                events: audioSessionDiagnostics.events.map(safeEvent)
            ),
            shazamKit: .init(
                state: recognitionDiagnostics.state,
                startTimestamp: recognitionDiagnostics.startTimestamp,
                matchTimestamp: recognitionDiagnostics.matchTimestamp,
                latencySeconds: recognitionDiagnostics.recognitionLatency,
                title: recognitionDiagnostics.title,
                artist: recognitionDiagnostics.artist,
                album: recognitionDiagnostics.album,
                shazamID: recognitionDiagnostics.shazamID,
                catalogURL: recognitionDiagnostics.catalogURL,
                error: DiagnosticSanitizer.sanitizedError(recognitionDiagnostics.error)
            ),
            lrclib: safeLyricsReport(lyricsDiagnostics),
            liveLRCLib: safeLyricsReport(liveLyricsDiagnostics),
            synchronization: .init(
                state: synchronizationState.rawValue,
                monotonicElapsedSeconds: recognitionDiagnostics.startMonotonicTime.map {
                    max(0, ProcessInfo.processInfo.systemUptime - $0)
                },
                estimatedLyricPositionSeconds: playbackPosition,
                globalOffsetSeconds: syncOffsetSeconds,
                currentLyricIndex: timelinePosition?.activeLineIndex
            ),
            musicCoexistence: .init(
                state: musicCoexistenceDiagnostics.state,
                startedAt: musicCoexistenceDiagnostics.startedAt,
                elapsedSeconds: musicCoexistenceDiagnostics.elapsedSeconds,
                otherAudioWasPlayingAtStart: musicCoexistenceDiagnostics.otherAudioWasPlayingAtStart,
                otherAudioIsPlayingNow: musicCoexistenceDiagnostics.otherAudioIsPlayingNow,
                continuedNormally: musicCoexistenceDiagnostics.continuedNormally,
                ducked: musicCoexistenceDiagnostics.ducked,
                paused: musicCoexistenceDiagnostics.paused,
                routeChanged: musicCoexistenceDiagnostics.routeChanged,
                becameInaudible: musicCoexistenceDiagnostics.becameInaudible,
                notes: DiagnosticSanitizer.sanitizedError(musicCoexistenceDiagnostics.notes) ?? ""
            ),
            rokidHardware: .init(
                connection: rokidHardwareDiagnostics.connection,
                authorization: rokidHardwareDiagnostics.authorization,
                session: rokidHardwareDiagnostics.session,
                customView: rokidHardwareDiagnostics.customView,
                audioStream: rokidHardwareDiagnostics.audioStream,
                lastSyntheticText: hardwareTestLastSyntheticText,
                events: rokidHardwareDiagnostics.events.map {
                    .init(
                        elapsedSeconds: $0.elapsedSeconds,
                        category: $0.category,
                        detail: DiagnosticSanitizer.sanitizedError($0.detail) ?? "Redacted event"
                    )
                },
                microphone: .init(
                    state: glassesMicrophoneDiagnostics.state,
                    streamConnected: glassesMicrophoneDiagnostics.streamConnected,
                    sampleRate: glassesMicrophoneDiagnostics.sampleRate,
                    channelCount: glassesMicrophoneDiagnostics.channelCount,
                    decodedByteCount: glassesMicrophoneDiagnostics.decodedByteCount,
                    pcmFrameCount: glassesMicrophoneDiagnostics.pcmFrameCount,
                    bufferCount: glassesMicrophoneDiagnostics.bufferCount,
                    durationSeconds: glassesMicrophoneDiagnostics.duration,
                    recognitionRouting: glassesMicrophoneDiagnostics.recognitionRouting,
                    error: DiagnosticSanitizer.sanitizedError(glassesMicrophoneDiagnostics.error)
                )
            ),
            lastDisplayPayload: lastGlassesPayload.map {
                .init(
                    status: $0.status.rawValue,
                    trackTitle: $0.trackTitle,
                    artist: $0.artist,
                    hasPreviousLine: $0.previousLine?.isEmpty == false,
                    activeLineCharacterCount: $0.activeLine.count,
                    hasNextLine: $0.nextLine?.isEmpty == false
                )
            },
            lastError: DiagnosticSanitizer.sanitizedError(lastError)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report),
            let string = String(data: data, encoding: .utf8)
        else { return "{\"error\":\"Diagnostics serialization failed\"}" }
        return string
    }

    private func runRecognitionPipeline(keepCurrentTab: Bool) async {
        let recognitionStartedAt = Date()
        let recognitionStartedAtMonotonic = ProcessInfo.processInfo.systemUptime
        recognitionDiagnostics = RecognitionDiagnosticState(
            state: "Starting",
            startTimestamp: recognitionStartedAt,
            startMonotonicTime: recognitionStartedAtMonotonic
        )
        defer {
            pipelineTask = nil
            audioSessionDiagnostics.setCaptureRunning(false, source: activeAudioSourceName)
            finishMusicCoexistenceTestIfNeeded()
        }
        do {
            await engine.stop()
            try await engine.startListening()
            statusMessage = "Microphone starting"
            recognitionDiagnostics.state = "Starting audio capture"
            await refreshFromEngine()

            isMicrophoneActive = true
            audioSessionDiagnostics.setCaptureRunning(true, source: activeAudioSourceName)
            try await engine.beginIdentification()
            statusMessage = "Listening for about 8 seconds"
            recognitionDiagnostics.state = "Listening"
            await refreshFromEngine()

            let track = try await identificationService.identifyTrack(using: audioCapture)
            isMicrophoneActive = false
            audioSessionDiagnostics.setCaptureRunning(false, source: activeAudioSourceName)
            let matchTimestamp = Date()
            recognitionDiagnostics.state = "Matched"
            recognitionDiagnostics.matchTimestamp = matchTimestamp
            recognitionDiagnostics.recognitionLatency = max(
                0,
                ProcessInfo.processInfo.systemUptime - recognitionStartedAtMonotonic
            )
            recognitionDiagnostics.title = track.title
            recognitionDiagnostics.artist = track.artist
            recognitionDiagnostics.album = track.album
            recognitionDiagnostics.shazamID = track.identification.sourceIdentifier
            recognitionDiagnostics.catalogURL = DiagnosticSanitizer.sanitizedPublicURL(
                track.identification.attributes["catalogURL"]
            )
            try await engine.setIdentifiedTrack(track)
            statusMessage = "Identified \(track.title)"
            await refreshFromEngine()

            try await engine.beginFetchingLyrics()
            statusMessage = "Searching LRCLIB"
            await refreshFromEngine()

            let query = LyricsQuery(track: track)
            let lyricsRequestStartedAt = ProcessInfo.processInfo.systemUptime
            lyricsDiagnostics = LyricsProviderDiagnosticState(
                state: "Requesting",
                requestedTitle: query.title,
                requestedArtist: query.artist
            )
            let candidates = try await lyricsProvider.searchLyrics(for: query)
            lyricsDiagnostics.state = "Received candidates"
            lyricsDiagnostics.candidateCount = candidates.count
            lyricsDiagnostics.requestLatency = max(
                0,
                ProcessInfo.processInfo.systemUptime - lyricsRequestStartedAt
            )
            providerResultSummary = "LRCLIB returned \(candidates.count) candidate(s) for \(track.title)"
            let synchronizedCandidates = candidates.filter {
                !$0.isInstrumental && $0.synchronizedLyrics?.isEmpty == false
            }
            switch scorer.selectBest(query: query, candidates: synchronizedCandidates) {
            case let .match(result):
                lyricsDiagnostics.selectedResult = candidateDiagnostic(
                    result.candidate,
                    score: result.score
                )
                lyricsDiagnostics.synchronizedLyricsAvailable = true
                try await activate(candidate: result.candidate)
                if !keepCurrentTab { selectedTab = .nowPlaying }
            case let .ambiguous(results):
                lyricsDiagnostics.state = "Ambiguous"
                searchResults = results
                searchSelectionUsesIdentifiedTrack = true
                manualSearchTitle = track.title
                manualSearchArtist = track.artist
                statusMessage = "Choose between \(results.count) close lyric matches"
                if !keepCurrentTab { selectedTab = .search }
            case let .noMatch(results):
                lyricsDiagnostics.state = "No safe automatic match"
                searchResults =
                    results.isEmpty
                    ? scorer.rank(query: query, candidates: candidates)
                    : results
                searchSelectionUsesIdentifiedTrack = true
                manualSearchTitle = track.title
                manualSearchArtist = track.artist
                statusMessage = "No safe automatic lyric match"
                lastError = "Review the LRCLIB results or refine the manual search."
                if !keepCurrentTab { selectedTab = .search }
            }
        } catch is CancellationError {
            isMicrophoneActive = false
            recognitionDiagnostics.state = "Cancelled"
            await audioCapture.stopCapture()
        } catch {
            isMicrophoneActive = false
            await audioCapture.stopCapture()
            await engine.fail(error.localizedDescription)
            let safeError = DiagnosticSanitizer.sanitizedError(error.localizedDescription)
            if recognitionDiagnostics.matchTimestamp == nil {
                recognitionDiagnostics.state = "Error"
                recognitionDiagnostics.error = safeError
            } else {
                lyricsDiagnostics.state = "Error"
                lyricsDiagnostics.error = safeError
            }
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

        lyricsDiagnostics.state = "Synchronized lyrics ready"
        lyricsDiagnostics.selectedResult =
            lyricsDiagnostics.selectedResult
            ?? candidateDiagnostic(candidate, score: nil)
        lyricsDiagnostics.synchronizedLyricsAvailable = true
        lyricsDiagnostics.lyricLineCount = document.lines.count

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
        refreshRokidHardwareDiagnostics()
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

    private func candidateDiagnostic(
        _ candidate: LyricsCandidate,
        score: Double?
    ) -> LyricsCandidateDiagnostic {
        LyricsCandidateDiagnostic(
            id: candidate.id,
            title: candidate.trackTitle,
            artist: candidate.artistName,
            album: candidate.albumName,
            hasSynchronizedLyrics: candidate.synchronizedLyrics?.isEmpty == false,
            hasPlainLyrics: candidate.plainLyrics?.isEmpty == false,
            isInstrumental: candidate.isInstrumental,
            score: score
        )
    }

    private func finishMusicCoexistenceTestIfNeeded() {
        guard musicCoexistenceDiagnostics.state == "Running recognition" else { return }
        audioSessionDiagnostics.refresh()
        musicCoexistenceDiagnostics.state =
            recognitionDiagnostics.error == nil ? "Recognition action finished" : "Recognition action failed"
        musicCoexistenceDiagnostics.otherAudioIsPlayingNow =
            audioSessionDiagnostics.snapshot.isOtherAudioPlaying
        if let startedAt = coexistenceStartedAtMonotonic {
            musicCoexistenceDiagnostics.elapsedSeconds = max(
                0,
                ProcessInfo.processInfo.systemUptime - startedAt
            )
        }
        musicCoexistenceDiagnostics.routeChanged =
            musicCoexistenceDiagnostics.routeChanged
            || audioSessionDiagnostics.snapshot.routeChangeCount > 0
        coexistenceStartedAtMonotonic = nil
    }

    private func sendSyntheticHardwareText(_ text: String, category: String) {
        hardwareTestTask?.cancel()
        hardwareTestTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await sendSyntheticHardwareTextNow(text, category: category)
            } catch {
                report(error)
                appendMockHardwareEvent(category: "display", detail: "Synthetic display update failed")
            }
            hardwareTestTask = nil
        }
    }

    private func sendSyntheticHardwareTextNow(_ text: String, category: String) async throws {
        let display = GlassesDisplayModel(
            trackTitle: "Rokid Hardware Test",
            artist: "Synthetic text",
            previousLine: nil,
            activeLine: text,
            nextLine: nil,
            progress: nil,
            status: .displayingLyrics,
            preferences: GlassesDisplayPreferences(
                fontScale: settings.fontScale,
                visibleLineCount: 1,
                verticalPosition: settings.verticalPosition,
                showPreviousLine: false,
                showNextLine: false
            )
        )
        try await transport.sendDisplayState(display)
        currentDisplayModel = display
        lastGlassesPayload = display
        lastTransportContent = TransportContent(display)
        lastTransportSendTime = ProcessInfo.processInfo.systemUptime
        hardwareTestLastSyntheticText = text
        appendMockHardwareEvent(category: category, detail: "Sent synthetic text: \(text)")
        await refreshConnectionState()
        refreshRokidHardwareDiagnostics()
    }

    private func appendMockHardwareEvent(category: String, detail: String) {
        #if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
            if rokidCoordinator != nil { return }
        #endif
        let nextSequence = (rokidHardwareDiagnostics.events.last?.sequence ?? 0) + 1
        rokidHardwareDiagnostics.events.append(
            RokidHardwareDiagnosticEvent(
                sequence: nextSequence,
                elapsedSeconds: max(
                    0,
                    ProcessInfo.processInfo.systemUptime - hardwareDiagnosticsStartedAt
                ),
                category: category,
                detail: detail
            )
        )
        if rokidHardwareDiagnostics.events.count > 100 {
            rokidHardwareDiagnostics.events.removeFirst(
                rokidHardwareDiagnostics.events.count - 100
            )
        }
    }

    private func refreshRokidHardwareDiagnostics() {
        #if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
            if let rokidCoordinator {
                rokidHardwareDiagnostics = rokidCoordinator.diagnosticSnapshot
                return
            }
        #endif

        rokidHardwareDiagnostics.connection = connectionStateText
        rokidHardwareDiagnostics.authorization =
            isRealRokidSDKCompiled ? "SDK inactive while Mock Mode is on" : "Not applicable in Mock build"
        rokidHardwareDiagnostics.session = "Mock transport"
        rokidHardwareDiagnostics.customView = lastGlassesPayload == nil ? "Cleared" : "Showing synthetic state"
        rokidHardwareDiagnostics.audioStream = "Not available in Mock mode"
    }

    private func safeEvent(_ event: DiagnosticEvent) -> SafeDeviceDiagnosticReport.Event {
        .init(
            elapsedSeconds: event.elapsedSeconds,
            category: event.category,
            detail: DiagnosticSanitizer.sanitizedError(event.detail) ?? "Redacted event"
        )
    }

    private func safeLyricsReport(
        _ state: LyricsProviderDiagnosticState
    ) -> SafeDeviceDiagnosticReport.Lyrics {
        .init(
            state: state.state,
            requestedTitle: state.requestedTitle,
            requestedArtist: state.requestedArtist,
            candidateCount: state.candidateCount,
            selectedResult: state.selectedResult?.safeReportValue,
            synchronizedLyricsAvailable: state.synchronizedLyricsAvailable,
            lyricLineCount: state.lyricLineCount,
            requestLatencySeconds: state.requestLatency,
            error: DiagnosticSanitizer.sanitizedError(state.error)
        )
    }

    private func report(_ error: Error) {
        lastError = error.localizedDescription
        statusMessage = "Action needs attention"
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
