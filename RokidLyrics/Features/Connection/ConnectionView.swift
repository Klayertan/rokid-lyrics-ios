import SwiftUI

struct ConnectionView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AppPanel {
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(model.connectionState.statusColor.opacity(0.14))
                                .frame(width: 112, height: 112)
                            Image(systemName: "eyeglasses")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundStyle(model.connectionState.statusColor)
                        }
                        VStack(spacing: 5) {
                            Text(model.settings.mockMode ? "Mock Rokid Display" : "Rokid Glasses")
                                .font(.title2.bold())
                            Text(model.connectionStateText)
                                .foregroundStyle(model.connectionState.statusColor)
                                .font(.headline)
                        }

                        if model.connectionState == .connected {
                            Button(role: .destructive) {
                                model.disconnectRokid()
                            } label: {
                                Label("Disconnect", systemImage: "xmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                model.connectRokid()
                            } label: {
                                Label("Connect", systemImage: "link")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.mint)
                            .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                GlassesSimulatorView(model: model.currentDisplayModel, settings: model.settings)

                AppPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Build capability", systemImage: "hammer")
                            .font(.headline)
                        capabilityRow("Mock transport", status: "Available", color: .mint)
                        capabilityRow(
                            "RGCxrClient adapter",
                            status: model.isRealRokidSDKCompiled
                                ? (model.settings.mockMode ? "Compiled, inactive" : "Active")
                                : "Not in this build",
                            color: model.isRealRokidSDKCompiled ? .orange : .secondary
                        )
                        capabilityRow("Hardware verification", status: "Not performed", color: .secondary)
                        Divider()
                        Text(
                            "Mock Mode exercises the complete display-state boundary without claiming a physical connection. Hardware Mode requires the separately installed official Rokid SDK, Rokid AI authentication, signing, and glasses."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }

                AppPanel {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Connection behavior", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                        Text(
                            "Transient disconnects keep the lyric clock running. Automatic reconnect attempts occur no more than once every five seconds, and the current visible state is pushed after reconnection."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Rokid Connection")
    }

    private func capabilityRow(_ title: String, status: String, color: Color) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}
