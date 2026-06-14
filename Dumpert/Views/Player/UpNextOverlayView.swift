import SwiftUI

/// Overlay shown near the end of a video, displaying the next video's
/// thumbnail, title, and a countdown timer with play/cancel actions.
struct UpNextOverlayView: View {
    let nextVideo: Video
    let countdown: Int
    let totalCountdown: Int
    let onPlayNow: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusedButton: UpNextButton?

    private enum UpNextButton {
        case playNow, cancel
    }

    var body: some View {
        HStack(spacing: 20) {
            // Thumbnail of next video
            FaceCenteredThumbnailView(url: nextVideo.thumbnailURL)
                .frame(width: 240, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                // Header with countdown ring
                HStack(spacing: 10) {
                    CountdownRingView(
                        countdown: countdown,
                        total: totalCountdown
                    )

                    Text("Volgende video", comment: "Up next overlay header")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Next video title
                Text(nextVideo.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .foregroundStyle(.white)

                // Duration
                if nextVideo.duration > 0 {
                    Text(nextVideo.duration.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                }

                // Buttons
                HStack(spacing: 12) {
                    Button(action: onPlayNow) {
                        Label("Afspelen", systemImage: "play.fill")
                            .font(.callout)
                            .fontWeight(.semibold)
                    }
                    .focused($focusedButton, equals: .playNow)
                    .buttonStyle(UpNextButtonStyle(isPrimary: true))
                    .accessibilityLabel(Text("Speel nu af: \(nextVideo.title)", comment: "Accessibility: play next video now"))

                    Button(action: onCancel) {
                        Text("Annuleren", comment: "Cancel button")
                            .font(.callout)
                    }
                    .focused($focusedButton, equals: .cancel)
                    .buttonStyle(UpNextButtonStyle(isPrimary: false))
                    .accessibilityLabel(Text("Annuleer volgende video", comment: "Accessibility: cancel up next"))
                }
            }
        }
        .padding(24)
        .modifier(GlassCardModifier(cornerRadius: 24))
        .padding(.bottom, 80)
        .padding(.trailing, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .onAppear {
            focusedButton = .playNow
        }
    }

}

// MARK: - Countdown Ring

private struct CountdownRingView: View {
    let countdown: Int
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(countdown) / Double(total)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: countdown)

            Text("\(countdown)")
                .font(.caption2)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
        .accessibilityLabel(Text("Aftelling: \(countdown) seconden", comment: "Accessibility: countdown timer seconds remaining"))
    }
}

// MARK: - Glass Card Background

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(tvOS 26, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.black.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        )
                )
        }
    }
}

// MARK: - Button Style

private struct UpNextButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, isPrimary: isPrimary)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let isPrimary: Bool
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8)
            configuration.label
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(shape.fill(isPrimary ? Color.white : Color.white.opacity(0.15)))
                .foregroundStyle(isPrimary ? .black : .white)
                .overlay(
                    shape
                        .stroke(isPrimary ? Color.black : Color.white,
                                lineWidth: isFocused ? 3 : 0)
                )
                .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.08 : 1.0))
                .shadow(color: .white.opacity(isFocused ? 0.3 : 0), radius: 14)
                .animation(reduceMotion ? nil : .dumpiFocus, value: isFocused)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}
