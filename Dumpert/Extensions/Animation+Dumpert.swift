import SwiftUI

/// Central motion tokens for the app — the single source of truth for animation
/// timing, mirroring `Color+Dumpert` for color. Referencing these by name (instead
/// of repeating `.spring(duration:…)` literals across views) keeps motion coherent
/// and means a tuning change happens in exactly one place.
///
/// Every animated view should pair a token with the Reduce Motion environment value,
/// e.g. `.animation(reduceMotion ? nil : .dumpiCard, value:)`. The convenience
/// helpers below do that automatically.
extension Animation {
    /// Focus gained on capsule controls — chips, pickers, buttons. (motion.focus)
    static let dumpiFocus = Animation.spring(duration: 0.25, bounce: 0.2)

    /// Card focus lift / brand shadow. (motion.card)
    static let dumpiCard = Animation.spring(duration: 0.35)

    /// Standard appearance & dismissal. (motion.standard)
    static let dumpiStandard = Animation.easeOut(duration: 0.3)

    /// Quick press feedback. (motion.press)
    static let dumpiPress = Animation.easeOut(duration: 0.12)

    /// Toast rising from the bottom. (motion.toast)
    static let dumpiToast = Animation.spring(duration: 0.4, bounce: 0.2)

    /// Selection changes in lists — sort order, load-more, category tab. (motion.selection)
    static let dumpiSelection = Animation.spring(duration: 0.5)

    /// Hero carousel rotation. (motion.carousel)
    static let dumpiCarousel = Animation.spring(duration: 0.7, bounce: 0.15)

    /// Player overlays fading in/out — resume, comment, now-playing, SharePlay. (motion.overlay)
    static let dumpiOverlay = Animation.easeInOut(duration: 0.5)
}
