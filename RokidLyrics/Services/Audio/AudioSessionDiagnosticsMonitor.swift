import AVFAudio
import Foundation
import Observation

/// Observes only public AVAudioSession state and notifications. It never
/// receives, inspects, logs, or persists microphone PCM.
@MainActor
@Observable
final class AudioSessionDiagnosticsMonitor {
    private(set) var snapshot = AudioSessionDiagnosticSnapshot()
    private(set) var events: [DiagnosticEvent] = []

    private let session: AVAudioSession
    private let notificationCenter: NotificationCenter
    private var observerTokens: [NSObjectProtocol] = []
    private var samplingTask: Task<Void, Never>?
    private var captureRunning = false
    private var eventSequence = 0
    private var observationStartedAt = ProcessInfo.processInfo.systemUptime

    init(
        session: AVAudioSession = .sharedInstance(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.session = session
        self.notificationCenter = notificationCenter
    }

    func startMonitoring() {
        guard observerTokens.isEmpty else {
            refresh()
            return
        }

        observeInterruptionNotifications()
        observeRouteChangeNotifications()
        observeSecondaryAudioHintNotifications()
        observe(AVAudioSession.mediaServicesWereLostNotification) { [weak self] in
            self?.appendEvent(category: "media-services", detail: "Media services were lost")
            self?.refresh()
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] in
            self?.appendEvent(category: "media-services", detail: "Media services were reset")
            self?.refresh()
        }

        refresh()
        appendEvent(category: "monitor", detail: "Audio-session monitoring started")
        samplingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopMonitoring() {
        samplingTask?.cancel()
        samplingTask = nil
        observerTokens.forEach(notificationCenter.removeObserver)
        observerTokens.removeAll()
    }

    func beginCoexistenceObservation() {
        observationStartedAt = ProcessInfo.processInfo.systemUptime
        eventSequence = 0
        events = []
        refresh()
        snapshot.routeChangeCount = 0
        appendEvent(
            category: "coexistence",
            detail: snapshot.isOtherAudioPlaying
                ? "Test started while iOS reported other audio playing"
                : "Test started while iOS did not report other audio playing"
        )
        appendEvent(category: "route", detail: safeRouteSummary())
    }

    func setCaptureRunning(_ running: Bool, source: String) {
        guard captureRunning != running else {
            refresh()
            return
        }
        captureRunning = running
        refresh()
        appendEvent(
            category: "capture",
            detail: "\(source) capture \(running ? "started" : "stopped")"
        )
    }

    func refresh() {
        let route = session.currentRoute
        let inputs = route.inputs.map {
            AudioRoutePortDiagnostic(name: $0.portName, type: $0.portType.rawValue)
        }
        let outputs = route.outputs.map {
            AudioRoutePortDiagnostic(name: $0.portName, type: $0.portType.rawValue)
        }
        let preferredInput = session.preferredInput.map {
            AudioRoutePortDiagnostic(name: $0.portName, type: $0.portType.rawValue)
        }

        snapshot.category = session.category.rawValue
        snapshot.mode = session.mode.rawValue
        snapshot.categoryOptions = Self.names(for: session.categoryOptions)
        snapshot.inputs = inputs
        snapshot.outputs = outputs
        snapshot.selectedInput = inputs.first ?? preferredInput
        snapshot.sampleRate = session.sampleRate
        snapshot.inputChannelCount = session.inputNumberOfChannels
        snapshot.outputChannelCount = session.outputNumberOfChannels
        snapshot.isCaptureRunning = captureRunning
        snapshot.isOtherAudioPlaying = session.isOtherAudioPlaying
        snapshot.secondaryAudioShouldBeSilenced = session.secondaryAudioShouldBeSilencedHint
    }

    private func observe(
        _ name: Notification.Name,
        handler: @escaping @MainActor () -> Void
    ) {
        let token = notificationCenter.addObserver(
            forName: name,
            object: session,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                handler()
            }
        }
        observerTokens.append(token)
    }

