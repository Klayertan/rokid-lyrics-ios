import AVFAudio
import Foundation
import RokidLyricsCore

public enum AudioCaptureError: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case captureAlreadyRunning
    case invalidInputFormat
    case engineStartFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission is required for song recognition."
        case .captureAlreadyRunning:
            return "Microphone capture is already active."
        case .invalidInputFormat:
            return "The selected microphone did not provide a supported PCM format."
        case let .engineStartFailed(message):
            return "Microphone capture could not start: \(message)"
        }
    }
}

public struct PhoneMicrophoneCaptureConfiguration: Equatable, Sendable {
    public var bufferSize: AVAudioFrameCount
    public var mixWithOtherAudio: Bool
    public var preferSpeakerOutput: Bool

    public init(
        bufferSize: AVAudioFrameCount = 4_096,
        mixWithOtherAudio: Bool = true,
        preferSpeakerOutput: Bool = true
    ) {
        self.bufferSize = bufferSize
        self.mixWithOtherAudio = mixWithOtherAudio
        self.preferSpeakerOutput = preferSpeakerOutput
    }
}

/// Captures short-lived microphone PCM for recognition. Frames are copied into
/// memory and yielded directly; no raw audio is written to disk.
public actor PhoneMicrophoneAudioCaptureService: AudioCaptureService {
    private let configuration: PhoneMicrophoneCaptureConfiguration
    private var engine: AVAudioEngine?
    private var continuation: CapturedAudioStream.Continuation?

    public init(configuration: PhoneMicrophoneCaptureConfiguration = .init()) {
        self.configuration = configuration
    }

    public func startCapture() async throws -> CapturedAudioStream {
        guard engine == nil else { throw AudioCaptureError.captureAlreadyRunning }
        guard await requestPermission() else { throw AudioCaptureError.permissionDenied }

#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = []
        if configuration.mixWithOtherAudio { options.insert(.mixWithOthers) }
        if configuration.preferSpeakerOutput { options.insert(.defaultToSpeaker) }
        try session.setCategory(.playAndRecord, mode: .default, options: options)
        try session.setActive(true)
#endif

        let audioEngine = AVAudioEngine()
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
#if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
#endif
            throw AudioCaptureError.invalidInputFormat
        }

        let pair = CapturedAudioStream.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )
        let stream = pair.stream
        let streamContinuation = pair.continuation

        input.installTap(
            onBus: 0,
            bufferSize: configuration.bufferSize,
            format: format
        ) { buffer, _ in
            guard let frame = Self.copyFrame(from: buffer) else { return }
            streamContinuation.yield(frame)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            streamContinuation.finish(throwing: error)
#if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
#endif
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }

        streamContinuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.stopCapture() }
        }
        engine = audioEngine
        continuation = streamContinuation
        return stream
    }

    public func stopCapture() async {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil

        let streamContinuation = continuation
        continuation = nil
        streamContinuation?.finish()

#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
#endif
    }

    public func currentRouteDescription() -> String {
#if os(iOS)
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputs = route.inputs.map { "\($0.portName) [\($0.portType.rawValue)]" }
        let outputs = route.outputs.map { "\($0.portName) [\($0.portType.rawValue)]" }
        return "input=\(inputs.joined(separator: ", ")); output=\(outputs.joined(separator: ", "))"
#else
        return "Default system audio input"
#endif
    }

    private func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private nonisolated static func copyFrame(from buffer: AVAudioPCMBuffer) -> CapturedAudioFrame? {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else { return nil }

        var samples = [Float](repeating: 0, count: channelCount * frameLength)
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else { return nil }
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    samples[(frame * channelCount) + channel] = channelData[channel][frame]
                }
            }
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else { return nil }
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    samples[(frame * channelCount) + channel] =
                        Float(channelData[channel][frame]) / Float(Int16.max)
                }
            }
        case .pcmFormatInt32:
            guard let channelData = buffer.int32ChannelData else { return nil }
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    samples[(frame * channelCount) + channel] =
                        Float(channelData[channel][frame]) / Float(Int32.max)
                }
            }
        default:
            return nil
        }

        return CapturedAudioFrame(
            samples: samples,
            sampleRate: buffer.format.sampleRate,
            channelCount: channelCount,
            capturedAtMonotonicTime: ProcessInfo.processInfo.systemUptime
        )
    }
}

