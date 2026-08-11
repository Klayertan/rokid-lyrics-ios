import AVFAudio
import Foundation
import RokidLyricsCore
import ShazamKit

public enum ShazamIdentificationError: Error, Equatable, LocalizedError, Sendable {
    case noMatch
    case noUsableMediaItem
    case insufficientAudio
    case invalidAudioFrame
    case shazam(String)

    public var errorDescription: String? {
        switch self {
        case .noMatch:
            return "ShazamKit could not identify the audible song."
        case .noUsableMediaItem:
            return "ShazamKit matched audio but returned no item with a title and artist."
        case .insufficientAudio:
            return "Not enough microphone audio was captured to identify the song."
        case .invalidAudioFrame:
            return "A captured audio frame had an invalid PCM shape."
        case let .shazam(message):
            return "ShazamKit could not complete recognition: \(message)"
        }
    }
}

/// Shazam catalog implementation backed exclusively by documented ShazamKit
/// signature APIs. It does not query or inspect any media-playing application.
public struct ShazamTrackIdentificationService: TrackIdentificationService, Sendable {
    public let sampleDuration: TimeInterval

    public init(sampleDuration: TimeInterval = 8) {
        self.sampleDuration = max(3, sampleDuration)
    }

    public func identifyTrack(from audioFrames: CapturedAudioStream) async throws -> TrackIdentity {
        let generator = SHSignatureGenerator()
        var accumulatedDuration: TimeInterval = 0

        for try await frame in audioFrames {
            try Task.checkCancellation()
            let buffer = try Self.makeAudioBuffer(from: frame)
            do {
                try generator.append(buffer, at: nil)
            } catch {
                throw ShazamIdentificationError.shazam(error.localizedDescription)
            }
            accumulatedDuration += TimeInterval(buffer.frameLength) / buffer.format.sampleRate
            if accumulatedDuration >= sampleDuration { break }
        }

        guard accumulatedDuration >= min(3, sampleDuration) else {
            throw ShazamIdentificationError.insufficientAudio
        }

        let signature = generator.signature()
        let result = await SHSession().result(from: signature)
        switch result {
        case let .match(match):
            return try Self.makeIdentity(from: match)
        case .noMatch:
            throw ShazamIdentificationError.noMatch
        case let .error(error, _):
            throw ShazamIdentificationError.shazam(error.localizedDescription)
        }
    }

    private static func makeIdentity(from match: SHMatch) throws -> TrackIdentity {
        guard let item = match.mediaItems.first(where: {
            clean($0.title) != nil && clean($0.artist) != nil
        }), let title = clean(item.title), let artist = clean(item.artist) else {
            throw ShazamIdentificationError.noUsableMediaItem
        }

        let confidence: Double?
        if #available(iOS 18.4, macOS 15.4, tvOS 18.4, watchOS 11.4, *) {
            confidence = Double(item.confidence)
        } else {
            confidence = nil
        }

        var attributes = [
            "matchOffsetSeconds": String(item.matchOffset),
            "frequencySkew": String(item.frequencySkew),
        ]
        if let url = item.webURL {
            attributes["catalogURL"] = url.absoluteString
        }

        return TrackIdentity(
            id: item.shazamID ?? item.appleMusicID ?? "shazam:\(title)|\(artist)",
            title: title,
            artist: artist,
            album: nil,
            artworkURL: item.artworkURL,
            duration: nil,
            recognizedAt: Date(),
            playbackPositionAtRecognition: max(0, item.predictedCurrentMatchOffset),
            identification: TrackIdentificationMetadata(
                source: "ShazamKit",
                confidence: confidence,
                sourceIdentifier: item.shazamID,
                attributes: attributes
            )
        )
    }

    private static func makeAudioBuffer(from frame: CapturedAudioFrame) throws -> AVAudioPCMBuffer {
        guard
            frame.channelCount > 0,
            frame.sampleRate > 0,
            !frame.samples.isEmpty,
            frame.samples.count.isMultiple(of: frame.channelCount),
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: frame.sampleRate,
                channels: AVAudioChannelCount(frame.channelCount),
                interleaved: false
            )
        else {
            throw ShazamIdentificationError.invalidAudioFrame
        }

        let frameCount = frame.samples.count / frame.channelCount
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ), let channelData = buffer.floatChannelData else {
            throw ShazamIdentificationError.invalidAudioFrame
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        for index in 0..<frameCount {
            for channel in 0..<frame.channelCount {
                channelData[channel][index] = frame.samples[(index * frame.channelCount) + channel]
            }
        }
        return buffer
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
