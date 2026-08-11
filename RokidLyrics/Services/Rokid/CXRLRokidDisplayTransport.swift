#if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
    import Foundation
    import RokidLyricsCore
    import RokidLyricsServices

    /// Optional real transport for RGCxrClient 1.0.4.2.
    ///
    /// Construction is intentionally explicit so the same coordinator can be
    /// injected into `RokidMicrophoneAudioCaptureService`. No SDK type appears in
    /// this transport's public surface or in the domain protocol.
    @MainActor
    final class CXRLRokidDisplayTransport: RokidDisplayTransport {
        private let coordinator: RokidCXRCoordinator
        private let encoder: RokidCustomViewPayloadEncoder

        init(
            coordinator: RokidCXRCoordinator,
            encoder: RokidCustomViewPayloadEncoder = .init()
        ) {
            self.coordinator = coordinator
            self.encoder = encoder
        }

        var connectionState: RokidConnectionState {
            get async { coordinator.connectionState }
        }

        func connect() async throws {
            try await coordinator.connect()
        }

        func disconnect() async {
            await coordinator.disconnect()
        }

        func sendDisplayState(_ state: GlassesDisplayModel) async throws {
            let payload = try encoder.payload(for: state)
            try await coordinator.send(payload)
        }

        func clearDisplay() async throws {
            try await coordinator.clearDisplay()
        }

        /// Route the application's supported custom-URL callback here. This method
        /// returns only whether the SDK handled it and never retains the URL.
        @discardableResult
        func handleOpenURL(_ url: URL) -> Bool {
            coordinator.handleOpenURL(url)
        }
    }
#endif
