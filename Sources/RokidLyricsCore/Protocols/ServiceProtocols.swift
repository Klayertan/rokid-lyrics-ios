import Foundation

public struct CapturedAudioFrame: Equatable, Sendable {
    /// Interleaved, normalized PCM samples in `-1...1`.
    public let samples: [Float]
    public let sampleRate: Double
    public let channelCount: Int
    public let capturedAtMonotonicTime: TimeInterval

    public init(
        samples: [Float],
        sampleRate: Double,
        channelCount: Int,
        capturedAtMonotonicTime: TimeInterval
    ) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.capturedAtMonotonicTime = capturedAtMonotonicTime
    }
}

public typealias CapturedAudioStream = AsyncThrowingStream<CapturedAudioFrame, Error>

public protocol AudioCaptureService: Sendable {
    /// Starts an ephemeral PCM stream. Implementations must not persist frames
    /// and must make active microphone capture visible to the user.
    func startCapture() async throws -> CapturedAudioStream
    func stopCapture() async
}

public protocol TrackIdentificationService: Sendable {
    /// Identifies the currently audible track from a public, supported audio
    /// capture path and honors stream/task cancellation.
    func identifyTrack(from audioFrames: CapturedAudioStream) async throws -> TrackIdentity
}

public extension TrackIdentificationService {
    func identifyTrack(using audioCapture: any AudioCaptureService) async throws -> TrackIdentity {
        let stream = try await audioCapture.startCapture()
        do {
            let identity = try await identifyTrack(from: stream)
            await audioCapture.stopCapture()
            return identity
        } catch {
            await audioCapture.stopCapture()
            throw error
        }
    }
}

public protocol LyricsProvider: Sendable {
    var providerName: String { get }

    /// Returns provider candidates. Selection remains in the domain layer so
    /// callers can surface ambiguous results instead of silently guessing.
    func searchLyrics(for query: LyricsQuery) async throws -> [LyricsCandidate]
}

public struct AudioAlignmentEstimate: Codable, Equatable, Sendable {
    public let playbackPosition: TimeInterval
    public let measuredAtMonotonicTime: TimeInterval
    public let confidence: Double?
    public let source: String

    public init(
        playbackPosition: TimeInterval,
        measuredAtMonotonicTime: TimeInterval,
        confidence: Double? = nil,
        source: String
    ) {
        self.playbackPosition = playbackPosition
        self.measuredAtMonotonicTime = measuredAtMonotonicTime
        self.confidence = confidence
        self.source = source
    }
}

/// Extension point for future signal-based alignment. No speculative
/// implementation is supplied by the core module.
public protocol AudioAlignmentService: Sendable {
    func estimateAlignment(for track: TrackIdentity) async throws -> AudioAlignmentEstimate
}
