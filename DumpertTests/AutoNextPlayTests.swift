import Testing
import Foundation
@testable import Dumpert

/// Tests for the auto next play feature.
/// The core autoplay logic (checkUpNext, onVideoFinished) depends on AVPlayer
/// runtime behavior so it requires integration testing. These tests verify the
/// computed properties and state that drive the autoplay decisions.
@Suite("Auto Next Play Tests")
@MainActor
struct AutoNextPlayTests {

    // MARK: - Helpers

    private func makeVideo(
        id: String = "v1",
        title: String = "Test",
        duration: Int = 120,
        streamURL: URL? = URL(string: "https://example.com/v.m3u8")
    ) -> Video {
        Video(
            id: id,
            title: title,
            descriptionText: "",
            date: nil,
            duration: duration,
            kudosTotal: 100,
            thumbnailURL: nil,
            streamURL: streamURL,
            tags: [],
            isNSFW: false
        )
    }

    private func makeViewModel(
        video: Video? = nil,
        playlist: [Video]? = nil,
        autoplay: Bool = true,
        upNextOverlay: Bool = true,
        upNextCountdown: Int = 5,
        upNextMinimumVideo: Int = 60
    ) -> VideoPlayerViewModel {
        let v = video ?? makeVideo()
        let list = playlist ?? [v]
        let repo = VideoRepository()
        repo.settings.autoplayEnabled = autoplay
        repo.settings.upNextOverlayEnabled = upNextOverlay
        repo.settings.upNextCountdownSeconds = upNextCountdown
        repo.settings.upNextMinimumVideoSeconds = upNextMinimumVideo
        return VideoPlayerViewModel(video: v, playlist: list, repository: repo)
    }

    // MARK: - nextVideo

    @Test("nextVideo returns next playlist item")
    func nextVideoFromPlaylist() {
        let videos = (1...3).map { makeVideo(id: "v\($0)", title: "Video \($0)") }
        let vm = makeViewModel(video: videos[0], playlist: videos)

        #expect(vm.nextVideo?.id == "v2")
        #expect(vm.hasNextVideo)
    }

    @Test("nextVideo is nil at end of playlist without related videos")
    func noNextAtEnd() {
        let v = makeVideo()
        let vm = makeViewModel(video: v, playlist: [v])

        #expect(vm.nextVideo == nil)
        #expect(!vm.hasNextVideo)
    }

    @Test("nextVideo returns correct item for mid-playlist position")
    func nextVideoMidPlaylist() {
        let videos = (1...5).map { makeVideo(id: "v\($0)") }
        // Start at v3 (index 2), next should be v4
        let vm = makeViewModel(video: videos[2], playlist: videos)

        #expect(vm.nextVideo?.id == "v4")
    }

    // MARK: - previousVideo

    @Test("previousVideo is nil at start of playlist")
    func noPreviousAtStart() {
        let videos = (1...3).map { makeVideo(id: "v\($0)") }
        let vm = makeViewModel(video: videos[0], playlist: videos)

        #expect(vm.previousVideo == nil)
        #expect(!vm.hasPreviousVideo)
    }

    @Test("previousVideo returns correct item for mid-playlist")
    func previousVideoMidPlaylist() {
        let videos = (1...3).map { makeVideo(id: "v\($0)") }
        let vm = makeViewModel(video: videos[1], playlist: videos)

        #expect(vm.previousVideo?.id == "v1")
        #expect(vm.hasPreviousVideo)
    }

    // MARK: - Settings reflection

    @Test("autoplayEnabled reflects repository settings")
    func autoplaySetting() {
        let vm = makeViewModel(autoplay: false)
        #expect(!vm.autoplayEnabled)

        let vm2 = makeViewModel(autoplay: true)
        #expect(vm2.autoplayEnabled)
    }

    @Test("upNextCountdownSeconds reflects repository settings")
    func countdownSetting() {
        let vm = makeViewModel(upNextCountdown: 10)
        #expect(vm.upNextCountdownSeconds == 10)
    }

    // MARK: - cancelUpNext

    @Test("cancelUpNext hides overlay")
    func cancelHidesOverlay() {
        let videos = (1...3).map { makeVideo(id: "v\($0)") }
        let vm = makeViewModel(video: videos[0], playlist: videos)

        vm.cancelUpNext()
        #expect(!vm.showUpNext)
    }

