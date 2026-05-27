import SwiftUI

struct ResumeOverlayView: View {
    let formattedTime: String
    let isVisible: Bool
    let onPlayFromBeginning: () -> Void

    var body: some View {
        VStack {
            if isVisible {
                HStack(spacing: 16) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))

                    Text("Hervat op \(formattedTime)", comment: "Resume overlay showing timestamp")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Button(action: onPlayFromBeginning) {
                        Text("Speel vanaf begin", comment: "Button to play video from start")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(ResumeButtonStyle())
                    .accessibilityLabel(Text("Speel video vanaf het begin", comment: "Accessibility: play from beginning"))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.75))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.top, 20)
                .padding(.leading, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Hervat op \(formattedTime)", comment: "Accessibility: resume at timestamp"))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.5), value: isVisible)
    }
}

// MARK: - Button Style

private struct ResumeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8)
            configuration.label
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(shape.fill(.white.opacity(0.2)))
                .foregroundStyle(.white)
                .overlay(shape.stroke(Color.white, lineWidth: isFocused ? 3 : 0))
                .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.08 : 1.0))
                .shadow(color: .white.opacity(isFocused ? 0.3 : 0), radius: 14)
                .animation(.spring(duration: 0.25, bounce: 0.2), value: isFocused)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}
