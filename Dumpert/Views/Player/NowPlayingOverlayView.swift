import SwiftUI

struct NowPlayingOverlayView: View {
    let title: String
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if isVisible {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
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
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityLabel(Text("Nu speelt: \(title)", comment: "Accessibility: now playing title"))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(reduceMotion ? nil : .dumpiOverlay, value: isVisible)
    }
}
