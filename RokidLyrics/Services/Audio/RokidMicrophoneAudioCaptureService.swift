#if ROKID_SDK_AVAILABLE && canImport(RGCxrClient)
    import Foundation
    import RokidLyricsCore
    import RokidLyricsServices

    enum RokidMicrophoneCaptureError: Error, Equatable, LocalizedError, Sendable {
        case captureAlreadyRunning
        case invalidPCMFormat
        case streamInterrupted

        var errorDescription: String? {
            switch self {
            case .captureAlreadyRunning:
                return "Rokid microphone capture is already active."
            case .invalidPCMFormat:
                return "The Rokid microphone returned an unsupported audio format."
            case .streamInterrupted:
                return "The Rokid microphone stream was interrupted."
            }
        }
    }

    /// Captures the glasses microphone through the verified CustomView session
    /// media API. Frames remain in memory only and are converted directly to the
    /// SDK-neutral normalized PCM domain model.
    actor RokidMicrophoneAudioCaptureService: AudioCaptureService {
        private static let sampleRate = 16_000.0

        private let coordinator: RokidCXRCoordinator
        private let payloadEncoder: RokidCustomViewPayloadEncoder
        private var relayTask: Task<Void, Never>?
        private var outputContinuation: CapturedAudioStream.Continuation?
        private var captureID: UUID?

        init(
            coordinator: RokidCXRCoordinator,
            payloadEncoder: RokidCustomViewPayloadEncoder = .init()
        ) {
            self.coordinator = coordinator
            self.payloadEncoder = payloadEncoder
        }

        func startCapture() async throws -> CapturedAudioStream {
            guard relayTask == nil else {
                throw RokidMicrophoneCaptureError.captureAlreadyRunning
            }

            // RGCxrClient CustomView mode requires the view to be running before
            // microphone streaming. It also provides an explicit visible capture
            // state on the glasses before any PCM is requested.
            let listeningModel = GlassesDisplayModel(
                trackTitle: "Rokid Lyrics",
                artist: "",
                activeLine: "Listening for music…",
                status: .listening,
                preferences: GlassesDisplayPreferences(
                    fontScale: 1,
                    visibleLineCount: 1,
                    showPreviousLine: false,
                    showNextLine: false
                )
            )
            let listeningPayload = try payloadEncoder.payload(for: listeningModel)
            try await coordinator.send(listeningPayload)
            let sdkStream = try await coordinator.startPCMStream()

            let pair = CapturedAudioStream.makeStream(bufferingPolicy: .bufferingNewest(32))
            let id = UUID()
            captureID = id
            outputContinuation = pair.continuation

            pair.continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.stopCapture(id: id) }
            }

            relayTask = Task { [weak self] in
                var pendingBytes = Data()
                do {
                    for try await event in sdkStream {
                        try Task.checkCancellation()
                        switch event {
                        case let .started(reportedChannelCount):
                            guard reportedChannelCount > 0 else {
                                throw RokidMicrophoneCaptureError.invalidPCMFormat
                            }
                        case let .packet(data, packetChannelCount):
                            guard packetChannelCount > 0 else {
                                throw RokidMicrophoneCaptureError.invalidPCMFormat
                            }
                            pendingBytes.append(data)
                            let bytesPerFrame = packetChannelCount * MemoryLayout<Int16>.size
                            let completeByteCount =
                                pendingBytes.count
                                - (pendingBytes.count % bytesPerFrame)
                            guard completeByteCount > 0 else { continue }

                            let completeData = Data(pendingBytes.prefix(completeByteCount))
                            pendingBytes.removeFirst(completeByteCount)
                            let samples = Self.decodeLittleEndianPCM16(completeData)
                            guard !samples.isEmpty else { continue }

                            pair.continuation.yield(
                                CapturedAudioFrame(
                                    samples: samples,
                                    sampleRate: Self.sampleRate,
                                    channelCount: packetChannelCount,
                                    capturedAtMonotonicTime: ProcessInfo.processInfo.systemUptime
                                )
                            )
                        }
                    }
                    pair.continuation.finish()
                } catch is CancellationError {
                    pair.continuation.finish()
                } catch {
                    // Preserve no SDK-supplied error text in the domain stream.
                    pair.continuation.finish(throwing: RokidMicrophoneCaptureError.streamInterrupted)
                }
                await self?.relayFinished(id: id)
            }

            return pair.stream
        }

        func stopCapture() async {
            guard let captureID else { return }
            await stopCapture(id: captureID)
        }

        private func stopCapture(id: UUID) async {
            guard captureID == id else { return }
            captureID = nil

            let task = relayTask
            relayTask = nil
            task?.cancel()

            let continuation = outputContinuation
            outputContinuation = nil
            continuation?.finish()
            await coordinator.stopPCMStream()
        }

        private func relayFinished(id: UUID) async {
            guard captureID == id else { return }
            captureID = nil
            relayTask = nil
            outputContinuation = nil
            await coordinator.stopPCMStream()
        }

        private nonisolated static func decodeLittleEndianPCM16(_ data: Data) -> [Float] {
            guard data.count >= MemoryLayout<Int16>.size else { return [] }
            return data.withUnsafeBytes { rawBuffer in
                let bytes = rawBuffer.bindMemory(to: UInt8.self)
                var samples = [Float]()
                samples.reserveCapacity(bytes.count / 2)
                var index = 0
                while index + 1 < bytes.count {
                    let bits = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
                    samples.append(Float(Int16(bitPattern: bits)) / 32_768)
                    index += 2
                }
                return samples
            }
        }
    }
#endif
