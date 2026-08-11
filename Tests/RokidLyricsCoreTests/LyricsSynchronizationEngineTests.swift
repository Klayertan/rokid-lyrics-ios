import Foundation
import XCTest
@testable import RokidLyricsCore

final class LyricsSynchronizationEngineTests: XCTestCase {
    func testFullStateMachineAndTimelineAdvance() async throws {
        let time = ManualMonotonicTimeSource(now: 100)
        let engine = LyricsSynchronizationEngine(timeSource: time)

        try await engine.startListening()
        try await engine.beginIdentification()
        try await engine.setIdentifiedTrack(track(playbackPosition: 1))
        try await engine.beginFetchingLyrics()
        try await engine.setLyrics(document())
        try await engine.play()

        var snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.state, .playing)
        XCTAssertEqual(snapshot.timelinePosition?.activeLine?.text, "First test line")

        time.advance(by: 1.1)
        snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.timelinePosition?.activeLine?.text, "Second test line")
        XCTAssertEqual(snapshot.playbackPosition, 2.1, accuracy: 0.000_1)
    }

    func testRecognitionPlaybackPositionSeedsClock() async throws {
        let time = ManualMonotonicTimeSource(now: 5)
        let engine = LyricsSynchronizationEngine(timeSource: time)

        try await prepareReadyEngine(engine, playbackPosition: 12.5)
        time.advance(by: 2)
        let snapshot = await engine.snapshot()

        XCTAssertEqual(snapshot.playbackPosition, 14.5)
        XCTAssertEqual(snapshot.clockState, .running)
    }

    func testPauseAndResumeKeepPositionStable() async throws {
        let time = ManualMonotonicTimeSource(now: 10)
        let engine = LyricsSynchronizationEngine(timeSource: time)
        try await prepareReadyEngine(engine, playbackPosition: 0)
        try await engine.play()

        time.advance(by: 1.5)
        try await engine.pause()
        time.advance(by: 20)
        var snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.playbackPosition, 1.5, accuracy: 0.000_1)
        XCTAssertEqual(snapshot.state, .paused)

        try await engine.play()
        time.advance(by: 0.5)
        snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.playbackPosition, 2, accuracy: 0.000_1)
    }

    func testSeekWhilePlaying() async throws {
        let time = ManualMonotonicTimeSource(now: 0)
        let engine = LyricsSynchronizationEngine(timeSource: time)
        try await prepareReadyEngine(engine, playbackPosition: 0)
        try await engine.play()
        try await engine.seek(to: 2.5)

        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.timelinePosition?.activeLine?.text, "Second test line")
    }

    func testOffsetAdjustmentsAndLineNavigationPersistPerTrack() async throws {
        let time = ManualMonotonicTimeSource(now: 0)
        let store = InMemorySyncCorrectionStore()
        let engine = LyricsSynchronizationEngine(timeSource: time, correctionStore: store)
        try await prepareReadyEngine(engine, playbackPosition: 1.2)

        try await engine.adjustSyncOffset(by: 1)
        var snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.syncOffsetSeconds, 1)
        XCTAssertEqual(snapshot.timelinePosition?.activeLine?.text, "Second test line")

        try await engine.moveToNextLine()
        snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.timelinePosition?.activeLine?.text, "Third test line")
        let storedCorrection = await store.correction(forTrackID: "track-id")
        let saved = try XCTUnwrap(storedCorrection)
        XCTAssertEqual(saved, 2.8, accuracy: 0.000_1)

        try await engine.moveToPreviousLine()
        snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.timelinePosition?.activeLine?.text, "Second test line")
    }

    func testLoadsStoredCorrectionWhenTrackIsIdentified() async throws {
        let store = InMemorySyncCorrectionStore(corrections: ["track-id": -1.25])
        let engine = LyricsSynchronizationEngine(correctionStore: store)

        try await engine.startListening()
        try await engine.beginIdentification()
        try await engine.setIdentifiedTrack(track(playbackPosition: 2))

        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.syncOffsetSeconds, -1.25)
    }

    func testSyncActiveLineNowAlignsItsStart() async throws {
        let time = ManualMonotonicTimeSource(now: 10)
        let engine = LyricsSynchronizationEngine(timeSource: time)
        try await prepareReadyEngine(engine, playbackPosition: 1.8)

        try await engine.syncActiveLineNow()
        let snapshot = await engine.snapshot()

        XCTAssertEqual(snapshot.syncOffsetSeconds, -0.8, accuracy: 0.000_1)
        XCTAssertEqual(snapshot.timelinePosition?.activeLine?.text, "First test line")
        let adjustedPosition = try XCTUnwrap(snapshot.timelinePosition?.adjustedPosition)
        XCTAssertEqual(adjustedPosition, 1, accuracy: 0.000_1)
    }

    func testResyncRestoresPlayingState() async throws {
        let time = ManualMonotonicTimeSource(now: 1)
        let engine = LyricsSynchronizationEngine(timeSource: time)
        try await prepareReadyEngine(engine, playbackPosition: 0)
        try await engine.play()
        try await engine.beginResyncing()

        var state = await engine.state
        XCTAssertEqual(state, .resyncing)

        try await engine.completeResync(at: 4)
        state = await engine.state
        let snapshot = await engine.snapshot()
        XCTAssertEqual(state, .playing)
        XCTAssertEqual(snapshot.playbackPosition, 4)
    }

    func testInvalidStateTransitionThrows() async throws {
        let engine = LyricsSynchronizationEngine()

        do {
            try await engine.beginIdentification()
            XCTFail("Expected invalid transition")
        } catch let error as LyricsSynchronizationEngineError {
            XCTAssertEqual(
                error,
                .invalidTransition(from: .idle, to: .identifying)
            )
        }
    }

    func testStopClearsSession() async throws {
        let engine = LyricsSynchronizationEngine()
        try await prepareReadyEngine(engine, playbackPosition: 0)
        await engine.stop()

        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.state, .idle)
        XCTAssertNil(snapshot.track)
        XCTAssertNil(snapshot.timelinePosition)
        XCTAssertEqual(snapshot.syncOffsetSeconds, 0)
    }

    func testGlassesDisplayModelUsesCurrentThreeLines() async throws {
        let time = ManualMonotonicTimeSource(now: 0)
        let engine = LyricsSynchronizationEngine(timeSource: time)
        try await prepareReadyEngine(engine, playbackPosition: 2.5)
        try await engine.play()

        let display = await engine.glassesDisplayModel()
        XCTAssertEqual(display?.previousLine, "First test line")
        XCTAssertEqual(display?.activeLine, "Second test line")
        XCTAssertEqual(display?.nextLine, "Third test line")
        XCTAssertEqual(display?.status, .displayingLyrics)
    }

    private func prepareReadyEngine(
        _ engine: LyricsSynchronizationEngine,
        playbackPosition: TimeInterval
    ) async throws {
        try await engine.startListening()
        try await engine.beginIdentification()
        try await engine.setIdentifiedTrack(track(playbackPosition: playbackPosition))
        try await engine.beginFetchingLyrics()
        try await engine.setLyrics(document())
    }

    private func track(playbackPosition: TimeInterval?) -> TrackIdentity {
        TrackIdentity(
            id: "track-id",
            title: "Synthetic Song",
            artist: "Test Artist",
            duration: 10,
            recognizedAt: Date(timeIntervalSince1970: 1_000),
            playbackPositionAtRecognition: playbackPosition,
            identification: TrackIdentificationMetadata(source: "test")
        )
    }

    private func document() -> LyricDocument {
        LyricDocument(
            lines: [
                LyricLine(id: 0, timestamp: 1, text: "First test line"),
                LyricLine(id: 1, timestamp: 2, text: "Second test line"),
                LyricLine(id: 2, timestamp: 4, text: "Third test line"),
            ]
        )
    }
}

private final class ManualMonotonicTimeSource: MonotonicTimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval

    init(now: TimeInterval) {
        value = now
    }

    var now: TimeInterval {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { value += interval }
    }
}
