import SwiftUI
import UIKit

struct DeveloperDiagnosticsView: View {
    @Bindable var model: AppModel
    @State private var copied = false

    var body: some View {
        List {
            Section("Device validation") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.compiledBuildModeText)
                        .font(.headline)
                        .foregroundStyle(model.isRealRokidSDKCompiled ? .orange : .mint)
                    Text("Active runtime: \(model.activeRuntimeModeText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    PhysicalDeviceDiagnosticsView(model: model)
                } label: {
                    Label("Physical iPhone Tests", systemImage: "iphone.gen3.radiowaves.left.and.right")
                }

                NavigationLink {
                    RokidHardwareTestView(model: model)
                } label: {
                    Label("Rokid Hardware Test", systemImage: "eyeglasses")
                }
            }

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
                LabeledContent("Audio source", value: model.activeAudioSourceName)
                LabeledContent("Audio category", value: model.audioSessionDiagnostics.snapshot.category)
                LabeledContent("Audio route", value: safeRouteTypes)
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
                        copied ? "COPIED" : "COPY DIAGNOSTICS",
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
        .task { await model.refreshDeviceDiagnostics() }
    }

    private var safeRouteTypes: String {
        let snapshot = model.audioSessionDiagnostics.snapshot
        let inputs = snapshot.inputs.map(\.type).joined(separator: ",")
        let outputs = snapshot.outputs.map(\.type).joined(separator: ",")
        return "in=[\(inputs)]; out=[\(outputs)]"
    }
}