    private func observeInterruptionNotifications() {
        let token = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleInterruption(rawType: rawType, rawOptions: rawOptions)
            }
        }
        observerTokens.append(token)
    }

    private func observeRouteChangeNotifications() {
        let token = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleRouteChange(rawReason: rawReason)
            }
        }
        observerTokens.append(token)
    }

    private func observeSecondaryAudioHintNotifications() {
        let token = notificationCenter.addObserver(
            forName: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleSecondaryAudioHint(rawType: rawType)
            }
        }
        observerTokens.append(token)
    }

    private func handleInterruption(rawType: UInt?, rawOptions: UInt?) {
        let type = rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
        switch type {
        case .began:
            snapshot.interruptionState = "Began"
            appendEvent(category: "interruption", detail: "Interruption began")
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
            snapshot.interruptionState = options.contains(.shouldResume) ? "Ended; resume suggested" : "Ended"
            appendEvent(category: "interruption", detail: snapshot.interruptionState)
        case nil:
            snapshot.interruptionState = "Unknown notification"
            appendEvent(category: "interruption", detail: "Unknown interruption notification")
        @unknown default:
            snapshot.interruptionState = "Unknown notification"
            appendEvent(category: "interruption", detail: "Unknown interruption notification")
        }
        refresh()
    }

    private func handleRouteChange(rawReason: UInt?) {
        let reason = rawReason.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        snapshot.routeChangeCount += 1
        refresh()
        appendEvent(
            category: "route-change",
            detail: "\(Self.description(for: reason)); \(safeRouteSummary())"
        )
    }

    private func handleSecondaryAudioHint(rawType: UInt?) {
        let type = rawType.flatMap(AVAudioSession.SilenceSecondaryAudioHintType.init(rawValue:))
        let detail: String
        switch type {
        case .begin: detail = "iOS requested secondary audio silence"
        case .end: detail = "iOS ended the secondary-audio silence hint"
        case nil: detail = "Unknown secondary-audio hint"
        @unknown default: detail = "Unknown secondary-audio hint"
        }
        refresh()
        appendEvent(category: "secondary-audio", detail: detail)
    }

    private func appendEvent(category: String, detail: String) {
        eventSequence += 1
        events.append(
            DiagnosticEvent(
                sequence: eventSequence,
                elapsedSeconds: max(
                    0,
                    ProcessInfo.processInfo.systemUptime - observationStartedAt
                ),
                category: category,
                detail: detail
            )
        )
        if events.count > 100 {
            events.removeFirst(events.count - 100)
        }
    }

    private func safeRouteSummary() -> String {
        let inputTypes = snapshot.inputs.map(\.type).joined(separator: ",")
        let outputTypes = snapshot.outputs.map(\.type).joined(separator: ",")
        return "inputs=[\(inputTypes)]; outputs=[\(outputTypes)]"
    }

    private static func names(for options: AVAudioSession.CategoryOptions) -> [String] {
        var names: [String] = []
        if options.contains(.mixWithOthers) { names.append("mixWithOthers") }
        if options.contains(.duckOthers) { names.append("duckOthers") }
        if options.contains(.interruptSpokenAudioAndMixWithOthers) {
            names.append("interruptSpokenAudioAndMixWithOthers")
        }
        if options.contains(.allowBluetooth) { names.append("allowBluetooth") }
        if options.contains(.allowBluetoothA2DP) { names.append("allowBluetoothA2DP") }
        if options.contains(.allowAirPlay) { names.append("allowAirPlay") }
        if options.contains(.defaultToSpeaker) { names.append("defaultToSpeaker") }
        return names.sorted()
    }

    private static func description(for reason: AVAudioSession.RouteChangeReason?) -> String {
        switch reason {
        case .newDeviceAvailable: return "New device available"
        case .oldDeviceUnavailable: return "Old device unavailable"
        case .categoryChange: return "Audio category changed"
        case .override: return "Route override"
        case .wakeFromSleep: return "Woke from sleep"
        case .noSuitableRouteForCategory: return "No suitable route for category"
        case .routeConfigurationChange: return "Route configuration changed"
        case .unknown, nil: return "Unknown route change"
        @unknown default: return "Unknown route change"
        }
    }
}
