import SwiftUI

/// Capsule-shaped button style for tvOS that adds an explicit focus state.
///
/// `.buttonStyle(.plain)` renders the label as-is on tvOS and provides no
/// visible focus indication — viewers cannot tell which chip/picker the
/// Siri Remote is on. This style keeps the existing capsule background
/// while layering a clear focus treatment (scale, white border, shadow)
/// so navigation from the couch is unambiguous.
struct FocusableCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .overlay(
                    Capsule()
                        .stroke(Color.white, lineWidth: isFocused ? 3 : 0)
                )
                .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.08 : 1.0))
                .shadow(color: .white.opacity(isFocused ? 0.25 : 0), radius: 14)
                .animation(.spring(duration: 0.25, bounce: 0.2), value: isFocused)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
