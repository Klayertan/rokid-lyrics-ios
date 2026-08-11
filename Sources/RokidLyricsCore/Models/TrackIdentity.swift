import Foundation

/// Metadata about how a track was identified.
///
/// `confidence` is optional by design. Identification adapters must leave it `nil`
/// when their backing service does not publish a confidence value.
public struct TrackIdentificationMetadata: Codable, Equatable, Sendable {
    public let source: String
    public let confidence: Double?
    public let sourceIdentifier: String?
    public let attributes: [String: String]

    public init(
        source: String,
        confidence: Double? = nil,
        sourceIdentifier: String? = nil,
        attributes: [String: String] = [:]
    ) {
        self.source = source
        self.confidence = confidence
        self.sourceIdentifier = sourceIdentifier
        self.attributes = attributes
    }
}

public struct TrackIdentity: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let duration: TimeInterval?
    public let recognizedAt: Date
    /// Provider-estimated playback position at `recognizedAt`, when exposed by
    /// a documented API (for example ShazamKit's predicted match offset).
    public let playbackPositionAtRecognition: TimeInterval?
    public let identification: TrackIdentificationMetadata

    public init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        duration: TimeInterval? = nil,
        recognizedAt: Date,
        playbackPositionAtRecognition: TimeInterval? = nil,
        identification: TrackIdentificationMetadata
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
        self.recognizedAt = recognizedAt
        self.playbackPositionAtRecognition = playbackPositionAtRecognition
        self.identification = identification
    }
}
