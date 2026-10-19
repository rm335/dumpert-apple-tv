import Testing
import Foundation
@testable import Dumpert

/// "Markeer als onbekeken" must make a finished video look unwatched. It used to
/// flip only `isCompleted`, so the saved ~100% position survived and the video
/// landed on the Gekeken "Verder kijken" shelf with a full progress bar.
@Suite("Watched Toggle Tests")
@MainActor
struct WatchedToggleTests {

    @Test("Marking a finished video as unwatched drops its saved position")
    func unwatchedClearsSavedPosition() {
        let repo = VideoRepository()
        repo.updateWatchProgress(videoId: "toggle-v1", watchedSeconds: 118, totalSeconds: 120)
        #expect(repo.isWatched("toggle-v1"))

        repo.toggleWatched(videoId: "toggle-v1")

        #expect(!repo.isWatched("toggle-v1"))
        #expect(repo.progressFor("toggle-v1") == 0, "An unwatched video must not show up as in progress")
    }

    @Test("Marking a half-watched video as watched keeps its position")
    func watchedKeepsSavedPosition() {
        let repo = VideoRepository()
        repo.updateWatchProgress(videoId: "toggle-v2", watchedSeconds: 60, totalSeconds: 120)

        repo.toggleWatched(videoId: "toggle-v2")

        #expect(repo.isWatched("toggle-v2"))
        #expect(repo.progressFor("toggle-v2") == 0.5)
    }
}
