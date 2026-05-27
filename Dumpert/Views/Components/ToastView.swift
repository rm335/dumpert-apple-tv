import SwiftUI

/// A temporary toast notification that appears at the bottom of the screen.
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    let duration: TimeInterval

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.dumpiGreen)
                            .accessibilityHidden(true)
                        Text(message)
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background {
                        if #available(tvOS 26, *) {
                            Capsule()
                                .glassEffect()
                        } else {
                            Capsule()
                                .fill(.ultraThinMaterial)
                        }
                    }
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.2), value: message)
            .onChange(of: message) {
                guard let msg = message else { return }
                AccessibilityNotification.Announcement(msg).post()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(duration))
                    withAnimation { self.message = nil }
                }
            }
    }
}

extension View {
    func toast(message: Binding<String?>, duration: TimeInterval = 3) -> some View {
        modifier(ToastModifier(message: message, duration: duration))
    }
}
