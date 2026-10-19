import Testing
import Foundation
@testable import Dumpert

/// Focus can hop to another card and back inside the 250ms debounce window.
/// The pending hop must not win over the card that is focused now.
@Suite("Immersive Background State Tests")
@MainActor
struct ImmersiveBackgroundStateTests {

    private func item(_ id: String) -> MediaItem {
        .video(Video(
            id: id, title: id, descriptionText: "", date: nil, duration: 10,
            kudosTotal: 0, thumbnailURL: URL(string: "https://example.com/\(id).jpg"),
            streamURL: nil, tags: [], isNSFW: false
        ))
    }

    @Test("Focus hopping away and back within the debounce keeps the current card's image")
    func hopAwayAndBack() async throws {
        let state = ImmersiveBackgroundState()
        let a = item("a"), b = item("b")

        state.update(for: a)
        try await Task.sleep(for: .milliseconds(400))
        #expect(state.currentImageURL == a.thumbnailURL)

        state.update(for: b)   // focus moves to B...
        state.update(for: a)   // ...and straight back to A, before the debounce fires
        try await Task.sleep(for: .milliseconds(400))

        #expect(state.currentImageURL == a.thumbnailURL, "Background must follow the focused card (A), not the abandoned hop (B)")
    }
}
