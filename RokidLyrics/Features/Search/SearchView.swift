import RokidLyricsCore
import SwiftUI

struct SearchView: View {
    @Bindable var model: AppModel

    var body: some View {
        List {
            if let url = model.pendingSharedURL {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Shared link received")
                                .font(.headline)
                            Text(url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(.mint)
                    }
                } footer: {
                    Text("The URL structure is not trusted as song metadata. Confirm the fields below.")
                }
            }

            Section("Song details") {
                TextField("Song title", text: $model.manualSearchTitle)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                TextField("Artist", text: $model.manualSearchArtist)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .onSubmit { model.searchLyrics() }

                Button {
                    model.searchLyrics()
                } label: {
                    HStack {
                        Label("Search LRCLIB", systemImage: "magnifyingglass")
                        Spacer()
                        if model.isSearching { ProgressView() }
                    }
                }
                .disabled(model.isSearching)
            }

            if !model.searchResults.isEmpty {
                Section {
                    ForEach(model.searchResults, id: \.candidate.id) { result in
                        candidateRow(result)
                    }
                } header: {
                    Text("Results")
                } footer: {
                    Text(
                        "Scores use conservative title, artist, album, and duration criteria. Close matches are shown instead of guessed."
                    )
                }
            } else if !model.isSearching {
                Section {
                    ContentUnavailableView {
                        Label("Manual fallback", systemImage: "music.note.list")
                    } description: {
                        Text(
                            "Enter a title and artist. Selecting a synchronized result starts its clock at 0:00; use the sync controls to align it with audible playback."
                        )
                    }
                }
            }
        }
        .navigationTitle("Find Lyrics")
        .alert("Search needs attention", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "Unknown error")
        }
    }

    private func candidateRow(_ result: ScoredLyricsCandidate) -> some View {
        Button {
            model.selectSearchResult(result)
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.mint.opacity(0.12))
                    Image(systemName: result.candidate.isInstrumental ? "music.note" : "quote.bubble")
                        .foregroundStyle(.mint)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.candidate.trackTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(result.candidate.artistName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if let album = result.candidate.albumName, !album.isEmpty {
                            Text(album).lineLimit(1)
                        }
                        if let duration = result.candidate.duration {
                            Text(duration, format: .number.precision(.fractionLength(0)))
                                + Text(" s")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(result.score, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit().weight(.semibold))
                    Text(availability(result.candidate))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(result.candidate.synchronizedLyrics == nil ? .orange : .mint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func availability(_ candidate: LyricsCandidate) -> String {
        if candidate.isInstrumental { return "Instrumental" }
        if candidate.synchronizedLyrics != nil { return "Synced" }
        if candidate.plainLyrics != nil { return "Plain only" }
        return "No lyrics"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.dismissError() } }
        )
    }
}
