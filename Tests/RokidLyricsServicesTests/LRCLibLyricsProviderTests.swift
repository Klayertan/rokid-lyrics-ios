import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing
@testable import RokidLyricsCore
@testable import RokidLyricsServices

private struct StubHTTPClient: HTTPClient {
    let handler: @Sendable (URLRequest) async throws -> HTTPResponse

    func data(for request: URLRequest) async throws -> HTTPResponse {
        try await handler(request)
    }
}

private enum TestFailure: Error {
    case responseConstruction
}

@Suite("LRCLIB provider")
struct LRCLibLyricsProviderTests {
    @Test("decodes a documented search response and identifies the client")
    func successfulResponse() async throws {
        let body = Data(
            #"[{"id":42,"trackName":"Test Song","artistName":"Test Artist","albumName":"Test Album","duration":123.0,"instrumental":false,"plainLyrics":"First test line","syncedLyrics":"[00:01.00]First test line"}]"#
                .utf8
        )
        let client = StubHTTPClient { request in
            #expect(request.url?.path == "/api/search")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("RokidLyrics") == true)
            return try response(status: 200, data: body, request: request)
        }
        let provider = LRCLibLyricsProvider(client: client)

        let candidates = try await provider.searchLyrics(
            for: LyricsQuery(title: "Test Song", artist: "Test Artist")
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.id == "42")
        #expect(candidates.first?.synchronizedLyrics == "[00:01.00]First test line")
    }

    @Test("surfaces an HTTP failure")
    func httpFailure() async {
        let client = StubHTTPClient { request in
            try response(status: 503, data: Data(), request: request)
        }
        let provider = LRCLibLyricsProvider(client: client)

        await #expect(throws: HTTPClientError.self) {
            try await provider.searchLyrics(for: LyricsQuery(title: "Test", artist: "Artist"))
        }
    }

    @Test("surfaces invalid JSON without returning an empty result")
    func invalidJSON() async {
        let client = StubHTTPClient { request in
            try response(status: 200, data: Data("not-json".utf8), request: request)
        }
        let provider = LRCLibLyricsProvider(client: client)

        await #expect(throws: LRCLibError.self) {
            try await provider.searchLyrics(for: LyricsQuery(title: "Test", artist: "Artist"))
        }
    }

    @Test("propagates task cancellation")
    func cancellation() async {
        let client = StubHTTPClient { request in
            try await Task.sleep(for: .seconds(30))
            return try response(status: 200, data: Data("[]".utf8), request: request)
        }
        let provider = LRCLibLyricsProvider(client: client)
        let task = Task {
            try await provider.searchLyrics(for: LyricsQuery(title: "Test", artist: "Artist"))
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("uses an injected cache")
    func cacheHit() async throws {
        let cache = MemoryLyricsCache()
        let requestCount = RequestCounter()
        let body = Data("[]".utf8)
        let client = StubHTTPClient { request in
            await requestCount.increment()
            return try response(status: 200, data: body, request: request)
        }
        let provider = LRCLibLyricsProvider(client: client, cache: cache)
        let query = LyricsQuery(title: "Test", artist: "Artist")

        _ = try await provider.searchLyrics(for: query)
        _ = try await provider.searchLyrics(for: query)

        #expect(await requestCount.value == 1)
    }
}

private actor RequestCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private func response(status: Int, data: Data, request: URLRequest) throws -> HTTPResponse {
    guard let url = request.url,
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )
    else {
        throw TestFailure.responseConstruction
    }
    return HTTPResponse(data: data, response: response)
}
