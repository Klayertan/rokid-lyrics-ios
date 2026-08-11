import SwiftUI
import UIKit

struct PhysicalDeviceDiagnosticsView: View {
    @Bindable var model: AppModel
    @State private var copied = false

    var body: some View {
        Form {
            buildSection
            audioSection
            coexistenceSection
            shazamSection
            liveLyricsSection
            lyricsSection
            synchronizationSection
            diagnosticOutputSection
        }
        .navigationTitle("iPhone Device Tests")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                await model.refreshDeviceDiagnostics()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private var buildSection: some View {
        Section("Build and runtime") {
            LabeledContent("Compiled mode", value: model.compiledBuildModeText)
            LabeledContent("Active mode", value: model.activeRuntimeModeText)
            LabeledContent("Audio source", value: model.activeAudioSourceName)
        }
    }

    private var audioSection: some View {
        let audio = model.audioSessionDiagnostics.snapshot
        return Section {
            LabeledContent("Category", value: audio.category)
            LabeledContent("Mode", value: audio.mode)
            LabeledContent(
                "Options",
                value: audio.categoryOptions.isEmpty
                    ? "None" : audio.categoryOptions.joined(separator: ", ")
            )
            LabeledContent("Route", value: routeDescription(audio))
            LabeledContent(
                "Input device",
                value: audio.selectedInput.map { "\($0.name) [\($0.type)]" } ?? "None"
            )
            LabeledContent(
                "Sample rate",
                value: "\(audio.sampleRate.formatted(.number.precision(.fractionLength(0)))) Hz"
            )
            LabeledContent("Input channels", value: String(audio.inputChannelCount))
            LabeledContent("Output channels", value: String(audio.outputChannelCount))
            LabeledContent("Microphone capture", value: audio.isCaptureRunning ? "Running" : "Stopped")
            LabeledContent("Other audio playing", value: yesNo(audio.isOtherAudioPlaying))
            LabeledContent(
                "Secondary audio silence hint",
                value: yesNo(audio.secondaryAudioShouldBeSilenced)
            )
            LabeledContent("Last interruption", value: audio.interruptionState)
            LabeledContent("Route changes", value: String(audio.routeChangeCount))

            if model.audioSessionDiagnostics.events.isEmpty {
                Text("No audio-session notifications recorded.")
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup("Audio notification log (\(model.audioSessionDiagnostics.events.count))") {
                    ForEach(model.audioSessionDiagnostics.events.suffix(30)) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("+\(seconds(event.elapsedSeconds)) · \(event.category)")
                                .font(.caption.monospaced())
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .textSelection(.enabled)
                    }
                }
            }
        } header: {
            Text("Audio session")
        } footer: {
            Text(
                "This monitor records public session state and notifications only. It never reads or logs PCM samples.")
        }
    }

