import RokidLyricsCore
import SwiftUI

struct StatusPill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.13), in: Capsule())
    }
}

struct AppPanel<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

struct TrackArtworkView: View {
    let url: URL?
    var size: CGFloat = 92

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image): image.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.mint.opacity(0.8), .cyan.opacity(0.45), .indigo.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "waveform")
                .font(.system(size: size * 0.34, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

struct LyricsTripletView: View {
    let previous: String?
    let active: String?
    let next: String?
    var scale: Double = 1

    var body: some View {
        VStack(spacing: 16) {
            lyric(previous, size: 15, weight: .regular, opacity: 0.42)
            lyric(active, size: 24, weight: .bold, opacity: 1)
            lyric(next, size: 17, weight: .medium, opacity: 0.68)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 160)
        .animation(.easeInOut(duration: 0.18), value: active)
    }

    @ViewBuilder
    private func lyric(_ text: String?, size: CGFloat, weight: Font.Weight, opacity: Double) -> some View {
        Text(text?.isEmpty == false ? text ?? "" : " ")
            .font(.system(size: size * scale, weight: weight, design: .rounded))
            .foregroundStyle(.primary.opacity(opacity))
            .lineLimit(3)
            .minimumScaleFactor(0.65)
            .contentTransition(.opacity)
    }
}

struct GlassesSimulatorView: View {
    let model: GlassesDisplayModel?
    let settings: AppSettings

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.black, Color(red: 0.02, green: 0.09, blue: 0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.mint.opacity(0.26), lineWidth: 1)

            VStack(spacing: 5) {
                HStack {
                    Image(systemName: "eyeglasses")
                    Text("GLASSES SIMULATOR")
                    Spacer()
                    Circle()
                        .fill(model == nil ? .gray : .mint)
                        .frame(width: 6, height: 6)
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.mint.opacity(0.65))

                Spacer(minLength: 6)
                Text(model?.trackTitle ?? "Rokid Lyrics")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)

                if settings.showPreviousLine, settings.lineCount >= 3 {
                    simulatorLine(model?.previousLine, size: 11, opacity: 0.35)
                }
                simulatorLine(model?.activeLine ?? "Start lyrics to preview", size: 16, opacity: 1)
                if settings.showNextLine, settings.lineCount >= 2 {
                    simulatorLine(model?.nextLine, size: 12, opacity: 0.62)
                }
                Spacer(minLength: 6)
            }
            .padding(18)
            .offset(y: CGFloat((settings.verticalPosition - 0.5) * 34))
        }
        .frame(height: 215)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Glasses display simulator")
    }

    private func simulatorLine(_ text: String?, size: CGFloat, opacity: Double) -> some View {
        Text(text?.isEmpty == false ? text ?? "" : " ")
            .font(.system(size: size * settings.fontScale, weight: opacity == 1 ? .bold : .medium, design: .rounded))
            .foregroundStyle(.white.opacity(opacity))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.55)
            .frame(maxWidth: .infinity)
    }
}

extension RokidConnectionState {
    var statusColor: Color {
        switch self {
        case .connected: return .mint
        case .connecting, .disconnecting: return .orange
        case .disconnected: return .secondary
        case .failed: return .red
        }
    }

    var statusSymbol: String {
        switch self {
        case .connected: return "checkmark.circle.fill"
        case .connecting, .disconnecting: return "arrow.triangle.2.circlepath"
        case .disconnected: return "circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}
