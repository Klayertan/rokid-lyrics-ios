import SwiftUI

struct HomeView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                connectionAndRecognition
                currentSong
                GlassesSimulatorView(model: model.currentDisplayModel, settings: model.settings)
                controls
                limitationNote
            }
            .padding()
        }
        .background(background)
        .navigationTitle("Rokid Lyrics")
        .navigationBarTitleDisplayMode(.large)
        .alert("Needs attention", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "Unknown error")
        }
    }

    private var hero: some View {
        AppPanel {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.mint.gradient)
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.82))
                }
                .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Lyrics in your line of sight")
                        .font(.title3.bold())
                    Text(
                        "Identify ambient music with ShazamKit, then keep a minimal synchronized overlay ready for Rokid."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var connectionAndRecognition: some View {
        HStack(spacing: 10) {
            StatusPill(
                title: model.connectionStateText,
                systemImage: model.connectionState.statusSymbol,
                color: model.connectionState.statusColor
            )
            StatusPill(
                title: model.isMicrophoneActive ? "Microphone active" : model.recognitionStateText,
                systemImage: model.isMicrophoneActive ? "mic.fill" : "waveform",
                color: model.isMicrophoneActive ? .red : .cyan
            )
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var currentSong: some View {
        AppPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("CURRENT SONG")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 15) {
                    TrackArtworkView(url: model.currentTrack?.artworkURL)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.currentTrack?.title ?? "Waiting for a song")
                            .font(.title3.bold())
                            .lineLimit(2)
                        Text(model.currentTrack?.artist ?? "Press Start Lyrics while music is audible")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(model.statusMessage)
                            .font(.caption)
                            .foregroundStyle(model.isMicrophoneActive ? .red : .mint)
                            .padding(.top, 3)
                    }
                    Spacer()
                }

                Divider()
                LyricsTripletView(
                    previous: model.timelinePosition?.previousLine?.text,
                    active: model.timelinePosition?.activeLine?.text,
                    next: model.timelinePosition?.nextLine?.text,
                    scale: 0.82
                )
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                model.startLyrics()
            } label: {
                Label(
                    model.isMicrophoneActive ? "Listening…" : "Start Lyrics",
                    systemImage: model.isMicrophoneActive ? "mic.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .foregroundStyle(.black)
            .controlSize(.large)
            .disabled(model.isMicrophoneActive)

            Button(role: .destructive) {
                model.stopLyrics()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.synchronizationState == .idle)
        }
    }

    private var limitationNote: some View {
        Label(
            "YouTube Music is treated only as audible sound. This app does not read its queue, playback state, or private APIs.",
            systemImage: "lock.shield"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var background: some View {
        LinearGradient(
            colors: [Color.mint.opacity(0.09), Color.clear, Color.indigo.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.dismissError() } }
        )
    }
}
