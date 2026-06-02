import SwiftUI

/// Tracks which media item's thumbnail should be shown as the immersive background.
/// Debounces rapid focus changes to prevent flickering during fast scrolling.
@Observable @MainActor
final class ImmersiveBackgroundState {
    private(set) var currentImageURL: URL?
    private(set) var fallbackImageURL: URL?
    private var debounceTask: Task<Void, Never>?

    /// The URL to display: current focused item, or fallback (random classics) if none.
    var activeURL: URL? {
        currentImageURL ?? fallbackImageURL
    }

    /// Update the background for a newly focused media item (debounced 250ms).
    /// The longer settle keeps the backdrop calm during fast focus traversal
    /// instead of strobing one image per focus hop.
    func update(for item: MediaItem) {
        let url = item.thumbnailURL
        guard url != currentImageURL else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            currentImageURL = url
        }
    }

    /// Clear the current image so `activeURL` returns the fallback.
    /// Use on tabs without media items (Settings) or without focused items (empty Search).
    func useFallback() {
        debounceTask?.cancel()
        currentImageURL = nil
    }

    /// Pick a new random classics item as fallback background.
    func shuffleFallback(from classics: [MediaItem]) {
        guard !classics.isEmpty else { return }
        fallbackImageURL = classics.randomElement()?.thumbnailURL
    }
}