    private var coexistenceSection: some View {
        Section {
            Text(
                "Start audible music in YouTube Music, return here, then run this action. The app does not control or inspect YouTube Music."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button {
                model.startMusicCoexistenceTest()
            } label: {
                Label("TEST MUSIC COEXISTENCE", systemImage: "waveform.badge.mic")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isMicrophoneActive || model.isLyricsSessionActive)

            if model.isLyricsSessionActive {
                Button(role: .destructive) {
                    model.stopLyrics()
                } label: {
                    Label("STOP CURRENT SESSION", systemImage: "stop.fill")
                }
            }

            LabeledContent("Test state", value: model.musicCoexistenceDiagnostics.state)
            LabeledContent(
                "Other audio at start",
                value: optionalYesNo(model.musicCoexistenceDiagnostics.otherAudioWasPlayingAtStart)
            )
            LabeledContent(
                "Other audio now",
                value: optionalYesNo(model.musicCoexistenceDiagnostics.otherAudioIsPlayingNow)
            )

            Text("Record what you heard")
                .font(.subheadline.weight(.semibold))
            coexistenceToggle("Continued normally", keyPath: \.continuedNormally)
            coexistenceToggle("Ducked", keyPath: \.ducked)
            coexistenceToggle("Paused", keyPath: \.paused)
            coexistenceToggle("Route changed", keyPath: \.routeChanged)
            coexistenceToggle("Became inaudible", keyPath: \.becameInaudible)
            TextField("Optional local notes (not copied)", text: coexistenceNotesBinding)
        } header: {
            Text("YouTube Music coexistence")
        } footer: {
            Text(
                "iOS can report session and route facts, but only you can confirm audible ducking, pausing, or silence."
            )
        }
    }

    private var shazamSection: some View {
        let state = model.recognitionDiagnostics
        return Section("ShazamKit") {
            LabeledContent("Recognition state", value: state.state)
            LabeledContent("Start timestamp", value: formatted(state.startTimestamp))
            LabeledContent("Match timestamp", value: formatted(state.matchTimestamp))
            LabeledContent("Recognition latency", value: optionalSeconds(state.recognitionLatency))
            LabeledContent("Returned title", value: state.title ?? "Not returned")
            LabeledContent("Returned artist", value: state.artist ?? "Not returned")
            LabeledContent("Returned album", value: state.album ?? "Not provided by current adapter")
            LabeledContent("Shazam ID", value: state.shazamID ?? "Not returned")
            LabeledContent("Shazam catalog URL", value: state.catalogURL ?? "Not returned")
            if let error = state.error {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var liveLyricsSection: some View {
        Section {
            TextField("Song title", text: $model.liveLyricsTestTitle)
                .textInputAutocapitalization(.words)
            TextField("Artist", text: $model.liveLyricsTestArtist)
                .textInputAutocapitalization(.words)

            Button {
                model.runLiveLRCLibTest()
            } label: {
                if model.isLiveLyricsTestRunning {
                    HStack {
                        ProgressView()
                        Text("Requesting LRCLIB…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("LIVE LRCLIB TEST", systemImage: "network")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isLiveLyricsTestRunning)

            diagnosticRows(model.liveLyricsDiagnostics)

            ForEach(model.liveLyricsCandidates) { candidate in
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.title)
                        .font(.headline)
                    Text(candidate.artist)
                        .foregroundStyle(.secondary)
                    Text(
                        "synced=\(yesNo(candidate.hasSynchronizedLyrics)); plain=\(yesNo(candidate.hasPlainLyrics)); instrumental=\(yesNo(candidate.isInstrumental))"
                    )
                    .font(.caption.monospaced())
                    if let score = candidate.score {
                        Text("match score \(score.formatted(.number.precision(.fractionLength(3))))")
                            .font(.caption)
                    }
                }
            }
        } header: {
            Text("Optional live LRCLIB test")
        } footer: {
            Text(
                "This performs a real uncached runtime request. It displays metadata and availability only, never lyric text."
            )
        }
    }

    private var lyricsSection: some View {
        Section("Current pipeline LRCLIB") {
            diagnosticRows(model.lyricsDiagnostics)
        }
    }

    private var synchronizationSection: some View {
        Section("Synchronization") {
            LabeledContent("State", value: model.synchronizationState.rawValue)
            LabeledContent(
                "Monotonic elapsed",
                value: model.recognitionDiagnostics.startMonotonicTime.map {
                    seconds(max(0, ProcessInfo.processInfo.systemUptime - $0))
                } ?? "Not started"
            )
            LabeledContent("Estimated lyric position", value: seconds(model.playbackPosition))
            LabeledContent("Global offset", value: seconds(model.syncOffsetSeconds))
            LabeledContent(
                "Current lyric index",
                value: model.timelinePosition?.activeLineIndex.map(String.init) ?? "None"
            )
        }
    }

    private var diagnosticOutputSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = model.diagnosticsJSON
                copied = true
            } label: {
                Label(copied ? "COPIED" : "COPY DIAGNOSTICS", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            DisclosureGroup("Preview sanitized report") {
                ScrollView(.horizontal) {
                    Text(model.diagnosticsJSON)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Sanitized report")
        } footer: {
            Text(
                "The copied report omits route/device names, raw audio, callback URLs, credentials, tokens, and SDK logs."
            )
        }
    }

    @ViewBuilder
    private func diagnosticRows(_ state: LyricsProviderDiagnosticState) -> some View {
        LabeledContent("State", value: state.state)
        LabeledContent("Requested title", value: state.requestedTitle ?? "None")
        LabeledContent("Requested artist", value: state.requestedArtist ?? "None")
        LabeledContent("Candidate count", value: state.candidateCount.map(String.init) ?? "Unknown")
        LabeledContent(
            "Selected result",
            value: state.selectedResult.map { "\($0.title) — \($0.artist)" } ?? "None"
        )
        LabeledContent(
            "Synchronized lyrics",
            value: optionalYesNo(state.synchronizedLyricsAvailable)
        )
        LabeledContent("Lyric-line count", value: state.lyricLineCount.map(String.init) ?? "Unknown")
        LabeledContent("Request latency", value: optionalSeconds(state.requestLatency))
        if let error = state.error {
            Text(error)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func coexistenceToggle(
        _ title: String,
        keyPath: WritableKeyPath<MusicCoexistenceDiagnosticState, Bool>
    ) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { model.musicCoexistenceDiagnostics[keyPath: keyPath] },
                set: { model.musicCoexistenceDiagnostics[keyPath: keyPath] = $0 }
            )
        )
    }

    private var coexistenceNotesBinding: Binding<String> {
        Binding(
            get: { model.musicCoexistenceDiagnostics.notes },
            set: { model.musicCoexistenceDiagnostics.notes = $0 }
        )
    }

    private func routeDescription(_ audio: AudioSessionDiagnosticSnapshot) -> String {
        let inputs = audio.inputs.map { "\($0.name) [\($0.type)]" }.joined(separator: ", ")
        let outputs = audio.outputs.map { "\($0.name) [\($0.type)]" }.joined(separator: ", ")
        return "in: \(inputs.isEmpty ? "none" : inputs); out: \(outputs.isEmpty ? "none" : outputs)"
    }

    private func formatted(_ date: Date?) -> String {
        date?.formatted(date: .numeric, time: .standard) ?? "Not recorded"
    }

    private func optionalSeconds(_ value: TimeInterval?) -> String {
        value.map(seconds) ?? "Not recorded"
    }

    private func seconds(_ value: TimeInterval) -> String {
        "\(value.formatted(.number.precision(.fractionLength(3)))) s"
    }

    private func optionalYesNo(_ value: Bool?) -> String {
        value.map(yesNo) ?? "Unknown"
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}
