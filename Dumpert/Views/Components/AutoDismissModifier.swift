import SwiftUI

/// Auto-dismisses a boolean binding after a delay with a smooth animation.
/// Used for transient feedback indicators (checkmarks, confirmation toasts).
extension View {
    func autoDismiss(_ isShowing: Binding<Bool>, after duration: TimeInterval = 4) -> some View {
        modifier(AutoDismissModifier(isShowing: isShowing, duration: duration))
    }
}

/// Backing modifier so the dismissal can read the Reduce Motion environment value
/// and skip the animation when motion is reduced. (A free `View` extension cannot
/// declare `@Environment`, so the logic lives here.)
private struct AutoDismissModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isShowing: Binding<Bool>
    let duration: TimeInterval

    func body(content: Content) -> some View {
        content.onChange(of: isShowing.wrappedValue) {
            if isShowing.wrappedValue {
                let reduceMotion = reduceMotion
                Task {
                    try? await Task.sleep(for: .seconds(duration))
                    withAnimation(reduceMotion ? nil : .smooth) { isShowing.wrappedValue = false }
                }
            }
        }
    }
}
