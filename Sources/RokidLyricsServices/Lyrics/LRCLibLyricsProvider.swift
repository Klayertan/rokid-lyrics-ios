import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import RokidLyricsCore

public enum LRCLibError: Error, Equatable, LocalizedError, Sendable {
    case invalidEndpoint
    case invalidResponse
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The LRCLIB request URL could not be constructed."
        case .invalidResponse:
            return "LRCLIB returned an invalid HTTP response."
        case let .decodingFailed(message):
            return "LRCLIB returned data that could not be decoded: \(message)"
        }
    }
}

/// Runtime-only LRCLIB client for the documented `/api/search` endpoint.
/// It deliberately does not publish lyrics or download the database.
public struct LRCLibLyricsProvider: LyricsProvider, Sendable {
    private struct Record: Decodable {
        let id: Int
        let trackName: String
        let artistName: String
        let albumName: String?
        let duration: TimeInterval?
        let instrumental: Bool
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    public let providerName = "LRCLIB"

    private let baseURL: URL
    private let client: any HTTPClient
    private let cache: (any LyricsCache)?
    private let userAgent: String

    public init(
        baseURL: URL = URL(string: "https://lrclib.net")!,
        client: any HTTPClient = URLSessionHTTPClient(),
        cache: (any LyricsCache)? = nil,
        userAgent: String = "RokidLyrics/0.1.0 (https://github.com/Klayertan/rokid-lyrics-ios)"
    ) {
        self.baseURL = baseURL
        self.client = client
        self.cache = cache
        self.userAgent = userAgent
    }

    public func searchLyrics(for query: LyricsQuery) async throws -> [LyricsCandidate] {
        let cacheKey = Self.cacheKey(for: query)
        if let cached = await cache?.candidates(for: cacheKey) {
            return cached
        }

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("api/search"),
            resolvingAgainstBaseURL: false
        ) else {
            throw LRCLibError.invalidEndpoint
        }

        var items = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
        ]
        if let album = query.album?.trimmingCharacters(in: .whitespacesAndNewlines), !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        components.queryItems = items

        guard let url = components.url else { throw LRCLibError.invalidEndpoint }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let response = try await client.data(for: request)
        guard (200...299).contains(response.response.statusCode) else {
            throw HTTPClientError.unacceptableStatus(
                code: response.response.statusCode,
                retryAfterSeconds: nil
            )
        }

        let records: [Record]
        do {
            records = try JSONDecoder().decode([Record].self, from: response.data)
        } catch {
            throw LRCLibError.decodingFailed(error.localizedDescription)
        }

        let candidates = records.map {
            LyricsCandidate(
                id: String($0.id),
                providerName: providerName,
                trackTitle: $0.trackName,
                artistName: $0.artistName,
                albumName: $0.albumName,
                duration: $0.duration,
                plainLyrics: $0.plainLyrics,
                synchronizedLyrics: $0.syncedLyrics,
                isInstrumental: $0.instrumental
            )
        }
        await cache?.store(candidates, for: cacheKey)
        return candidates
    }

    private static func cacheKey(for query: LyricsQuery) -> String {
        let duration = query.duration.map { String($0) } ?? ""
        let joined = [query.title, query.artist, query.album ?? "", duration]
            .joined(separator: "\u{1f}")
        return joined.precomposedStringWithCanonicalMapping.lowercased()
    }
}
