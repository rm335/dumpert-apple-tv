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
}
