import SwiftUI
import UIKit

struct RokidHardwareTestView: View {
    @Bindable var model: AppModel
    @State private var testText = "Rokid Lyrics Test"
    @State private var isolatedTestsConfirmed = false
    @State private var copied = false

    var body: some View {
        Form {
            modeSection
            connectionSection
            displaySection
            callbackSection
            glassesMicrophoneSection
            endToEndSection
            diagnosticSection
        }
        .navigationTitle("Rokid Hardware Test")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                await model.refreshDeviceDiagnostics()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private var modeSection: some View {
        Section {
            Text(model.compiledBuildModeText)
                .font(.title2.bold())
                .foregroundStyle(model.isRealRokidSDKCompiled ? .orange : .mint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            LabeledContent("Active runtime", value: model.activeRuntimeModeText)
            LabeledContent("Transport state", value: model.connectionStateText)
            if model.isLyricsSessionActive {
                Text("Stop the lyric pipeline before running isolated hardware actions.")
                    .foregroundStyle(.orange)
                Button("STOP LYRIC PIPELINE", role: .destructive) {
                    model.stopLyrics()
                }
            }
        } footer: {
            Text(
                model.isRealRokidSDKCompiled
                    ? "A hardware build only proves the SDK was compiled in. Results below remain unverified until you run them with physical glasses."
                    : "This is the Mock build. Controls exercise the same transport boundary but do not communicate with glasses."
            )
        }
    }

    private var connectionSection: some View {
        Section("Connection only") {
            Button {
                model.hardwareTestConnect()
            } label: {
                Label("CONNECT", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isLyricsSessionActive)

            Button(role: .destructive) {
                model.hardwareTestDisconnect()
            } label: {
                Label("DISCONNECT", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var displaySection: some View {
        Section {
            TextField("Synthetic test text", text: $testText)

            Button("SEND TEST TEXT") {
                model.hardwareTestSendText(testText)
            }
            .disabled(
                model.isLyricsSessionActive
                    || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            Button("CLEAR DISPLAY", role: .destructive) {
                model.hardwareTestClearDisplay()
            }
            .disabled(model.isLyricsSessionActive)

            Button("SEND COUNTER") {
                model.hardwareTestSendCounter()
            }
            .disabled(model.isLyricsSessionActive)
            LabeledContent("Next counter", value: "Test \(model.hardwareTestCounter + 1)")

            Button("UNICODE TEST") {
                model.hardwareTestSendUnicodeSequence()
            }
            .disabled(model.isLyricsSessionActive)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hello Rokid")
                Text("日本語テスト")
                Text("中文测试")
                Text("한국어 테스트")
            }
            .font(.body.monospaced())

            if let lastText = model.hardwareTestLastSyntheticText {
                LabeledContent("Last synthetic text", value: lastText)
            }

            GlassesSimulatorView(model: model.currentDisplayModel, settings: model.settings)
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 8)
        } header: {
            Text("Isolated display transport")
        } footer: {
            Text("These actions use synthetic text only and do not start ShazamKit, LRCLIB, or lyric synchronization.")
        }
    }

    private var callbackSection: some View {
        let diagnostic = model.rokidHardwareDiagnostics
        return Section {
            LabeledContent("Connection", value: diagnostic.connection)
            LabeledContent("Authorization", value: diagnostic.authorization)
            LabeledContent("Session", value: diagnostic.session)
            LabeledContent("CustomView", value: diagnostic.customView)
            LabeledContent("Audio stream", value: diagnostic.audioStream)

            if diagnostic.events.isEmpty {
                Text("No transport callbacks recorded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diagnostic.events.suffix(60)) { event in
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
        } header: {
            Text("Sanitized SDK callbacks")
        } footer: {
            Text("Token values, session IDs, device names, callback URLs, raw SDK errors, and SDK logs are excluded.")
        }
    }

    private var glassesMicrophoneSection: some View {
        let microphone = model.glassesMicrophoneDiagnostics
        return Section {
            if model.isMicrophoneActive {
                Button("STOP GLASSES MICROPHONE", role: .destructive) {
                    model.stopGlassesMicrophoneTest()
                }
            } else {
                Button("TEST GLASSES MICROPHONE") {
                    model.startGlassesMicrophoneTest()
                }
                .disabled(
                    !model.isRealRokidSDKCompiled
                        || model.settings.mockMode
                        || model.isLyricsSessionActive
                )
            }

            LabeledContent("State", value: microphone.state)
            LabeledContent("Stream connected", value: yesNo(microphone.streamConnected))
            LabeledContent(
                "Sample rate",
                value: microphone.sampleRate.map {
                    "\($0.formatted(.number.precision(.fractionLength(0)))) Hz"
                } ?? "Unknown"
            )
            LabeledContent("Channel count", value: microphone.channelCount.map(String.init) ?? "Unknown")
            LabeledContent("Decoded PCM bytes", value: String(microphone.decodedByteCount))
            LabeledContent("PCM frames", value: String(microphone.pcmFrameCount))
            LabeledContent("Buffers received", value: String(microphone.bufferCount))
            LabeledContent("Duration", value: seconds(microphone.duration))
            LabeledContent("ShazamKit routing", value: microphone.recognitionRouting)
            if let error = microphone.error {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Glasses microphone")
        } footer: {
            Text(
                "The verified SDK PCM API is used only in an active Hardware runtime. Raw audio stays in memory and is never saved or copied into diagnostics."
            )
        }
    }

    private var endToEndSection: some View {
        Section {
            Toggle(
                "I completed the isolated connection, text, clear, update, and Unicode checks",
                isOn: $isolatedTestsConfirmed)
            Button {
                model.startLyrics()
            } label: {
                Label("START COMPLETE PIPELINE", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                !isolatedTestsConfirmed
                    || model.connectionState != .connected
                    || model.isMicrophoneActive
                    || model.isLyricsSessionActive
            )
        } header: {
            Text("End-to-end mode")
        } footer: {
            Text(
                "This final action may start glasses PCM, ShazamKit, LRCLIB, synchronization, and display updates. Run it only after the isolated controls above have produced evidence."
            )
        }
    }

    private var diagnosticSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = model.diagnosticsJSON
                copied = true
            } label: {
                Label(copied ? "COPIED" : "COPY DIAGNOSTICS", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } footer: {
            Text("Paste the report back with the matching test number from docs/DEVICE_TEST_SESSION.md.")
        }
    }

    private func seconds(_ value: TimeInterval) -> String {
        "\(value.formatted(.number.precision(.fractionLength(2)))) s"
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}