    // MARK: - skipToNext

    @Test("skipToNext hides overlay and advances to next video")
    func skipToNextAdvances() {
        let videos = (1...3).map { makeVideo(id: "v\($0)") }
        let vm = makeViewModel(video: videos[0], playlist: videos)

        // skipToNext calls playNext which changes currentVideo
        vm.skipToNext()
        #expect(!vm.showUpNext)
        #expect(vm.currentVideo.id == "v2")
        #expect(vm.nextVideo?.id == "v3")
    }

    @Test("skipToNext chains through entire playlist")
    func skipThroughPlaylist() {
        let videos = (1...4).map { makeVideo(id: "v\($0)") }
        let vm = makeViewModel(video: videos[0], playlist: videos)

        vm.skipToNext()
        #expect(vm.currentVideo.id == "v2")

        vm.skipToNext()
        #expect(vm.currentVideo.id == "v3")

        vm.skipToNext()
        #expect(vm.currentVideo.id == "v4")
        #expect(!vm.hasNextVideo)
    }

    // MARK: - playPrevious

    @Test("playPrevious goes back in playlist")
    func playPreviousGoesBack() {
        let videos = (1...3).map { makeVideo(id: "v\($0)") }
        let vm = makeViewModel(video: videos[0], playlist: videos)

        vm.skipToNext() // v1 → v2
        vm.skipToNext() // v2 → v3
        #expect(vm.currentVideo.id == "v3")

        vm.playPrevious() // v3 → v2
        #expect(vm.currentVideo.id == "v2")

        vm.playPrevious() // v2 → v1
        #expect(vm.currentVideo.id == "v1")
        #expect(!vm.hasPreviousVideo)
    }

    // MARK: - Edge cases

    @Test("Empty playlist uses single video")
    func emptyPlaylistUsesSingleVideo() {
        let v = makeVideo(id: "solo")
        let vm = makeViewModel(video: v, playlist: [])

        // With empty playlist, currentVideo falls back to the init video
        #expect(vm.currentVideo.id == "solo")
        #expect(!vm.hasNextVideo)
        #expect(!vm.hasPreviousVideo)
    }

    @Test("Video without streamURL still creates viewModel")
    func noStreamURL() {
        let v = makeVideo(id: "nostream", streamURL: nil)
        let vm = makeViewModel(video: v, playlist: [v])

        #expect(vm.currentVideo.id == "nostream")
        #expect(vm.currentVideo.streamURL == nil)
    }

    @Test("currentVideo matches initial video")
    func currentVideoMatchesInit() {
        let videos = (1...3).map { makeVideo(id: "v\($0)") }
        let vm = makeViewModel(video: videos[1], playlist: videos)

        #expect(vm.currentVideo.id == "v2")
    }

    @Test("Start index is matched by id, not full value-equality")
    func startIndexMatchesById() {
        let videos = (1...4).map { makeVideo(id: "v\($0)") }
        // Same id as videos[2], but a diverging field. Video is Hashable over
        // every field (incl. stats), so firstIndex(of:) would miss this copy and
        // fall back to 0 — starting the wrong video.
        let divergent = makeVideo(id: "v3", title: "A different cached copy")
        let repo = VideoRepository()
        let vm = VideoPlayerViewModel(video: divergent, playlist: videos, repository: repo)

        #expect(vm.currentIndex == 2, "Should locate the matching id, not fall back to 0")
        #expect(vm.currentVideo.id == "v3")
        #expect(vm.nextVideo?.id == "v4")
    }

    // MARK: - Related-video handoff

