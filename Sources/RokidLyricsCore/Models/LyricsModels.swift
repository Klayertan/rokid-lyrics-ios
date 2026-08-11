import Foundation

public struct LyricsQuery: Codable, Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String?
    public let duration: TimeInterval?

    public init(
        title: String,
        artist: String,
        album: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    public init(track: TrackIdentity) {
        self.init(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration
        )
    }
}

/// A provider-neutral lyrics search result. Lyrics remain runtime data and
/// should not be persisted as source-controlled fixtures.
public struct LyricsCandidate: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let providerName: String
    public let trackTitle: String
    public let artistName: String
    public let albumName: String?
    public let duration: TimeInterval?
    public let plainLyrics: String?
    public let synchronizedLyrics: String?
    public let isInstrumental: Bool

    public init(
        id: String,
        providerName: String,
        trackTitle: String,
        artistName: String,
        albumName: String? = nil,
        duration: TimeInterval? = nil,
        plainLyrics: String? = nil,
        synchronizedLyrics: String? = nil,
        isInstrumental: Bool = false
    ) {
        self.id = id
        self.providerName = providerName
        self.trackTitle = trackTitle
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.plainLyrics = plainLyrics
        self.synchronizedLyrics = synchronizedLyrics
        self.isInstrumental = isInstrumental
    }
}

public struct LyricLine: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// Unique within a parsed `LyricDocument`; it also preserves source order
    /// when timestamps are duplicated.
    public let id: Int
    public let timestamp: TimeInterval
    public let text: String

    public init(id: Int = 0, timestamp: TimeInterval, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}

public struct LyricDocument: Codable, Equatable, Sendable {
    public let lines: [LyricLine]
    public let metadata: [String: String]

    /// Offset supplied by an LRC `[offset:...]` tag. A positive value moves
    /// lyric timestamps later.
    public let embeddedOffsetSeconds: TimeInterval

    public init(
        lines: [LyricLine],
        metadata: [String: String] = [:],
        embeddedOffsetSeconds: TimeInterval = 0
    ) {
        self.lines = lines.sorted {
            if $0.timestamp == $1.timestamp { return $0.id < $1.id }
            return $0.timestamp < $1.timestamp
        }
        self.metadata = metadata
        self.embeddedOffsetSeconds = embeddedOffsetSeconds
    }
}
