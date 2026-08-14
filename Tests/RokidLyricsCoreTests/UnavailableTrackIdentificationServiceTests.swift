import Testing

@testable import RokidLyricsCore

@Suite("Unavailable track identification service")
struct UnavailableTrackIdentificationServiceTests {
    @Test("fails fast with a user-readable error instead of reading the audio stream")
    func failsFastWithoutReadingTheStream() async {
        let service = UnavailableTrackIdentificationService()
        let stream: CapturedAudioStream = AsyncThrowingStream { continuation in
            continuation.finish(throwing: TestOnlyStreamMustNotBeReadError())
        }

        await #expect(throws: TrackIdentificationUnavailableError.recognitionUnavailable) {
            try await service.identifyTrack(from: stream)
        }
    }

    @Test("exposes a manual-search explanation instead of a raw system message")
    func explainsTheManualFallback() {
        let error = TrackIdentificationUnavailableError.recognitionUnavailable
        let expected = "Automatic recognition is unavailable in this build. Search for the song manually."
        #expect(error.errorDescription == expected)
    }
}

private struct TestOnlyStreamMustNotBeReadError: Error {}
