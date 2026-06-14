import SwiftUI

extension FullScreenImageView {
    var zoomControls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) {
                            currentScale = min(currentScale + zoomStep, maxScale)
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.title3)
                            .frame(width: 50, height: 50)
                    }
                    .accessibilityLabel(Text("Inzoomen", comment: "Accessibility: zoom in button"))

                    if currentScale > minScale {
                        Text("\(Int(currentScale * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) {
                            let newScale = currentScale - zoomStep
                            if newScale <= minScale {
                                resetZoom()
                            } else {
                                currentScale = newScale
                            }
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.title3)
                            .frame(width: 50, height: 50)
                    }
                    .accessibilityLabel(Text("Uitzoomen", comment: "Accessibility: zoom out button"))
                    .disabled(currentScale <= minScale)

                    if currentScale > minScale {
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) {
                                resetZoom()
                            }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.title3)
                                .frame(width: 50, height: 50)
                        }
                        .accessibilityLabel(Text("Zoom resetten", comment: "Accessibility: reset zoom to default"))
                    }
                }
                .buttonStyle(ZoomIconButtonStyle())
                .padding(16)
                .modifier(GlassControlsModifier())
                .focusSection()
            }
            .padding(.trailing, 40)
            .padding(.bottom, 40)
        }
    }
}

/// Applies Liquid Glass on tvOS 26+, falling back to an ultra-thin material on
/// older versions so the controls stay legible over bright imagery.
struct GlassControlsModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(tvOS 26, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: 12))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// Icon-only button style with a clear tvOS focus state (scale + circular
/// highlight + soft glow). `.plain` would leave the zoom controls without any
/// visible focus indication — the viewer cannot tell which button Select
/// will activate from the couch.
private struct ZoomIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .background(
                    Circle()
                        .fill(.white.opacity(isFocused ? 0.18 : 0))
                )
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .scaleEffect(configuration.isPressed ? 0.9 : (isFocused ? 1.15 : 1.0))
                .shadow(color: .white.opacity(isFocused ? 0.3 : 0), radius: 12)
                .animation(reduceMotion ? nil : .dumpiFocus, value: isFocused)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}
