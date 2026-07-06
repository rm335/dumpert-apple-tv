import Foundation

/// Global signal for whether a primary video player — full-screen *or*
/// Picture-in-Picture — is currently live. The app's background video decoders
/// consult this and stand down while a player is active:
/// - `VideoPreviewView`, the looping muted focus preview behind a grid card.
/// - `ThumbnailUpgradeService`, the smart-thumbnail frame extractor.
///
/// Why this exists: a second AVPlayer/decoder running behind the active player
/// competes for the shared hardware video decoder and starves the foreground
/// player's audio render thread. The video stays smooth while its sound drops
/// out or turns robotic at random moments — exactly the symptom users report.
///
/// The per-section `suspendPreview` flag (`selectedVideo != nil`) only silences
/// cards in the grid that presented the player. It misses every other playback
/// path: deep-link / Top Shelf videos presented from `ContentView`, and PiP
/// browsing (the cover is dismissed — so `suspendPreview` is false — while audio
/// keeps playing in the corner). This coordinator is the single authoritative
/// gate that covers them all.
@Observable @MainActor
final class PlaybackCoordinator {
    static let shared = PlaybackCoordinator()

    /// Number of live primary players. A counter rather than a `Bool` so an
    /// overlapping hand-off — e.g. opening a new video while a PiP player is
    /// still tearing down — can never clear the gate while a player still plays.
    private(set) var activePlayerCount = 0

    /// True while at least one primary player is live. Read by the background
    /// decoders to decide whether to suspend.
    var isPlaybackActive: Bool { activePlayerCount > 0 }

    private init() {}

    /// Called when a primary player starts (full-screen or PiP).
    func playbackBegan() {
        activePlayerCount += 1
    }

    /// Called when a primary player is fully torn down. Clamped at zero so an
    /// unexpected extra call can never drive the count negative and wedge the
    /// gate permanently closed.
    func playbackEnded() {
        activePlayerCount = max(0, activePlayerCount - 1)
    }

    // MARK: - Deep-link takeover

    /// Bumped when a deep link (Top Shelf tap) needs the stage cleared. The
    /// section views observe this and dismiss their own presented video/photo
    /// covers — ContentView cannot reach that local @State, yet its root-level
    /// deep-link cover can only present once every other cover is gone
    /// (UIKit refuses a second concurrent presentation).
    private(set) var deepLinkTakeoverID = 0

    func requestDeepLinkTakeover() {
        deepLinkTakeoverID += 1
    }
}
