import Foundation
import XCTest
@testable import RokidLyricsCore

final class DomainModelTests: XCTestCase {
    func testTrackIdentityCodablePreservesRecognitionPlaybackPosition() throws {
        let original = TrackIdentity(
            id: "synthetic-id",
            title: "Synthetic Song",
            artist: "Test Artist",
            album: "Synthetic Album",
            artworkURL: URL(string: "https://example.invalid/artwork.png"),
            duration: 180,
            recognizedAt: Date(timeIntervalSince1970: 123),
            playbackPositionAtRecognition: 42.5,
            identification: TrackIdentificationMetadata(
                source: "test",
                confidence: nil,
                sourceIdentifier: "source-id"
            )
        )

        let decoded = try JSONDecoder().decode(
            TrackIdentity.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.playbackPositionAtRecognition, 42.5)
        XCTAssertNil(decoded.identification.confidence)
    }

    func testDisplayProgressIsClamped() {
        let belowZero = GlassesDisplayModel(
            trackTitle: "Synthetic Song",
            artist: "Test Artist",
            activeLine: "Test line",
            progress: -1,
            status: .displayingLyrics
        )
        let aboveOne = GlassesDisplayModel(
            trackTitle: "Synthetic Song",
            artist: "Test Artist",
            activeLine: "Test line",
            progress: 2,
            status: .displayingLyrics
        )

        XCTAssertEqual(belowZero.progress, 0)
        XCTAssertEqual(aboveOne.progress, 1)
    }

    func testDisplayPreferencesHaveSafeDefaultsAndClamping() {
        XCTAssertEqual(GlassesDisplayPreferences(), GlassesDisplayPreferences(
            fontScale: 1,
            visibleLineCount: 3,
            verticalPosition: 0.5,
            showPreviousLine: true,
            showNextLine: true
        ))

        let clamped = GlassesDisplayPreferences(
            fontScale: 50,
            visibleLineCount: 10,
            verticalPosition: -2
        )
        XCTAssertEqual(clamped.fontScale, 2)
        XCTAssertEqual(clamped.visibleLineCount, 3)
        XCTAssertEqual(clamped.verticalPosition, 0)
    }

    func testInMemoryCorrectionStoreRoundTripAndRemoval() async {
        let store = InMemorySyncCorrectionStore()

        await store.saveCorrection(1.5, forTrackID: "track")
        var correction = await store.correction(forTrackID: "track")
        XCTAssertEqual(correction, 1.5)

        await store.removeCorrection(forTrackID: "track")
        correction = await store.correction(forTrackID: "track")
        XCTAssertNil(correction)
    }
}
