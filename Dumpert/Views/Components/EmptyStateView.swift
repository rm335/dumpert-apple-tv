import SwiftUI

struct EmptyStateView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey
    var retryAction: (() -> Void)?

    @State private var iconPulse = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.5), isActive: iconPulse && !reduceMotion)
                .onAppear { iconPulse = true }
                .onDisappear { iconPulse = false }
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let retryAction {
                Button(action: retryAction) {
                    Text("Opnieuw proberen")
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
