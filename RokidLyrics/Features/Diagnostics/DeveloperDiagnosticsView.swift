import SwiftUI
import UIKit

struct DeveloperDiagnosticsView: View {
    @Bindable var model: AppModel
    @State private var copied = false

    var body: some View {
        List {
            Section("Live state") {
                LabeledContent("Rokid", value: model.connectionStateText)
                LabeledContent("Recognition", value: model.recognitionStateText)
                LabeledContent("Microphone", value: model.isMicrophoneActive ? "Active" : "Inactive")
                LabeledContent(
                    "Timeline",
                    value: "\(model.playbackPosition.formatted(.number.precision(.fractionLength(2)))) s"
                )
                LabeledContent(
                    "Offset",
                    value: "\(model.syncOffsetSeconds.formatted(.number.precision(.fractionLength(2)))) s"
                )
            }

            Section("Normalized metadata") {
                Text(model.normalizedMetadataText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Section("Lyrics provider") {
                Text(model.providerResultSummary)
                    .font(.caption)
            }

            Section {
                ScrollView(.horizontal) {
                    Text(model.diagnosticsJSON)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                Button {
                    UIPasteboard.general.string = model.diagnosticsJSON
                    copied = true
                } label: {
                    Label(
                        copied ? "Copied" : "Copy structured diagnostics",
                        systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text("Safe diagnostic output")
            } footer: {
                Text("Authentication tokens, callback URLs, credentials, raw audio, and SDK logs are never included.")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.diagnosticsJSON) { _, _ in copied = false }
    }
}
