import RokidLyricsCore
import SwiftUI

struct NowPlayingView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            if let track = model.currentTrack {
                VStack(spacing: 22) {
                    trackHeader(track)
                    lyrics
                    progress
                    syncControls
                    lineControls
                    GlassesSimulatorView(model: model.currentDisplayModel, settings: model.settings)
                }
                .padding()
            } else {
                ContentUnavailableView {
                    Label("No lyrics playing", systemImage: "quote.bubble")
                } description: {
                    Text("Identify a song from Home or select a result from Search.")
                } actions: {
                    Button("Go to Home") { model.selectedTab = .home }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Lyrics Now Playing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.currentTrack != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.togglePause()
                    } label: {
                        Image(systemName: model.synchronizationState == .paused ? "play.fill" : "pause.fill")
                    }
                    .accessibilityLabel(model.synchronizationState == .paused ? "Resume lyrics" : "Pause lyrics")
                }
            }
        }
    }

    private func trackHeader(_ track: TrackIdentity) -> some View {
        VStack(spacing: 14) {
            TrackArtworkView(url: track.artworkURL, size: 168)
            VStack(spacing: 4) {
                Text(track.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(track.artist)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let album = track.album {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var lyrics: some View {
        AppPanel {
            LyricsTripletView(
                previous: model.timelinePosition?.previousLine?.text,
                active: model.timelinePosition?.activeLine?.text,
                next: model.timelinePosition?.nextLine?.text,
                scale: model.settings.fontScale
            )
        }
    }

    @ViewBuilder
    private var progress: some View {
        if let value = model.timelinePosition?.progress {
            VStack(spacing: 7) {
                ProgressView(value: value)
                    .tint(.mint)
                HStack {
                    Text(time(model.playbackPosition))
                    Spacer()
                    if let duration = model.currentTrack?.duration {
                        Text(time(duration))
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Image(systemName: "clock.badge.questionmark")
                Text("Track duration unavailable; lyric timing still advances from the recognition estimate.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var syncControls: some View {
        VStack(spacing: 11) {
            HStack(spacing: 8) {
                offsetButton("−5", seconds: -5)
                offsetButton("−1", seconds: -1)
                Button("SYNC") { model.syncActiveLineNow() }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
                    .foregroundStyle(.black)
                    .font(.caption.bold())
                    .accessibilityHint("Aligns the current lyric line with this moment")
                offsetButton("+1", seconds: 1)
                offsetButton("+5", seconds: 5)
            }
            Text("Correction: \(model.syncOffsetSeconds, format: .number.precision(.fractionLength(2))) s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var lineControls: some View {
        HStack {
            Button {
                model.moveToPreviousLine()
            } label: {
                Label("Previous lyric", systemImage: "backward.end.fill")
            }
            Spacer()
            Button {
                model.moveToNextLine()
            } label: {
                Label("Next lyric", systemImage: "forward.end.fill")
            }
        }
        .buttonStyle(.bordered)
        .font(.caption.weight(.semibold))
    }

    private func offsetButton(_ label: String, seconds: Double) -> some View {
        Button(label) { model.adjustOffset(by: seconds) }
            .buttonStyle(.bordered)
            .font(.caption.bold())
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Adjust lyrics by \(seconds, format: .number) seconds")
    }

    private func time(_ seconds: TimeInterval) -> String {
        let safe = max(0, Int(seconds))
        return String(format: "%d:%02d", safe / 60, safe % 60)
    }
}
