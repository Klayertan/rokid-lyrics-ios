import Foundation

public enum TrackIdentificationUnavailableError: Error, Equatable, LocalizedError, Sendable {
    case recognitionUnavailable

    public var errorDescription: String? {
        "Automatic recognition is unavailable in this build. Search for the song manually."
    }
}

/// Selected instead of a real backend when a build configuration compiles
/// without automatic recognition (for example, Personal Team mode with
/// ShazamKit disabled). It never touches the audio stream; it fails fast
/// with one typed, user-readable error instead of attempting capture.
public struct UnavailableTrackIdentificationService: TrackIdentificationService, Sendable {
    public init() {}

    public func identifyTrack(from audioFrames: CapturedAudioStream) async throws -> TrackIdentity {
        throw TrackIdentificationUnavailableError.recognitionUnavailable
    }
}
