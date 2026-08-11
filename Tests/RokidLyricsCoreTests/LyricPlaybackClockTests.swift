import XCTest
@testable import RokidLyricsCore

final class LyricPlaybackClockTests: XCTestCase {
    func testRunningClockUsesMonotonicElapsedTime() {
        var clock = LyricPlaybackClock()
        clock.start(at: 10, monotonicTime: 100)

        XCTAssertEqual(clock.position(at: 102.5), 12.5, accuracy: 0.000_1)
    }

    func testPauseAndResume() {
        var clock = LyricPlaybackClock()
        clock.start(at: 1, monotonicTime: 10)
        clock.pause(at: 12)

        XCTAssertEqual(clock.position(at: 50), 3, accuracy: 0.000_1)
        XCTAssertEqual(clock.state, .paused)

        clock.resume(at: 60)
        XCTAssertEqual(clock.position(at: 62), 5, accuracy: 0.000_1)
    }

    func testSeekPreservesPauseState() {
        var clock = LyricPlaybackClock()
        clock.start(at: 0, monotonicTime: 0)
        clock.pause(at: 2)
        clock.seek(to: 20, at: 10)

        XCTAssertEqual(clock.state, .paused)
        XCTAssertEqual(clock.position(at: 100), 20)
    }

    func testBackwardTimeDoesNotMovePositionBackward() {
        var clock = LyricPlaybackClock()
        clock.start(at: 10, monotonicTime: 100)

        XCTAssertEqual(clock.position(at: 99), 10)
    }

    func testStopResetsClock() {
        var clock = LyricPlaybackClock()
        clock.start(at: 10, monotonicTime: 100)
        clock.stop()

        XCTAssertEqual(clock.state, .stopped)
        XCTAssertEqual(clock.position(at: 1_000), 0)
    }
}

