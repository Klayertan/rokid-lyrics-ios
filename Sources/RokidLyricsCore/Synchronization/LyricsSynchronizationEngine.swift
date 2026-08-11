import Foundation

public enum LyricsSynchronizationState: String, Codable, Equatable, Sendable {
    case idle
    case listening
    case identifying
    case identified
    case fetchingLyrics
    case ready
    case playing
    case paused
    case resyncing
    case error
}

public enum LyricsSynchronizationEngineError: Error, Equatable, Sendable {
    case invalidTransition(
        from: LyricsSynchronizationState,
        to: LyricsSynchronizationState
    )
    case missingTrack
    case missingLyrics
    case lineOutOfBounds
}

public struct LyricsSynchronizationSnapshot: Equatable, Sendable {
    public let state: LyricsSynchronizationState
    public let track: TrackIdentity?
    public let timelinePosition: LyricTimelinePosition?
    public let playbackPosition: TimeInterval
    public let syncOffsetSeconds: TimeInterval
    public let clockState: LyricPlaybackClockState
    public let lastErrorDescription: String?
}

/// Coordinates lyric clock state without depending on UI, AVFoundation,
/// networking, or a Rokid SDK.
public actor LyricsSynchronizationEngine {
    public private(set) var state: LyricsSynchronizationState = .idle
    public private(set) var currentTrack: TrackIdentity?
    public private(set) var syncOffsetSeconds: TimeInterval = 0
    public private(set) var lastErrorDescription: String?

    private let timeSource: any MonotonicTimeSource
    private let correctionStore: any SyncCorrectionStore
    private var clock = LyricPlaybackClock()
    private var timeline: LyricTimeline?
    private var stateBeforeResync: LyricsSynchronizationState?

    public init(
        timeSource: any MonotonicTimeSource = SystemMonotonicTimeSource(),
        correctionStore: any SyncCorrectionStore = InMemorySyncCorrectionStore()
    ) {
        self.timeSource = timeSource
        self.correctionStore = correctionStore
    }

    public func startListening() throws {
        guard state == .idle || state == .error else {
            throw transitionError(to: .listening)
        }
        resetSessionData()
        state = .listening
    }

    public func beginIdentification() throws {
        guard state == .listening else { throw transitionError(to: .identifying) }
        state = .identifying
    }

    public func setIdentifiedTrack(_ track: TrackIdentity) async throws {
        guard state == .identifying || state == .listening else {
            throw transitionError(to: .identified)
        }
        currentTrack = track
        syncOffsetSeconds = await correctionStore.correction(forTrackID: track.id) ?? 0
        if let playbackPosition = track.playbackPositionAtRecognition {
            // ShazamKit's predicted offset describes the current point when
            // recognition completes. Start immediately so lyric lookup/network
            // latency is included before the UI enters `.playing`.
            clock.start(at: playbackPosition, monotonicTime: timeSource.now)
        }
        state = .identified
    }

    public func beginFetchingLyrics() throws {
        guard state == .identified else { throw transitionError(to: .fetchingLyrics) }
        state = .fetchingLyrics
    }

    public func setLyrics(_ document: LyricDocument) throws {
        guard state == .fetchingLyrics || state == .identified else {
            throw transitionError(to: .ready)
        }
        guard let track = currentTrack else {
            throw LyricsSynchronizationEngineError.missingTrack
        }
        timeline = LyricTimeline(document: document, trackDuration: track.duration)
        state = .ready
    }

    public func play(from playbackPosition: TimeInterval? = nil) throws {
        guard state == .ready || state == .paused else {
            throw transitionError(to: .playing)
        }
        guard timeline != nil else { throw LyricsSynchronizationEngineError.missingLyrics }
        let now = timeSource.now
        if let playbackPosition {
            clock.start(at: playbackPosition, monotonicTime: now)
        } else if clock.state == .paused {
            clock.resume(at: now)
        } else {
            clock.start(at: clock.position(at: now), monotonicTime: now)
        }
        state = .playing
    }

    public func pause() throws {
        guard state == .playing else { throw transitionError(to: .paused) }
        clock.pause(at: timeSource.now)
        state = .paused
    }

    public func seek(to playbackPosition: TimeInterval) throws {
        guard timeline != nil else { throw LyricsSynchronizationEngineError.missingLyrics }
        guard state == .ready || state == .playing || state == .paused else {
            throw transitionError(to: state)
        }
        clock.seek(to: playbackPosition, at: timeSource.now)
    }

    public func beginResyncing() throws {
        guard state == .ready || state == .playing || state == .paused else {
            throw transitionError(to: .resyncing)
        }
        stateBeforeResync = state
        state = .resyncing
    }

    public func completeResync(at playbackPosition: TimeInterval) throws {
        guard state == .resyncing else {
            throw transitionError(to: stateBeforeResync ?? .ready)
        }
        clock.seek(to: playbackPosition, at: timeSource.now)
        state = stateBeforeResync ?? .ready
        stateBeforeResync = nil
    }

    public func cancelResync() throws {
        guard state == .resyncing else {
            throw transitionError(to: stateBeforeResync ?? .ready)
        }
        state = stateBeforeResync ?? .ready
        stateBeforeResync = nil
    }

    public func synchronizeNow(to playbackPosition: TimeInterval) throws {
        try beginResyncing()
        try completeResync(at: playbackPosition)
    }

    public func adjustSyncOffset(by delta: TimeInterval) async throws {
        try await setSyncOffset(syncOffsetSeconds + delta)
    }

    public func setSyncOffset(_ correction: TimeInterval) async throws {
        guard timeline != nil else { throw LyricsSynchronizationEngineError.missingLyrics }
        guard let track = currentTrack else {
            throw LyricsSynchronizationEngineError.missingTrack
        }
        syncOffsetSeconds = correction
        await correctionStore.saveCorrection(correction, forTrackID: track.id)
    }

    /// Aligns the currently displayed line's start timestamp with the current
    /// monotonic lyric-clock position. This is the domain behavior behind the
    /// manual `Sync Now` control.
    public func syncActiveLineNow() async throws {
        guard let timeline else { throw LyricsSynchronizationEngineError.missingLyrics }
        let playbackPosition = clock.position(at: timeSource.now)
        let current = timeline.position(
            at: playbackPosition,
            syncOffsetSeconds: syncOffsetSeconds
        )
        guard let index = current.activeLineIndex else {
            throw LyricsSynchronizationEngineError.lineOutOfBounds
        }
        try await alignLine(at: index, with: playbackPosition)
    }

    public func moveToPreviousLine() async throws {
        guard let timeline else { throw LyricsSynchronizationEngineError.missingLyrics }
        let playbackPosition = clock.position(at: timeSource.now)
        let current = timeline.position(
            at: playbackPosition,
            syncOffsetSeconds: syncOffsetSeconds
        )
        guard let currentIndex = current.activeLineIndex, currentIndex > 0 else {
            throw LyricsSynchronizationEngineError.lineOutOfBounds
        }
        try await alignLine(at: currentIndex - 1, with: playbackPosition)
    }

    public func moveToNextLine() async throws {
        guard let timeline else { throw LyricsSynchronizationEngineError.missingLyrics }
        let playbackPosition = clock.position(at: timeSource.now)
        let current = timeline.position(
            at: playbackPosition,
            syncOffsetSeconds: syncOffsetSeconds
        )
        let nextIndex = current.activeLineIndex.map { $0 + 1 } ?? 0
        guard timeline.line(at: nextIndex) != nil else {
            throw LyricsSynchronizationEngineError.lineOutOfBounds
        }
        try await alignLine(at: nextIndex, with: playbackPosition)
    }

    public func fail(_ description: String) {
        lastErrorDescription = description
        state = .error
    }

    public func stop() {
        resetSessionData()
        state = .idle
    }

    public func snapshot() -> LyricsSynchronizationSnapshot {
        let playbackPosition = clock.position(at: timeSource.now)
        return LyricsSynchronizationSnapshot(
            state: state,
            track: currentTrack,
            timelinePosition: timeline?.position(
                at: playbackPosition,
                syncOffsetSeconds: syncOffsetSeconds
            ),
            playbackPosition: playbackPosition,
            syncOffsetSeconds: syncOffsetSeconds,
            clockState: clock.state,
            lastErrorDescription: lastErrorDescription
        )
    }

    public func glassesDisplayModel() -> GlassesDisplayModel? {
        guard let track = currentTrack else { return nil }
        let currentSnapshot = snapshot()
        let lyricPosition = currentSnapshot.timelinePosition
        return GlassesDisplayModel(
            trackTitle: track.title,
            artist: track.artist,
            previousLine: lyricPosition?.previousLine?.text,
            activeLine: lyricPosition?.activeLine?.text ?? "",
            nextLine: lyricPosition?.nextLine?.text,
            progress: lyricPosition?.progress,
            status: displayStatus(for: state)
        )
    }

    private func alignLine(
        at index: Int,
        with playbackPosition: TimeInterval
    ) async throws {
        guard let timeline else { throw LyricsSynchronizationEngineError.missingLyrics }
        guard let correction = timeline.correctionToAlignLine(
            at: index,
            with: playbackPosition
        ) else {
            throw LyricsSynchronizationEngineError.lineOutOfBounds
        }
        try await setSyncOffset(correction)
    }

    private func transitionError(
        to target: LyricsSynchronizationState
    ) -> LyricsSynchronizationEngineError {
        .invalidTransition(from: state, to: target)
    }

    private func resetSessionData() {
        currentTrack = nil
        timeline = nil
        syncOffsetSeconds = 0
        lastErrorDescription = nil
        stateBeforeResync = nil
        clock.stop()
    }

    private func displayStatus(
        for state: LyricsSynchronizationState
    ) -> GlassesDisplayStatus {
        switch state {
        case .idle, .identified, .ready: return .idle
        case .listening: return .listening
        case .identifying, .resyncing: return .identifying
        case .fetchingLyrics: return .loadingLyrics
        case .playing: return .displayingLyrics
        case .paused: return .paused
        case .error: return .error
        }
    }
}
