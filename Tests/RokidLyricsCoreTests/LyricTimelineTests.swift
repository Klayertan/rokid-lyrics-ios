import XCTest
@testable import RokidLyricsCore

final class LyricTimelineTests: XCTestCase {
    private let document = LyricDocument(
        lines: [
            LyricLine(id: 0, timestamp: 1, text: "First test line"),
            LyricLine(id: 1, timestamp: 2, text: "Second test line"),
            LyricLine(id: 2, timestamp: 4, text: "Third test line")
        ]
    )

    func testBeforeFirstLine() {
        let position = LyricTimeline(document: document).position(at: 0.5)

        XCTAssertNil(position.previousLine)
        XCTAssertNil(position.activeLine)
        XCTAssertEqual(position.nextLine?.text, "First test line")
    }

    func testAtExactTimestamp() {
        let position = LyricTimeline(document: document).position(at: 2)

        XCTAssertEqual(position.previousLine?.text, "First test line")
        XCTAssertEqual(position.activeLine?.text, "Second test line")
        XCTAssertEqual(position.nextLine?.text, "Third test line")
    }

    func testBetweenLines() {
        let position = LyricTimeline(document: document).position(at: 3.999)

        XCTAssertEqual(position.activeLine?.text, "Second test line")
    }

    func testAfterFinalLine() {
        let position = LyricTimeline(document: document).position(at: 20)

        XCTAssertEqual(position.previousLine?.text, "Second test line")
        XCTAssertEqual(position.activeLine?.text, "Third test line")
        XCTAssertNil(position.nextLine)
    }

    func testPositiveCorrectionAdvancesLyrics() {
        let position = LyricTimeline(document: document).position(
            at: 1.2,
            syncOffsetSeconds: 1
        )

        XCTAssertEqual(position.activeLine?.text, "Second test line")
    }

    func testNegativeCorrectionDelaysLyrics() {
        let position = LyricTimeline(document: document).position(
            at: 2.5,
            syncOffsetSeconds: -2
        )

        XCTAssertNil(position.activeLine)
        XCTAssertEqual(position.nextLine?.text, "First test line")
    }

    func testEmbeddedOffsetMovesLyricsLater() {
        let offsetDocument = LyricDocument(
            lines: [LyricLine(timestamp: 1, text: "First test line")],
            embeddedOffsetSeconds: 0.5
        )
        let timeline = LyricTimeline(document: offsetDocument)

        XCTAssertNil(timeline.position(at: 1.49).activeLine)
        XCTAssertEqual(timeline.position(at: 1.5).activeLine?.text, "First test line")
    }

    func testTrackProgressIsClamped() {
        let timeline = LyricTimeline(document: document, trackDuration: 10)

        XCTAssertEqual(timeline.position(at: -1).progress, 0)
        XCTAssertEqual(timeline.position(at: 5).progress, 0.5)
        XCTAssertEqual(timeline.position(at: 15).progress, 1)
    }

    func testCorrectionToAlignLineAccountsForEmbeddedOffset() {
        let offsetDocument = LyricDocument(
            lines: [LyricLine(timestamp: 5, text: "First test line")],
            embeddedOffsetSeconds: 0.25
        )
        let correction = LyricTimeline(document: offsetDocument)
            .correctionToAlignLine(at: 0, with: 3)

        XCTAssertEqual(correction, 2.25)
    }
}