    @Test("playNext switches currentVideo to the related video once the playlist is exhausted")
    func playNextAdoptsRelatedVideoAsCurrent() {
        // Regression: when autoplay transitioned from the last playlist item
        // into a related-video tail, `currentIndex` was deliberately left at
        // the last playlist position (only `relatedVideos.removeFirst()` ran).
        // Because `currentVideo` was derived from `playlist[currentIndex]`,
        // every subsequent `saveProgress()` tick attributed the related
        // video's playback time to the *previous* playlist video's id —
        // which then flipped `isCompleted` back to false because
        // `WatchProgress.update` rederives completion from raw progress.
        let last = makeVideo(id: "v_last")
        let related = makeVideo(id: "v_related")
        let vm = makeViewModel(video: last, playlist: [last])

        // Simulate the async fetch having already returned a related video.
        vm.relatedVideos = [related]
        #expect(vm.currentVideo.id == "v_last")
        #expect(vm.hasNextVideo)

        vm.playNext()

        #expect(vm.currentVideo.id == "v_related")
        // Related queue consumed its head, currentIndex unchanged.
        #expect(vm.currentIndex == 0)
        #expect(vm.relatedVideos.isEmpty)
    }

    @Test("Related-video autoplay does not wipe the previous video's watched mark")
    func relatedAutoplayPreservesPreviousWatchedMark() {
        // End-to-end consequence of the bug above: while the related video
        // was playing, time-observer-driven `saveProgress()` calls wrote the
        // related video's small currentTime/large duration under the old
        // video's id. `WatchProgress.update` recomputed isCompleted from
        // those values (<0.9) and demoted the previous video from watched
        // back to in-progress, making it reappear in lists that filter on
        // `hideWatched`.
        let repo = VideoRepository()
        let last = makeVideo(id: "v_last")
        let related = makeVideo(id: "v_related")

        repo.markAsWatched(videoId: last.id)
        #expect(repo.isWatched(last.id))

        let vm = VideoPlayerViewModel(video: last, playlist: [last], repository: repo)
        vm.relatedVideos = [related]
        vm.playNext()

        // Simulate the time-observer firing for the related video's playback.
        // After the fix this updates progress for "v_related"; before the fix
        // it would have updated "v_last" and flipped isCompleted to false.
        repo.updateWatchProgress(
            videoId: vm.currentVideo.id,
            watchedSeconds: 5,
            totalSeconds: 120
        )

        #expect(repo.isWatched(last.id), "Previous video must remain marked as watched")
        #expect(repo.progressFor(related.id) > 0, "Related video should have its own progress recorded")
    }

    // MARK: - Watched-on-finish

    @Test("Finishing a video marks it watched even when autoplay does not advance")
    func finishMarksWatchedWithoutAdvancing() {
        // Regression: reaching the end only marked the video watched when
        // `playNext` ran. With autoplay off (or on the last/only video) the
        // finish path never called `markAsWatched`, leaving fully-watched
        // videos stuck as unwatched.
        let repo = VideoRepository()
        repo.settings.autoplayEnabled = false
        let v = makeVideo(id: "v1", duration: 120)
        let vm = VideoPlayerViewModel(video: v, playlist: [v], repository: repo)

        #expect(!repo.isWatched(v.id))
        vm.onVideoFinished(playedToEnd: true)
        #expect(repo.isWatched(v.id), "Reaching the end must mark the video watched")
    }

    @Test("Short clip watched to the end is marked watched despite the 90% threshold")
    func finishMarksShortClipWatched() {
        // An 8s clip's last 1s-interval progress tick lands around 7s
        // (7/8 = 0.875), below the 0.9 completion threshold — so before the fix
        // it stayed unwatched. Seed that sub-threshold progress, then finish.
        let repo = VideoRepository()
        repo.settings.autoplayEnabled = false
        let v = makeVideo(id: "short", duration: 8)
        let vm = VideoPlayerViewModel(video: v, playlist: [v], repository: repo)

        repo.updateWatchProgress(videoId: v.id, watchedSeconds: 7, totalSeconds: 8)
        #expect(!repo.isWatched(v.id), "Precondition: 7/8 is below the 0.9 threshold")

        vm.onVideoFinished(playedToEnd: true)
        #expect(repo.isWatched(v.id))
    }

    @Test("A playback failure does not mark an unfinished video as watched")
    func failedPlaybackDoesNotMarkWatched() {
        let repo = VideoRepository()
        repo.settings.autoplayEnabled = false
        let v = makeVideo(id: "v1", duration: 120)
        let vm = VideoPlayerViewModel(video: v, playlist: [v], repository: repo)

        vm.onVideoFinished(playedToEnd: false)
        #expect(!repo.isWatched(v.id), "Failing to reach the end must not mark watched")
    }
}
