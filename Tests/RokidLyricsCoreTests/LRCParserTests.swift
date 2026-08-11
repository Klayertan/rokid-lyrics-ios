import XCTest
@testable import RokidLyricsCore

final class LRCParserTests: XCTestCase {
    private let parser = LRCParser()

    func testParsesHundredthsTimestamp() {
        let document = parser.parse("[00:01.25]First test line")

        XCTAssertEqual(document.lines.count, 1)
        XCTAssertEqual(document.lines[0].timestamp, 1.25, accuracy: 0.000_1)
        XCTAssertEqual(document.lines[0].text, "First test line")
    }

    func testParsesMillisecondsTimestamp() {
        let document = parser.parse("[12:34.567]Second test line")

        XCTAssertEqual(document.lines[0].timestamp, 754.567, accuracy: 0.000_1)
    }

    func testParsesOneDigitFractionAndTimestampWithoutFraction() {
        let document = parser.parse("[0:01.5]One\n[00:02]Two")

        XCTAssertEqual(document.lines.map(\.timestamp), [1.5, 2])
    }

    func testParsesHourTimestamp() {
        let document = parser.parse("[1:02:03.004]Long synthetic track")

        XCTAssertEqual(document.lines[0].timestamp, 3_723.004, accuracy: 0.000_1)
    }

    func testExpandsMultipleTimestamps() {
        let document = parser.parse("[00:01.00][00:03.500]Repeated test line")

        XCTAssertEqual(document.lines.map(\.timestamp), [1, 3.5])
        XCTAssertEqual(document.lines.map(\.text), ["Repeated test line", "Repeated test line"])
    }

    func testIgnoresMalformedAndUntimedLines() {
        let document = parser.parse(
            """
            [bad]Ignored
            [00:75.00]Also ignored
            Untimed text
            [00:02.00]Valid synthetic line
            """
        )

        XCTAssertEqual(document.lines.count, 1)
        XCTAssertEqual(document.lines[0].text, "Valid synthetic line")
    }

    func testPreservesTimestampedEmptyLineAndIgnoresPhysicalEmptyLine() {
        let document = parser.parse("[00:01.00]\n\n[00:02.00]Second test line")

        XCTAssertEqual(document.lines.count, 2)
        XCTAssertEqual(document.lines[0].text, "")
    }

    func testPreservesUnicodeText() {
        let document = parser.parse(
            "[00:01.00]日本語テスト\n[00:02.00]中文测试\n[00:03.00]한국어 테스트"
        )

        XCTAssertEqual(
            document.lines.map(\.text),
            ["日本語テスト", "中文测试", "한국어 테스트"]
        )
    }

    func testSortsLinesAndKeepsDuplicateTimestampsStable() {
        let document = parser.parse(
            """
            [00:03.00]Third
            [00:01.00]First A
            [00:01.00]First B
            [00:02.00]Second
            """
        )

        XCTAssertEqual(document.lines.map(\.text), ["First A", "First B", "Second", "Third"])
        XCTAssertEqual(document.lines.map(\.id), [1, 2, 3, 0])
    }

    func testParsesMetadataAndOffset() {
        let document = parser.parse(
            """
            [ar:Synthetic Artist]
            [ti:Synthetic Song]
            [offset:+250]
            [00:01.00]First test line
            """
        )

        XCTAssertEqual(document.metadata["ar"], "Synthetic Artist")
        XCTAssertEqual(document.metadata["ti"], "Synthetic Song")
        XCTAssertEqual(document.embeddedOffsetSeconds, 0.25, accuracy: 0.000_1)
    }
}
