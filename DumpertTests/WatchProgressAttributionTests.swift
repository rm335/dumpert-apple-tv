import Testing
import Foundation
@testable import Dumpert

/// Regression tests for per-video resume attribution.
///
/// Root cause of the "resume is unreliable" bug: `VideoPlayerViewModel.init`
/// derived `currentVideo` from `playlist[startIndex]` with a `?? 0` fallback, so
/// when the tapped `video` was NOT in the supplied `playlist` (the Toppers tab
/// hands the player the hotshiz-only list while presenting Top-dag/week/maand
/// clips) `currentVideo` silently became `playlist[0]` — a *different* clip than
/// the stream `setupPlayer` loads (`video.streamURL`). Because every progress
/// read/write and the resume seek key off `currentVideo`, that desync produced
/// both reported symptoms at once:
///   (1) the tapped clip's progress was written under playlist[0]'s id, so the
///       clip itself never remembered its position (restart at 0:00), and
///   (2) playlist[0]'s saved position was seeked onto the tapped clip and the
///       tapped clip's playback time corrupted playlist[0] (positions "bleed").
@Suite("Watch Progress Attribution Tests")
@MainActor
struct WatchProgressAttributionTests {

    private func makeVideo(id: String, title: String = "Test") -> Video {
        Video(
            id: id,
            title: title,
            descriptionText: "",
            date: nil,
            duration: 120,
            kudosTotal: 100,
            thumbnailURL: nil,
            streamURL: URL(string: "https://example.com/\(id).m3u8"),
            tags: [],
            isNSFW: false
        )
    }

    // MARK: - The root-cause fix

    @Test("currentVideo stays the tapped video when it is absent from the playlist")
    func currentVideoWhenNotInPlaylist() {
        // Mirrors the Toppers tab: playlist is the hotshiz feed, but the user
        // tapped a Top-maand clip that isn't in it.
        let hotshiz = (1...3).map { makeVideo(id: "hot\($0)") }
        let tapped = makeVideo(id: "topmaand_x")
        let repo = VideoRepository()

        let vm = VideoPlayerViewModel(video: tapped, playlist: hotshiz, repository: repo)

        // Before the fix this was hotshiz[0] ("hot1") — a different clip than the
        // stream that actually plays.
        #expect(vm.currentVideo.id == "topmaand_x")
        #expect(vm.currentIndex == 0)
    }

    @Test("Progress is attributed to the tapped video, never to playlist[0]")
    func progressAttributedToTappedVideoNotPlaylistHead() {
        let hotshiz = (1...3).map { makeVideo(id: "hot\($0)") }
        let tapped = makeVideo(id: "topmaand_x")
        let repo = VideoRepository()

        // playlist[0] already has a saved position from an earlier session.
        repo.updateWatchProgress(videoId: "hot1", watchedSeconds: 42, totalSeconds: 120)

        let vm = VideoPlayerViewModel(video: tapped, playlist: hotshiz, repository: repo)

        // Simulate a saveProgress() tick for the clip that's actually playing.
        repo.updateWatchProgress(
            videoId: vm.currentVideo.id,
            watchedSeconds: 10,
            totalSeconds: 120
        )

        // Symptom (1): the tapped clip now remembers its own position.
        #expect(repo.progressFor("topmaand_x") > 0)
        // Symptom (2): playlist[0]'s position was NOT overwritten by the tapped
        // clip's playback time.
        #expect(repo.watchProgress["hot1"]?.watchedSeconds == 42)
    }

    @Test("A resumable position does not bleed from playlist[0] onto the tapped clip")
    func resumePositionDoesNotBleed() {
        // playlist[0] is deep into playback; the tapped clip is brand new.
        let hotshiz = (1...3).map { makeVideo(id: "hot\($0)") }
        let tapped = makeVideo(id: "fresh_clip")
        let repo = VideoRepository()
        repo.updateWatchProgress(videoId: "hot1", watchedSeconds: 60, totalSeconds: 120)

        let vm = VideoPlayerViewModel(video: tapped, playlist: hotshiz, repository: repo)

        // resumeIfNeeded reads watchProgress[currentVideo.id]. With currentVideo
        // correctly bound to the tapped clip, there is no saved position to resume
        // to — so the fresh clip cannot inherit hot1's 60s.
        #expect(vm.currentVideo.id == "fresh_clip")
        #expect(repo.watchProgress[vm.currentVideo.id] == nil)
    }

    // MARK: - Keying invariant (dictionary + cache round-trip)

    @Test("Distinct ids never share a WatchProgress entry across a cache round-trip")
    func distinctIdsNeverShareAnEntry() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DumpertTests-\(UUID().uuidString)", isDirectory: true)
        let cache = CacheService(cacheDirectory: dir)

        // A is watched halfway; B has never been played.
        let map: [String: WatchProgress] = [
            "A": WatchProgress(videoId: "A", watchedSeconds: 50, totalSeconds: 120),
            "B": WatchProgress(videoId: "B", watchedSeconds: 0, totalSeconds: 0),
        ]
        await cache.saveWatchProgress(map)
        let reloaded = await cache.loadWatchProgress()

        // A's resume point round-trips for A only; B does not adopt it.
        #expect(reloaded["A"]?.watchedSeconds == 50)
        #expect(reloaded["B"]?.watchedSeconds == 0)
        #expect(reloaded.count == 2)
    }
}
