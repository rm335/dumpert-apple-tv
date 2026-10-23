import SwiftUI

/// Picks where Siri Remote focus should land after a player cover closes.
/// With "Bekeken verbergen" on, the clip you just watched drops out of the
/// feed, so the card you came from is gone and focus would jump to a random card.
enum FocusRestore {
    /// `lastPlayed` if it is still shown; else the next surviving item after it
    /// (as laid out in `snapshot`), else the nearest surviving one before it.
    /// `nil` when `lastPlayed` was never in `snapshot` (e.g. a related clip).
    static func target(lastPlayed: String?, snapshot: [String], current: [String]) -> String? {
        guard let lastPlayed, let index = snapshot.firstIndex(of: lastPlayed) else { return nil }
        let alive = Set(current)
        if alive.contains(lastPlayed) { return lastPlayed }
        if let next = snapshot[(index + 1)...].first(where: alive.contains) { return next }
        return snapshot[..<index].last(where: alive.contains)
    }
}

/// Snapshots the section's item ids when a video opens and, when it closes,
/// moves scroll + focus to `FocusRestore.target`. Apply it where the
/// section's `ScrollViewProxy` is in scope (pass `nil` if there is none).
private struct RestoreFocusAfterPlayer: ViewModifier {
    let presentedID: String?
    let ids: [String]
    var focus: FocusState<String?>.Binding
    let proxy: ScrollViewProxy?

    @State private var snapshot: [String] = []
    @State private var tappedID: String?

    func body(content: Content) -> some View {
        content.onChange(of: presentedID) { _, new in
            if let new {
                snapshot = ids
                tappedID = new
                return
            }
            // Autoplay may have moved on; prefer the last clip, else the one tapped.
            let last = PlaybackCoordinator.shared.lastPlayedVideoID
            let anchor = last.flatMap { snapshot.contains($0) ? $0 : nil } ?? tappedID
            let current = ids
            guard let target = FocusRestore.target(lastPlayed: anchor, snapshot: snapshot, current: current) else { return }
            Task { @MainActor in
                // ponytail: fixed delay for the cover dismissal; no completion hook on fullScreenCover.
                try? await Task.sleep(for: .milliseconds(300))
                proxy?.scrollTo(target, anchor: .center)
                focus.wrappedValue = target
            }
        }
    }
}

extension View {
    func restoreFocusAfterPlayer(
        presentedID: String?,
        ids: [String],
        focus: FocusState<String?>.Binding,
        proxy: ScrollViewProxy? = nil
    ) -> some View {
        modifier(RestoreFocusAfterPlayer(presentedID: presentedID, ids: ids, focus: focus, proxy: proxy))
    }
}
