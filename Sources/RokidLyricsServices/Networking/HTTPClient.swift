import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: @unchecked Sendable {
    public let data: Data
    public let response: HTTPURLResponse

    public init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }
}

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> HTTPResponse
}

public enum HTTPClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidResponse
    case unacceptableStatus(code: Int, retryAfterSeconds: TimeInterval?)
    case requestFailed(String)
    case retriesExhausted(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned a response that was not HTTP."
        case let .unacceptableStatus(code, retryAfter):
            if let retryAfter {
                return "The server returned HTTP \(code); retry after \(retryAfter) seconds."
            }
            return "The server returned HTTP \(code)."
        case let .requestFailed(message):
            return "The network request failed: \(message)"
        case let .retriesExhausted(message):
            return "The network request failed after retrying: \(message)"
        }
    }
}

/// URLSession client with bounded retries for transient failures. Cancellation
/// is never converted into a retry.
public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession
    private let maximumRetryCount: Int
    private let maximumRetryDelay: TimeInterval

    public init(
        session: URLSession = URLSessionHTTPClient.makeDefaultSession(),
        maximumRetryCount: Int = 2,
        maximumRetryDelay: TimeInterval = 10
    ) {
        self.session = session
        self.maximumRetryCount = max(0, maximumRetryCount)
        self.maximumRetryDelay = max(0, maximumRetryDelay)
    }

    public func data(for request: URLRequest) async throws -> HTTPResponse {
        var attempt = 0
        var lastError: Error?

        while attempt <= maximumRetryCount {
            try Task.checkCancellation()

            do {
                let (data, rawResponse) = try await session.data(for: request)
                guard let response = rawResponse as? HTTPURLResponse else {
                    throw HTTPClientError.invalidResponse
                }

                if (200...299).contains(response.statusCode) {
                    return HTTPResponse(data: data, response: response)
                }

                let retryAfter = Self.retryAfterSeconds(from: response)
                let error = HTTPClientError.unacceptableStatus(
                    code: response.statusCode,
                    retryAfterSeconds: retryAfter
                )
                // Never retry earlier than LRCLIB's Retry-After instruction.
                // If the server asks for a delay beyond this client's bounded
                // retry window, return the response error without another call.
                let retryFitsWindow = retryAfter.map { $0 <= maximumRetryDelay } ?? true
                guard attempt < maximumRetryCount,
                      Self.isRetryable(response.statusCode),
                      retryFitsWindow
                else {
                    throw error
                }
                lastError = error
                try await sleepBeforeRetry(attempt: attempt, serverDelay: retryAfter)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < maximumRetryCount, Self.isRetryable(error) else {
                    if attempt > 0, let lastError {
                        throw HTTPClientError.retriesExhausted(lastError.localizedDescription)
                    }
                    throw error
                }
                lastError = error
                try await sleepBeforeRetry(attempt: attempt, serverDelay: nil)
            }

            attempt += 1
        }

        throw HTTPClientError.retriesExhausted(
            lastError?.localizedDescription ?? "Unknown network error"
        )
    }

    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private func sleepBeforeRetry(attempt: Int, serverDelay: TimeInterval?) async throws {
        let exponentialDelay = min(pow(2, Double(attempt)) * 0.5, maximumRetryDelay)
        let delay = serverDelay ?? exponentialDelay
        guard delay > 0 else { return }
        try await Task.sleep(for: .seconds(delay))
    }

    private static func isRetryable(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 425 || statusCode == 429 || (500...599).contains(statusCode)
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        switch error.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff:
            return true
        case .cancelled:
            return false
        default:
            return false
        }
    }

    private static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(0, seconds)
        }
        return nil
    }
}
