import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import RokidLyricsServices

@Suite("URLSession HTTP retry policy", .serialized)
struct URLSessionHTTPClientTests {
    @Test("does not retry before a long Retry-After window")
    func longRetryAfterStopsWithoutEarlyRetry() async throws {
        let counter = LockedCounter()
        StubURLProtocol.handler = { request in
            counter.increment()
            return try makeResponse(
                request: request,
                status: 429,
                headers: ["Retry-After": "30"]
            )
        }
        defer { StubURLProtocol.handler = nil }
        let client = makeClient(maximumRetryCount: 2, maximumRetryDelay: 0.01)

        await #expect(throws: HTTPClientError.self) {
            _ = try await client.data(for: URLRequest(url: try #require(URL(string: "https://example.invalid/test"))))
        }
        #expect(counter.value == 1)
    }

    @Test("retries a transient server failure within the bounded policy")
    func retriesTransientFailure() async throws {
        let counter = LockedCounter()
        StubURLProtocol.handler = { request in
            let attempt = counter.increment()
            return try makeResponse(
                request: request,
                status: attempt == 1 ? 503 : 200,
                data: Data("[]".utf8)
            )
        }
        defer { StubURLProtocol.handler = nil }
        let client = makeClient(maximumRetryCount: 1, maximumRetryDelay: 0)
        let url = try #require(URL(string: "https://example.invalid/test"))

        let response = try await client.data(for: URLRequest(url: url))

        #expect(response.response.statusCode == 200)
        #expect(counter.value == 2)
    }

    private func makeClient(
        maximumRetryCount: Int,
        maximumRetryDelay: TimeInterval
    ) -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionHTTPClient(
            session: URLSession(configuration: configuration),
            maximumRetryCount: maximumRetryCount,
            maximumRetryDelay: maximumRetryDelay
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    @discardableResult
    func increment() -> Int {
        lock.withLock {
            storedValue += 1
            return storedValue
        }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> HTTPResponse)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let result = try handler(request)
            client?.urlProtocol(self, didReceive: result.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeResponse(
    request: URLRequest,
    status: Int,
    headers: [String: String] = [:],
    data: Data = Data()
) throws -> HTTPResponse {
    guard let url = request.url,
          let response = HTTPURLResponse(
              url: url,
              statusCode: status,
              httpVersion: "HTTP/1.1",
              headerFields: headers
          )
    else {
        throw URLError(.badServerResponse)
    }
    return HTTPResponse(data: data, response: response)
}
