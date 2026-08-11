import Foundation

public enum RokidConnectionState: Codable, Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed(message: String)
}

/// The only boundary through which application state reaches Rokid hardware.
/// No SDK-specific type may escape a concrete adapter.
public protocol RokidDisplayTransport: Sendable {
    var connectionState: RokidConnectionState { get async }

    func connect() async throws
    func disconnect() async
    func sendDisplayState(_ state: GlassesDisplayModel) async throws
    func clearDisplay() async throws
}

public enum MockRokidDisplayTransportError: Error, Equatable, Sendable {
    case connectionFailed
    case notConnected
    case sendFailed
}

/// Hardware-free transport used by previews, simulator builds, and tests.
/// Duplicate display states are coalesced to model the production requirement
/// that transport updates occur only when visible content changes.
public actor MockRokidDisplayTransport: RokidDisplayTransport {
    public private(set) var connectionState: RokidConnectionState = .disconnected
    public private(set) var lastDisplayState: GlassesDisplayModel?
    public private(set) var sentDisplayStates: [GlassesDisplayModel] = []
    public private(set) var connectionHistory: [RokidConnectionState] = [.disconnected]
    public private(set) var clearCount = 0

    private let connectionShouldFail: Bool
    private let sendShouldFail: Bool

    public init(
        connectionShouldFail: Bool = false,
        sendShouldFail: Bool = false
    ) {
        self.connectionShouldFail = connectionShouldFail
        self.sendShouldFail = sendShouldFail
    }

    public func connect() async throws {
        guard connectionState != .connected else { return }
        setConnectionState(.connecting)
        if connectionShouldFail {
            setConnectionState(.failed(message: "Mock connection failed"))
            throw MockRokidDisplayTransportError.connectionFailed
        }
        setConnectionState(.connected)
    }

    public func disconnect() async {
        guard connectionState != .disconnected else { return }
        setConnectionState(.disconnecting)
        lastDisplayState = nil
        setConnectionState(.disconnected)
    }

    public func sendDisplayState(_ state: GlassesDisplayModel) async throws {
        guard connectionState == .connected else {
            throw MockRokidDisplayTransportError.notConnected
        }
        guard !sendShouldFail else { throw MockRokidDisplayTransportError.sendFailed }
        guard state != lastDisplayState else { return }
        lastDisplayState = state
        sentDisplayStates.append(state)
    }

    public func clearDisplay() async throws {
        guard connectionState == .connected else {
            throw MockRokidDisplayTransportError.notConnected
        }
        lastDisplayState = nil
        clearCount += 1
    }

    private func setConnectionState(_ state: RokidConnectionState) {
        connectionState = state
        connectionHistory.append(state)
    }
}
