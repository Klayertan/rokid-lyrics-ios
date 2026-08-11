import Foundation

public enum SharedTrackParseQuality: String, Codable, Equatable, Sendable {
    case explicitFields
    case conservativeTextPattern
    case insufficient
}

public struct SharedTrackDraft: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var title: String?
    public var artist: String?
    public var url: URL?
    public let rawText: String?
    public let parseQuality: SharedTrackParseQuality
    public let receivedAt: Date

    public var requiresConfirmation: Bool {
        parseQuality != .explicitFields || title?.isEmpty != false || artist?.isEmpty != false
    }

    public init(
        schemaVersion: Int = 1,
        title: String?,
        artist: String?,
        url: URL?,
        rawText: String?,
        parseQuality: SharedTrackParseQuality,
        receivedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.artist = artist
        self.url = url
        self.rawText = rawText
        self.parseQuality = parseQuality
        self.receivedAt = receivedAt
    }
}

/// Conservative parser for standard iOS share items. It does not depend on a
/// YouTube Music hostname or undocumented URL shape.
public enum SharedTrackParser {
    public static func parse(
        text: String?,
        url: URL?,
        explicitTitle: String? = nil,
        explicitArtist: String? = nil
    ) -> SharedTrackDraft {
        let safeURL = validatedWebURL(url)
        let suppliedTitle = clean(explicitTitle)
        let suppliedArtist = clean(explicitArtist)

        if let suppliedTitle, let suppliedArtist {
            return SharedTrackDraft(
                title: suppliedTitle,
                artist: suppliedArtist,
                url: safeURL,
                rawText: text,
                parseQuality: .explicitFields
            )
        }

        let meaningfulLines = (text ?? "")
            .components(separatedBy: .newlines)
            .compactMap(clean)
            .filter { validatedWebURL(URL(string: $0)) == nil }

        if meaningfulLines.count == 2 {
            return SharedTrackDraft(
                title: meaningfulLines[0],
                artist: meaningfulLines[1],
                url: safeURL,
                rawText: text,
                parseQuality: .conservativeTextPattern
            )
        }

        if meaningfulLines.count == 1,
            let pair = splitSingleLine(meaningfulLines[0])
        {
            return SharedTrackDraft(
                title: pair.title,
                artist: pair.artist,
                url: safeURL,
                rawText: text,
                parseQuality: .conservativeTextPattern
            )
        }

        return SharedTrackDraft(
            title: suppliedTitle ?? meaningfulLines.first,
            artist: suppliedArtist,
            url: safeURL,
            rawText: text,
            parseQuality: .insufficient
        )
    }

    private static func splitSingleLine(_ text: String) -> (title: String, artist: String)? {
        for separator in [" — ", " – ", " - "] {
            let parts = text.components(separatedBy: separator)
            guard parts.count == 2, let title = clean(parts[0]), let artist = clean(parts[1]) else {
                continue
            }
            return (title, artist)
        }
        return nil
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func validatedWebURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }
}
