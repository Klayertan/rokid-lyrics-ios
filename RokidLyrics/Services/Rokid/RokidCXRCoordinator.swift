#if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
    @preconcurrency import Combine
    import Foundation
    @preconcurrency import RGCxrClient
    import RokidLyricsCore
    import RokidLyricsServices

    /// Errors deliberately contain no SDK-provided text. The current SDK can put
    /// authentication tokens in logs and error-adjacent callback data, so the
    /// adapter exposes only bounded, domain-safe messages.
    enum RokidCXRAdapterError: Error, Equatable, LocalizedError, Sendable {
        case authenticationFailed
        case authenticationTimedOut
        case incompatibleInitializationMode
        case connectionTimedOut
        case notConnected
        case permissionDenied
        case sessionNotReady
        case sessionPaused
        case sessionUnavailable
        case sessionDestroyed
        case displayCommandFailed
        case displayCommandTimedOut
        case audioAlreadyRunning
        case audioCommandFailed
        case audioInterrupted

        var errorDescription: String? {
            switch self {
            case .authenticationFailed:
                return "Rokid authorization failed. No credential details were retained."
            case .authenticationTimedOut:
                return "Rokid authorization timed out."
            case .incompatibleInitializationMode:
                return "The Rokid SDK was already initialized for an incompatible session mode."
            case .connectionTimedOut:
                return "The Rokid glasses connection timed out."
            case .notConnected:
                return "Rokid Glasses are not connected."
            case .permissionDenied:
                return "Rokid microphone permission was not granted."
            case .sessionNotReady:
                return "The Rokid display session is not ready."
            case .sessionPaused:
                return "The Rokid display session is paused."
            case .sessionUnavailable:
                return "The Rokid display session is unavailable."
            case .sessionDestroyed:
                return "The Rokid display session was closed."
            case .displayCommandFailed:
                return "The Rokid display did not accept the update."
            case .displayCommandTimedOut:
                return "The Rokid display update timed out."
            case .audioAlreadyRunning:
                return "Rokid microphone capture is already active."
            case .audioCommandFailed:
                return "The Rokid microphone stream could not start."
            case .audioInterrupted:
                return "The Rokid microphone stream was interrupted."
            }
        }
    }

    /// SDK-neutral events shared with the optional audio adapter. SDK event types
    /// are converted on the main actor and never cross this boundary.
    enum RokidPCMStreamEvent: Sendable {
        case started(channelCount: Int)
        case packet(Data, channelCount: Int)
    }

    typealias RokidPCMStream = AsyncThrowingStream<RokidPCMStreamEvent, Error>

    /// Owns the one Link and one typed CustomView session used by both the display
    /// transport and the glasses-microphone adapter. RGCxrClient objects are kept
    /// on the main actor because the SDK does not declare those reference types
    /// Sendable and performs authorization through UIApplication.
    @MainActor
    final class RokidCXRCoordinator {
        private static let authorizationTimeoutNanoseconds: UInt64 = 65_000_000_000
        private static let connectionTimeoutSeconds: TimeInterval = 45
        private static let displayTimeoutNanoseconds: UInt64 = 35_000_000_000
        private static let viewReadyTimeoutSeconds: TimeInterval = 8

        private let link: any RGCxrLink
        private let session: any RGCxrCustomViewSession
        private var cancellables = Set<AnyCancellable>()

        private(set) var connectionState: RokidConnectionState = .disconnected
        private var linkConnected = false
        private var explicitlyDisconnected = false
        private var customViewOpen = false
        private var lastPayload: RokidCustomViewPayload?
        private var lastSentUpdateJSON: String?
        private var reopenTask: Task<Void, Never>?

        private var audioContinuation: RokidPCMStream.Continuation?
        private var audioChannelCount: Int?
        private(set) var diagnosticSnapshot = RokidHardwareDiagnosticSnapshot()
        private var diagnosticSequence = 0
        private let diagnosticsStartedAt = ProcessInfo.processInfo.systemUptime

        init(appDisplayName: String = "Rokid Lyrics") throws {
            let outcome = CxrClient.initialize(
                mode: .customView,
                options: RGCxrClientInitializationOptions(
                    appDisplayName: appDisplayName,
                    pageName: nil
                )
            )
            switch outcome {
            case .success:
                break
            case .failureAlreadyInitialized:
                guard CxrClient.initializationMode == .customView else {
                    throw RokidCXRAdapterError.incompatibleInitializationMode
                }
            @unknown default:
                throw RokidCXRAdapterError.incompatibleInitializationMode
            }

            let link = CxrClient.makeLink(appDisplayName: appDisplayName)
            self.link = link
            session = link.makeCustomViewSession(aiInterceptMode: .allowWithPause)
            bindEvents()
            diagnosticSnapshot.authorization = "SDK initialized; authorization not started"
            appendDiagnostic(category: "sdk", detail: "RGCxrClient initialized in CustomView mode")
        }

        /// Starts the SDK's supported authorization flow. There is no public
        /// discovery or direct connect API: successful authorization carries the
        /// glasses name and the SDK then initiates BLE automatically.
        func connect() async throws {
            if linkConnected {
                connectionState = .connected
                diagnosticSnapshot.connection = "Connected"
                appendDiagnostic(category: "connection", detail: "Connect reused the active link")
                return
            }

            if connectionState != .connecting {
                explicitlyDisconnected = false
                connectionState = .connecting
                diagnosticSnapshot.connection = "Connecting"
                diagnosticSnapshot.authorization = "Authorization requested"
                appendDiagnostic(category: "connection", detail: "Connect requested")
                do {
                    try await authenticate()
                    diagnosticSnapshot.authorization = "Authorization completion succeeded"
                    appendDiagnostic(category: "authorization", detail: "Authorization completion succeeded")
                } catch {
                    let safeError = error as? RokidCXRAdapterError ?? .authenticationFailed
                    connectionState = .failed(message: safeError.localizedDescription)
                    diagnosticSnapshot.connection = "Failed"
                    diagnosticSnapshot.authorization = "Authorization failed"
                    appendDiagnostic(category: "authorization", detail: "Authorization completion failed")
                    throw safeError
                }
            }

            do {
                try await waitForLinkConnection()
                connectionState = .connected
                diagnosticSnapshot.connection = "Connected"
            } catch is CancellationError {
                connectionState = .disconnected
                diagnosticSnapshot.connection = "Disconnected"
                appendDiagnostic(category: "connection", detail: "Connect was cancelled")
                throw CancellationError()
            } catch {
                connectionState = .failed(message: RokidCXRAdapterError.connectionTimedOut.localizedDescription)
                diagnosticSnapshot.connection = "Timed out"
                appendDiagnostic(category: "connection", detail: "Connection timed out")
                throw error
            }
        }

        /// Must be called from SwiftUI `onOpenURL` (or the equivalent app/scene
        /// callback). The URL is forwarded directly and is never logged or stored.
        @discardableResult
        func handleOpenURL(_ url: URL) -> Bool {
            let handled = link.handleOpenURL(url)
            appendDiagnostic(
                category: "authorization",
                detail: handled ? "Authorization callback handled" : "Authorization callback not handled"
            )
            return handled
        }

        func disconnect() async {
            explicitlyDisconnected = true
            connectionState = .disconnecting
            diagnosticSnapshot.connection = "Disconnecting"
            appendDiagnostic(category: "connection", detail: "Disconnect requested")
            let pendingReopen = reopenTask
            pendingReopen?.cancel()
            if let pendingReopen { await pendingReopen.value }
            reopenTask = nil
            stopPCMStream()

            if customViewOpen {
                try? await closeCustomView()
            }

            link.disconnect()

            // RGCxrClient 1.0.4.2 keeps a valid token after Link.disconnect(), but
            // its fast-path authenticate completion does not emit the event that
            // supplies the device name to BLE. Clearing authentication is the only
            // verified public-API route that makes a later explicit connect work.
            CxrClient.shared.auth.clearAuthentication()

            linkConnected = false
            customViewOpen = false
            lastSentUpdateJSON = nil
            connectionState = .disconnected
            diagnosticSnapshot.connection = "Disconnected"
            diagnosticSnapshot.authorization = "Cleared after explicit disconnect"
            diagnosticSnapshot.session = "Unavailable"
            diagnosticSnapshot.customView = "Closed"
            diagnosticSnapshot.audioStream = "Stopped"
            appendDiagnostic(category: "connection", detail: "Disconnect completed")
        }

        func send(_ payload: RokidCustomViewPayload) async throws {
            guard linkConnected else { throw RokidCXRAdapterError.notConnected }
            let previousPayload = lastPayload
            lastPayload = payload

            // A transient reconnect may already be re-opening the previous tree.
            // Serialize behind it, then update to the newest payload instead of
            // issuing concurrent open commands for one CustomView session.
            if let reopenTask { await reopenTask.value }
            guard linkConnected else { throw RokidCXRAdapterError.notConnected }

            if customViewOpen {
                if let previousPayload,
                    previousPayload.layoutIdentifier != payload.layoutIdentifier
                {
                    // Gravity is verified in the open tree, but the official iOS
                    // sample does not demonstrate mutating it with update(). Use
                    // the verified close/open lifecycle instead of guessing.
                    try await closeCustomView()
                    try await openCustomView(payload)
                    return
                }
                guard payload.updateJSON != lastSentUpdateJSON else { return }
                try await updateCustomView(payload.updateJSON)
                lastSentUpdateJSON = payload.updateJSON
            } else {
                try await openCustomView(payload)
            }
        }

        func clearDisplay() async throws {
            lastPayload = nil
            lastSentUpdateJSON = nil
            let pendingReopen = reopenTask
            pendingReopen?.cancel()
            if let pendingReopen { await pendingReopen.value }
            reopenTask = nil

            guard customViewOpen else { return }
            guard linkConnected else {
                customViewOpen = false
                throw RokidCXRAdapterError.notConnected
            }
            try await closeCustomView()
            appendDiagnostic(category: "display", detail: "Clear display completed")
        }

        func startPCMStream() async throws -> RokidPCMStream {
            guard linkConnected else { throw RokidCXRAdapterError.notConnected }
            guard audioContinuation == nil else { throw RokidCXRAdapterError.audioAlreadyRunning }

            // CustomView mode requires a running view before media operations.
            try await waitForRunningCustomView()

            let pair = RokidPCMStream.makeStream(bufferingPolicy: .bufferingNewest(64))
            audioChannelCount = nil
            audioContinuation = pair.continuation
            diagnosticSnapshot.audioStream = "Start requested"
            appendDiagnostic(category: "audio", detail: "Glasses PCM start requested")
            pair.continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in self?.stopPCMStream() }
            }

            if let error = session.media.startAudioStream(codec: .pcm, mode: .antClose) {
                audioContinuation = nil
                diagnosticSnapshot.audioStream = "Start failed"
                appendDiagnostic(category: "audio", detail: "Glasses PCM start failed")
                pair.continuation.finish(throwing: mapAudioError(error))
                throw mapAudioError(error)
            }
            return pair.stream
        }

        func stopPCMStream() {
            guard let continuation = audioContinuation else { return }
            audioContinuation = nil
            audioChannelCount = nil
            _ = session.media.stopAudioStream()
            continuation.finish()
            diagnosticSnapshot.audioStream = "Stopped"
            appendDiagnostic(category: "audio", detail: "Glasses PCM stopped")
        }

        private func bindEvents() {
            link.events.connectionStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] connected in
                    MainActor.assumeIsolated {
                        self?.handleLinkConnectionChange(connected)
                    }
                }
                .store(in: &cancellables)

            link.events.authEventPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] event in
                    MainActor.assumeIsolated {
                        self?.handleAuthorizationEvent(event)
                    }
                }
                .store(in: &cancellables)

            session.statePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] event in
                    MainActor.assumeIsolated {
                        self?.handleSessionState(event)
                    }
                }
                .store(in: &cancellables)

            session.customViewEvents.lifecyclePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] event in
                    MainActor.assumeIsolated {
                        self?.handleCustomViewEvent(event)
                    }
                }
                .store(in: &cancellables)

            session.mediaEvents.audioPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] event in
                    MainActor.assumeIsolated {
                        self?.handleAudioEvent(event)
                    }
                }
                .store(in: &cancellables)
        }

        private func authenticate() async throws {
            try await withCheckedThrowingContinuation { continuation in
                let gate = RokidOperationGate(
                    continuation: continuation,
                    timeoutNanoseconds: Self.authorizationTimeoutNanoseconds,
                    timeoutError: .authenticationTimedOut
                )
                link.authenticate(scopes: [.microphone]) { result in
                    let succeeded: Bool
                    switch result {
                    case .success: succeeded = true
                    case .failure: succeeded = false
                    }
                    DispatchQueue.main.async {
                        if succeeded {
                            gate.succeed()
                        } else {
                            gate.fail(.authenticationFailed)
                        }
                    }
                }
            }
        }

        private func waitForLinkConnection() async throws {
            let startedAt = ProcessInfo.processInfo.systemUptime
            while !linkConnected {
                try Task.checkCancellation()
                if ProcessInfo.processInfo.systemUptime - startedAt >= Self.connectionTimeoutSeconds {
                    throw RokidCXRAdapterError.connectionTimedOut
                }
                try await Task.sleep(for: .milliseconds(100))
            }
        }

        private func waitForRunningCustomView() async throws {
            let startedAt = ProcessInfo.processInfo.systemUptime
            while session.state != .started {
                try Task.checkCancellation()
                if !linkConnected { throw RokidCXRAdapterError.notConnected }
                if ProcessInfo.processInfo.systemUptime - startedAt >= Self.viewReadyTimeoutSeconds {
                    throw RokidCXRAdapterError.sessionNotReady
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        private func openCustomView(_ payload: RokidCustomViewPayload) async throws {
            try await withCheckedThrowingContinuation { continuation in
                let gate = RokidOperationGate(
                    continuation: continuation,
                    timeoutNanoseconds: Self.displayTimeoutNanoseconds,
                    timeoutError: .displayCommandTimedOut
                )
                let immediateError = session.customView.open(payload.openJSON) { success, _ in
                    DispatchQueue.main.async {
                        if success {
                            gate.succeed()
                        } else {
                            gate.fail(.displayCommandFailed)
                        }
                    }
                }
                if let immediateError {
                    gate.fail(mapDisplayError(immediateError))
                }
            }
            customViewOpen = true
            lastSentUpdateJSON = payload.updateJSON
            diagnosticSnapshot.customView = "Open"
            appendDiagnostic(category: "display", detail: "CustomView open callback succeeded")
        }

        private func updateCustomView(_ updateJSON: String) async throws {
            try await withCheckedThrowingContinuation { continuation in
                let gate = RokidOperationGate(
                    continuation: continuation,
                    timeoutNanoseconds: Self.displayTimeoutNanoseconds,
                    timeoutError: .displayCommandTimedOut
                )
                let immediateError = session.customView.update(updateJSON) { success in
                    DispatchQueue.main.async {
                        if success {
                            gate.succeed()
                        } else {
                            gate.fail(.displayCommandFailed)
                        }
                    }
                }
                if let immediateError {
                    gate.fail(mapDisplayError(immediateError))
                }
            }
            appendDiagnostic(category: "display", detail: "CustomView update callback succeeded")
        }

        private func closeCustomView() async throws {
            try await withCheckedThrowingContinuation { continuation in
                let gate = RokidOperationGate(
                    continuation: continuation,
                    timeoutNanoseconds: 8_000_000_000,
                    timeoutError: .displayCommandTimedOut
                )
                let immediateError = session.customView.close { success in
                    DispatchQueue.main.async {
                        if success {
                            gate.succeed()
                        } else {
                            gate.fail(.displayCommandFailed)
                        }
                    }
                }
                if let immediateError {
                    gate.fail(mapDisplayError(immediateError))
                }
            }
            customViewOpen = false
            lastSentUpdateJSON = nil
            diagnosticSnapshot.customView = "Closed"
            appendDiagnostic(category: "display", detail: "CustomView close callback succeeded")
        }

        private func handleLinkConnectionChange(_ connected: Bool) {
            linkConnected = connected
            if connected {
                connectionState = .connected
                diagnosticSnapshot.connection = "Connected callback"
                appendDiagnostic(category: "connection-callback", detail: "BLE connection callback: connected")
                scheduleReopenIfNeeded()
            } else {
                customViewOpen = false
                lastSentUpdateJSON = nil
                finishAudio(throwing: .audioInterrupted)
                if connectionState != .connecting {
                    connectionState = .disconnected
                }
                diagnosticSnapshot.connection = "Disconnected callback"
                diagnosticSnapshot.customView = "Closed"
                diagnosticSnapshot.audioStream = "Stopped"
                appendDiagnostic(category: "connection-callback", detail: "BLE connection callback: disconnected")
            }
        }

        private func handleAuthorizationEvent(_ event: RGCxrClientAuthEvent) {
            switch event {
            case let .stateChanged(state):
                let stateText: String
                switch state {
                case .notAuthenticated: stateText = "Not authenticated"
                case .authenticating: stateText = "Authenticating"
                case .authenticated: stateText = "Authenticated"
                case .expired: stateText = "Expired"
                case .failed: stateText = "Failed"
                @unknown default: stateText = "Unknown"
                }
                diagnosticSnapshot.authorization = stateText
                appendDiagnostic(category: "authorization-callback", detail: "Authorization state: \(stateText)")
            case .authenticationSucceeded:
                diagnosticSnapshot.authorization = "Succeeded"
                appendDiagnostic(category: "authorization-callback", detail: "Authorization succeeded")
            case .authenticationFailed:
                diagnosticSnapshot.authorization = "Failed"
                appendDiagnostic(category: "authorization-callback", detail: "Authorization failed")
                if !linkConnected {
                    connectionState = .failed(message: RokidCXRAdapterError.authenticationFailed.localizedDescription)
                }
            case .tokenExpired:
                diagnosticSnapshot.authorization = "Token expired"
                appendDiagnostic(category: "authorization-callback", detail: "Authorization expired")
                if !linkConnected {
                    connectionState = .failed(message: RokidCXRAdapterError.authenticationFailed.localizedDescription)
                }
            @unknown default:
                diagnosticSnapshot.authorization = "Unknown callback"
                appendDiagnostic(category: "authorization-callback", detail: "Unknown authorization callback")
            }
        }

        private func handleSessionState(_ event: RGCxrSessionStateEvent) {
            diagnosticSnapshot.session =
                event.reason.map {
                    "\(event.state.rawValue) (\($0.rawValue))"
                } ?? event.state.rawValue
            appendDiagnostic(
                category: "session-callback",
                detail: "Session state: \(diagnosticSnapshot.session)"
            )
            switch event.state {
            case .started, .available:
                break
            case .paused:
                finishAudio(throwing: .audioInterrupted)
            case .unavailable:
                customViewOpen = false
                lastSentUpdateJSON = nil
                finishAudio(throwing: .audioInterrupted)
            @unknown default:
                customViewOpen = false
                lastSentUpdateJSON = nil
                finishAudio(throwing: .audioInterrupted)
            }
        }

        private func handleCustomViewEvent(_ event: RGCxrSessionCustomViewEvent) {
            switch event {
            case .opened:
                customViewOpen = true
                diagnosticSnapshot.customView = "Opened callback"
                appendDiagnostic(category: "display-callback", detail: "CustomView opened")
            case .closed:
                customViewOpen = false
                lastSentUpdateJSON = nil
                diagnosticSnapshot.customView = "Closed callback"
                appendDiagnostic(category: "display-callback", detail: "CustomView closed")
            case .updated:
                diagnosticSnapshot.customView = "Updated callback"
                appendDiagnostic(category: "display-callback", detail: "CustomView updated")
            case .iconsSent:
                appendDiagnostic(category: "display-callback", detail: "CustomView icons sent")
            case .error:
                // The SDK message may contain implementation data. Do not retain or
                // surface it; the per-operation callback remains authoritative.
                diagnosticSnapshot.customView = "Error callback"
                appendDiagnostic(category: "display-callback", detail: "CustomView error callback")
            @unknown default:
                diagnosticSnapshot.customView = "Unknown callback"
                appendDiagnostic(category: "display-callback", detail: "Unknown CustomView callback")
            }
        }

        private func handleAudioEvent(_ event: RGCxrClientAudioEvent) {
            guard let audioContinuation else { return }
            switch event {
            case let .started(info):
                let channelCount = Int(info.channels)
                audioChannelCount = channelCount
                diagnosticSnapshot.audioStream = "Started (\(channelCount) channel(s))"
                appendDiagnostic(
                    category: "audio-callback",
                    detail: "Glasses PCM started with \(channelCount) channel(s)"
                )
                audioContinuation.yield(.started(channelCount: channelCount))
            case let .stream(packet):
                // SDK timestamp units are undocumented. The audio adapter assigns
                // a local monotonic receipt timestamp instead of guessing.
                guard let audioChannelCount else { return }
                diagnosticSnapshot.audioStream = "Receiving PCM"
                audioContinuation.yield(
                    .packet(packet.data, channelCount: audioChannelCount)
                )
            @unknown default:
                diagnosticSnapshot.audioStream = "Unknown callback"
                appendDiagnostic(category: "audio-callback", detail: "Unknown glasses audio callback")
            }
        }

        private func appendDiagnostic(category: String, detail: String) {
            diagnosticSequence += 1
            diagnosticSnapshot.events.append(
                RokidHardwareDiagnosticEvent(
                    sequence: diagnosticSequence,
                    elapsedSeconds: max(
                        0,
                        ProcessInfo.processInfo.systemUptime - diagnosticsStartedAt
                    ),
                    category: category,
                    detail: detail
                )
            )
            if diagnosticSnapshot.events.count > 100 {
                diagnosticSnapshot.events.removeFirst(
                    diagnosticSnapshot.events.count - 100
                )
            }
        }

        private func scheduleReopenIfNeeded() {
            guard !explicitlyDisconnected,
                !customViewOpen,
                reopenTask == nil,
                let payload = lastPayload
            else { return }

            reopenTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { reopenTask = nil }
                guard !Task.isCancelled else { return }
                do {
                    try await openCustomView(payload)
                } catch {
                    // The application-level reconnect loop can retry by sending its
                    // current state. No raw SDK error is persisted or logged here.
                }
            }
        }

        private func finishAudio(throwing error: RokidCXRAdapterError) {
            guard let continuation = audioContinuation else { return }
            audioContinuation = nil
            audioChannelCount = nil
            continuation.finish(throwing: error)
            diagnosticSnapshot.audioStream = "Interrupted"
            appendDiagnostic(category: "audio-callback", detail: "Glasses PCM interrupted")
        }

        private func mapDisplayError(_ error: RGCxrClientError) -> RokidCXRAdapterError {
            switch error {
            case .permissionDenied: return .permissionDenied
            case .sessionPaused: return .sessionPaused
            case .sessionUnavailable: return .sessionUnavailable
            case .sessionDestroyed: return .sessionDestroyed
            case .notInitialized, .modeMismatch, .notAuthenticated, .notReady:
                return .sessionNotReady
            @unknown default:
                return .displayCommandFailed
            }
        }

        private func mapAudioError(_ error: RGCxrClientError) -> RokidCXRAdapterError {
            switch error {
            case .permissionDenied: return .permissionDenied
            case .sessionPaused: return .sessionPaused
            case .sessionUnavailable: return .sessionUnavailable
            case .sessionDestroyed: return .sessionDestroyed
            case .notInitialized, .modeMismatch, .notAuthenticated, .notReady:
                return .audioCommandFailed
            @unknown default:
                return .audioCommandFailed
            }
        }
    }

    @MainActor
    private final class RokidOperationGate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var timeoutTask: Task<Void, Never>?

        init(
            continuation: CheckedContinuation<Void, Error>,
            timeoutNanoseconds: UInt64,
            timeoutError: RokidCXRAdapterError
        ) {
            self.continuation = continuation
            timeoutTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                } catch {
                    return
                }
                self?.fail(timeoutError)
            }
        }

        func succeed() {
            guard let continuation else { return }
            self.continuation = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            continuation.resume()
        }

        func fail(_ error: RokidCXRAdapterError) {
            guard let continuation else { return }
            self.continuation = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            continuation.resume(throwing: error)
        }
    }
#endif
