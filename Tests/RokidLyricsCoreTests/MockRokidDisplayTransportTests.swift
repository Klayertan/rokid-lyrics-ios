import XCTest
@testable import RokidLyricsCore

final class MockRokidDisplayTransportTests: XCTestCase {
    func testConnectSendCoalesceClearAndDisconnect() async throws {
        let transport = MockRokidDisplayTransport()
        let display = displayModel(activeLine: "First test line")

        try await transport.connect()
        var state = await transport.connectionState
        XCTAssertEqual(state, .connected)

        try await transport.sendDisplayState(display)
        try await transport.sendDisplayState(display)
        var history = await transport.sentDisplayStates
        XCTAssertEqual(history, [display])

        try await transport.sendDisplayState(displayModel(activeLine: "Second test line"))
        history = await transport.sentDisplayStates
        XCTAssertEqual(history.count, 2)

        try await transport.clearDisplay()
        let last = await transport.lastDisplayState
        let clearCount = await transport.clearCount
        XCTAssertNil(last)
        XCTAssertEqual(clearCount, 1)

        await transport.disconnect()
        state = await transport.connectionState
        XCTAssertEqual(state, .disconnected)
    }

    func testSendWhileDisconnectedThrows() async {
        let transport = MockRokidDisplayTransport()

        do {
            try await transport.sendDisplayState(displayModel(activeLine: "Test line"))
            XCTFail("Expected not-connected error")
        } catch let error as MockRokidDisplayTransportError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConnectionFailureIsExplicit() async {
        let transport = MockRokidDisplayTransport(connectionShouldFail: true)

        do {
            try await transport.connect()
            XCTFail("Expected mock failure")
        } catch let error as MockRokidDisplayTransportError {
            XCTAssertEqual(error, .connectionFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let state = await transport.connectionState
        XCTAssertEqual(state, .failed(message: "Mock connection failed"))
    }

    func testSendFailureDoesNotRecordPayload() async throws {
        let transport = MockRokidDisplayTransport(sendShouldFail: true)
        try await transport.connect()

        do {
            try await transport.sendDisplayState(displayModel(activeLine: "Test line"))
            XCTFail("Expected mock send failure")
        } catch let error as MockRokidDisplayTransportError {
            XCTAssertEqual(error, .sendFailed)
        }
        let history = await transport.sentDisplayStates
        XCTAssertTrue(history.isEmpty)
    }

    private func displayModel(activeLine: String) -> GlassesDisplayModel {
        GlassesDisplayModel(
            trackTitle: "Synthetic Song",
            artist: "Test Artist",
            previousLine: "Previous test line",
            activeLine: activeLine,
            nextLine: "Next test line",
            progress: 0.5,
            status: .displayingLyrics
        )
    }
}
