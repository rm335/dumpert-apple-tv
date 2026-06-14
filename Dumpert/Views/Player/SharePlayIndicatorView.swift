import SwiftUI

struct SharePlayIndicatorView: View {
    let participantCount: Int
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if isVisible {
                HStack(spacing: 8) {
                    Image(systemName: "shareplay")
                        .font(.caption)
                    Text(String(localized: "\(participantCount) kijkers", comment: "SharePlay participant count"))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.75))
                        .overlay(
                            Capsule()
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.top, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel(Text("SharePlay actief met \(participantCount) kijkers", comment: "Accessibility: SharePlay active with participant count"))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 50)
        .animation(reduceMotion ? nil : .dumpiOverlay, value: isVisible)
    }
}
