import Foundation

struct AudioRoutePortDiagnostic: Equatable, Identifiable {
    let name: String
    let type: String

    var id: String { "\(type)|\(name)" }
}

struct AudioSessionDiagnosticSnapshot: Equatable {
    var category = "Unavailable"
    var mode = "Unavailable"
    var categoryOptions: [String] = []
    var inputs: [AudioRoutePortDiagnostic] = []
    var outputs: [AudioRoutePortDiagnostic] = []
    var selectedInput: AudioRoutePortDiagnostic?
    var sampleRate: Double = 0
    var inputChannelCount = 0
    var outputChannelCount = 0
    var isCaptureRunning = false
    var isOtherAudioPlaying = false
    var secondaryAudioShouldBeSilenced = false
    var interruptionState = "None observed"
    var routeChangeCount = 0
}

struct DiagnosticEvent: Equatable, Identifiable {
    let sequence: Int
    let elapsedSeconds: TimeInterval
    let category: String
    let detail: String

    var id: Int { sequence }
}

struct RecognitionDiagnosticState: Equatable {
    var state = "Not started"
    var startTimestamp: Date?
    var startMonotonicTime: TimeInterval?
    var matchTimestamp: Date?
    var recognitionLatency: TimeInterval?
    var title: String?
    var artist: String?
    var album: String?
    var shazamID: String?
    var catalogURL: String?
    var error: String?
}

struct LyricsCandidateDiagnostic: Equatable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let hasSynchronizedLyrics: Bool
    let hasPlainLyrics: Bool
    let isInstrumental: Bool
    let score: Double?
}

struct LyricsProviderDiagnosticState: Equatable {
    var state = "Not requested"
    var requestedTitle: String?
    var requestedArtist: String?
    var candidateCount: Int?
    var selectedResult: LyricsCandidateDiagnostic?
    var synchronizedLyricsAvailable: Bool?
    var lyricLineCount: Int?
    var requestLatency: TimeInterval?
    var error: String?
}

struct MusicCoexistenceDiagnosticState: Equatable {
    var state = "Not started"
    var startedAt: Date?
    var elapsedSeconds: TimeInterval?
    var otherAudioWasPlayingAtStart: Bool?
    var otherAudioIsPlayingNow: Bool?
    var continuedNormally = false
    var ducked = false
    var paused = false
    var routeChanged = false
    var becameInaudible = false
    var notes = ""
}

struct GlassesMicrophoneDiagnosticState: Equatable {
    var state = "Not started"
    var streamConnected = false
    var sampleRate: Double?
    var channelCount: Int?
    var decodedByteCount = 0
    var pcmFrameCount = 0
    var bufferCount = 0
    var duration: TimeInterval = 0
    var recognitionRouting = "Not routed in isolated microphone test"
    var error: String?
}

struct RokidHardwareDiagnosticEvent: Equatable, Identifiable, Sendable {
    let sequence: Int
    let elapsedSeconds: TimeInterval
    let category: String
    let detail: String

    var id: Int { sequence }
}

struct RokidHardwareDiagnosticSnapshot: Equatable, Sendable {
    var connection = "Disconnected"
    var authorization = "Not started"
    var session = "Unavailable"
    var customView = "Closed"
    var audioStream = "Stopped"
    var events: [RokidHardwareDiagnosticEvent] = []
}

struct SafeDeviceDiagnosticReport: Encodable {
    struct Build: Encodable {
        let compiledMode: String
        let activeMode: String
        let sdkAvailable: Bool
    }

    struct Audio: Encodable {
        let category: String
        let mode: String
        let categoryOptions: [String]
        let inputPortTypes: [String]
        let outputPortTypes: [String]
        let selectedInputPortType: String?
        let sampleRate: Double
        let inputChannelCount: Int
        let outputChannelCount: Int
        let captureRunning: Bool
        let otherAudioPlaying: Bool
        let secondaryAudioShouldBeSilenced: Bool
        let interruptionState: String
        let routeChangeCount: Int
        let events: [Event]
    }

    struct Event: Encodable {
        let elapsedSeconds: TimeInterval
        let category: String
        let detail: String
    }

    struct Recognition: Encodable {
        let state: String
        let startTimestamp: Date?
        let matchTimestamp: Date?
        let latencySeconds: TimeInterval?
        let title: String?
        let artist: String?
        let album: String?
        let shazamID: String?
        let catalogURL: String?
        let error: String?
    }

    struct Lyrics: Encodable {
        let state: String
        let requestedTitle: String?
        let requestedArtist: String?
        let candidateCount: Int?
        let selectedResult: Candidate?
        let synchronizedLyricsAvailable: Bool?
        let lyricLineCount: Int?
        let requestLatencySeconds: TimeInterval?
        let error: String?
    }

    struct Candidate: Encodable {
        let providerID: String
        let title: String
        let artist: String
        let album: String?
        let hasSynchronizedLyrics: Bool
        let hasPlainLyrics: Bool
        let isInstrumental: Bool
        let score: Double?
    }

    struct Synchronization: Encodable {
        let state: String
        let monotonicElapsedSeconds: TimeInterval?
        let estimatedLyricPositionSeconds: TimeInterval
        let globalOffsetSeconds: TimeInterval
        let currentLyricIndex: Int?
    }

    struct Coexistence: Encodable {
        let state: String
        let startedAt: Date?
        let elapsedSeconds: TimeInterval?
        let otherAudioWasPlayingAtStart: Bool?
        let otherAudioIsPlayingNow: Bool?
        let continuedNormally: Bool
        let ducked: Bool
        let paused: Bool
        let routeChanged: Bool
        let becameInaudible: Bool
        let notes: String
    }

    struct Rokid: Encodable {
        let connection: String
        let authorization: String
        let session: String
        let customView: String
        let audioStream: String
        let lastSyntheticText: String?
        let events: [Event]
        let microphone: GlassesMicrophone
    }

    struct GlassesMicrophone: Encodable {
        let state: String
        let streamConnected: Bool
        let sampleRate: Double?
        let channelCount: Int?
        let decodedByteCount: Int
        let pcmFrameCount: Int
        let bufferCount: Int
        let durationSeconds: TimeInterval
        let recognitionRouting: String
        let error: String?
    }

    struct Display: Encodable {
        let status: String
        let trackTitle: String
        let artist: String
        let hasPreviousLine: Bool
        let activeLineCharacterCount: Int
        let hasNextLine: Bool
    }

    let schemaVersion = 2
    let generatedAt: Date
    let build: Build
    let audioSession: Audio
    let shazamKit: Recognition
    let lrclib: Lyrics
    let liveLRCLib: Lyrics
    let synchronization: Synchronization
    let musicCoexistence: Coexistence
    let rokidHardware: Rokid
    let lastDisplayPayload: Display?
    let lastError: String?
}

extension LyricsCandidateDiagnostic {
    var safeReportValue: SafeDeviceDiagnosticReport.Candidate {
        .init(
            providerID: id,
            title: title,
            artist: artist,
            album: album,
            hasSynchronizedLyrics: hasSynchronizedLyrics,
            hasPlainLyrics: hasPlainLyrics,
            isInstrumental: isInstrumental,
            score: score
        )
    }
}
