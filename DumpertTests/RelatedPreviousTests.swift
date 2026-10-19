import Testing
import Foundation
@testable import Dumpert

/// "Vorige" must step back to the video that played right before, also when
/// that video was the last playlist item and the current one is a related
/// (autoplay tail) video.
@Suite("Related video previous navigation")
@MainActor
struct RelatedPreviousTests {

    private func makeVideo(id: String) -> Video {
        Video(
            id: id, title: id, descriptionText: "", date: nil, duration: 120,
            kudosTotal: 100, thumbnailURL: nil,
            streamURL: URL(string: "https://example.com/\(id).m3u8"),
            tags: [], isNSFW: false
        )
    }

    @Test("Previous after related autoplay returns to the last playlist video")
    func previousFromRelatedReturnsToLastPlaylistVideo() {
        let a = makeVideo(id: "a"), b = makeVideo(id: "b"), r = makeVideo(id: "r")
        let vm = VideoPlayerViewModel(video: b, playlist: [a, b], repository: VideoRepository())
        vm.relatedVideos = [r]

        vm.playNext()
        #expect(vm.currentVideo.id == "r")
        #expect(vm.previousVideo?.id == "b")

        vm.playPrevious()
        #expect(vm.currentVideo.id == "b")
    }

    @Test("Previous exists after related autoplay from a single-video playlist")
    func previousFromRelatedWithSingleVideoPlaylist() {
        let b = makeVideo(id: "b"), r = makeVideo(id: "r")
        let vm = VideoPlayerViewModel(video: b, playlist: [b], repository: VideoRepository())
        vm.relatedVideos = [r]

        vm.playNext()
        #expect(vm.currentVideo.id == "r")
        #expect(vm.hasPreviousVideo)
    }
}
