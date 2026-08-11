import Foundation

public enum GlassesDisplayStatus: String, Codable, Equatable, Sendable {
    case idle
    case listening
    case identifying
    case loadingLyrics
    case displayingLyrics
    case paused
    case lyricsUnavailable
    case error
}

/// SDK-neutral rendering preferences. Concrete transports should honor only
/// capabilities verified for their display and safely ignore unsupported ones.
public struct GlassesDisplayPreferences: Codable, Equatable, Sendable {
    public let fontScale: Double
    public let visibleLineCount: Int

    /// Abstract top-to-bottom position in `0...1`; it is intentionally not an
    /// SDK coordinate. A transport may ignore this value when positioning is
    /// unsupported.
    public let verticalPosition: Double
    public let showPreviousLine: Bool
    public let showNextLine: Bool

    public init(
        fontScale: Double = 1,
        visibleLineCount: Int = 3,
        verticalPosition: Double = 0.5,
        showPreviousLine: Bool = true,
        showNextLine: Bool = true
    ) {
        self.fontScale = min(max(fontScale, 0.5), 2)
        self.visibleLineCount = min(max(visibleLineCount, 1), 3)
        self.verticalPosition = min(max(verticalPosition, 0), 1)
        self.showPreviousLine = showPreviousLine
        self.showNextLine = showNextLine
    }
}

/// Complete provider- and SDK-independent state to be rendered on the glasses.
public struct GlassesDisplayModel: Codable, Equatable, Sendable {
    public let trackTitle: String
    public let artist: String
    public let previousLine: String?
    public let activeLine: String
    public let nextLine: String?
    public let progress: Double?
    public let status: GlassesDisplayStatus
    public let preferences: GlassesDisplayPreferences

    public init(
        trackTitle: String,
        artist: String,
        previousLine: String? = nil,
        activeLine: String,
        nextLine: String? = nil,
        progress: Double? = nil,
        status: GlassesDisplayStatus,
        preferences: GlassesDisplayPreferences = GlassesDisplayPreferences()
    ) {
        self.trackTitle = trackTitle
        self.artist = artist
        self.previousLine = previousLine
        self.activeLine = activeLine
        self.nextLine = nextLine
        self.progress = progress.map { min(max($0, 0), 1) }
        self.status = status
        self.preferences = preferences
    }
}
