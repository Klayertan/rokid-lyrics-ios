import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Stepper("Visible lines: \(model.settings.lineCount)", value: $model.settings.lineCount, in: 1...3)

                VStack(alignment: .leading) {
                    HStack {
                        Text("Font scale")
                        Spacer()
                        Text(model.settings.fontScale, format: .number.precision(.fractionLength(2)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $model.settings.fontScale, in: 0.75...1.6, step: 0.05)
                }

                Toggle("Show previous line", isOn: $model.settings.showPreviousLine)
                    .disabled(model.settings.lineCount < 3)
                Toggle("Show next line", isOn: $model.settings.showNextLine)
                    .disabled(model.settings.lineCount < 2)

                VStack(alignment: .leading) {
                    HStack {
                        Text("Vertical position")
                        Spacer()
                        Text(model.settings.verticalPosition, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.settings.verticalPosition, in: 0...1, step: 0.05)
                }
            } header: {
                Text("Glasses presentation")
            } footer: {
                Text(
                    "The simulator honors these settings. A real adapter applies only capabilities verified for the installed Rokid SDK and firmware."
                )
            }

            Section {
                Picker("Start behavior", selection: $model.settings.recognitionBehavior) {
                    ForEach(RecognitionBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                Toggle("Automatic reconnect", isOn: $model.settings.automaticReconnect)

                VStack(alignment: .leading) {
                    HStack {
                        Text("Default lyric offset")
                        Spacer()
                        Text("\(model.settings.defaultLyricOffset, format: .number.precision(.fractionLength(1))) s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $model.settings.defaultLyricOffset, in: -10...10, step: 0.5)
                }
            } header: {
                Text("Recognition")
            } footer: {
                Text("Shazam recognition records a short microphone sample only after Start Lyrics is pressed.")
            }

            Section {
                Picker("Transliteration", selection: $model.settings.transliterationMode) {
                    ForEach(PlaceholderTextMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Translation", selection: $model.settings.translationMode) {
                    ForEach(PlaceholderTextMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Future text modes")
            } footer: {
                Text(
                    "These controls reserve the UX only. No transliteration or translation service is implemented yet.")
            }

            Section {
                Toggle("Developer / Mock Mode", isOn: mockBinding)
                NavigationLink {
                    DeveloperDiagnosticsView(model: model)
                } label: {
                    Label("Developer Diagnostics", systemImage: "stethoscope")
                }
            } header: {
                Text("Development")
            } footer: {
                Text("Mock Mode is always available and does not claim a physical glasses connection.")
            }

            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                if let url = URL(string: "https://lrclib.net/docs") {
                    Link("LRCLIB API documentation", destination: url)
                }
                if let url = URL(string: "https://developer.apple.com/documentation/shazamkit") {
                    Link("ShazamKit documentation", destination: url)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var mockBinding: Binding<Bool> {
        Binding(
            get: { model.settings.mockMode },
            set: { model.updateMockMode($0) }
        )
    }
}
