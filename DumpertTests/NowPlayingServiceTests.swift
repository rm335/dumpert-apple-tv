import Testing
import MediaPlayer
import UIKit
@testable import Dumpert

@Suite("NowPlayingService Tests", .serialized)
@MainActor
struct NowPlayingServiceTests {

    private func configure(_ service: NowPlayingService, title: String, thumbnailURL: URL? = nil) {
        service.configure(
            title: title,
            thumbnailURL: thumbnailURL,
            duration: 120,
            onPlay: {}, onPause: {}, onSkipForward: {}, onSkipBackward: {}, onSeek: { _ in }
        )
    }

    private func writePNG() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("np-\(UUID().uuidString).png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        try image.pngData()!.write(to: url)
        return url
    }

    @Test("configure publishes the title and duration")
    func configurePublishesTitle() {
        let service = NowPlayingService()
        defer { service.cleanup() }
        configure(service, title: "Mijn filmpje")

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "Mijn filmpje")
        #expect(info?[MPMediaItemPropertyPlaybackDuration] as? Double == 120)
    }

    @Test("artwork that finishes loading after cleanup does not resurrect the info")
    func lateArtworkAfterCleanup() async throws {
        let png = try writePNG()
        let service = NowPlayingService()
        configure(service, title: "Weg", thumbnailURL: png)
        service.cleanup()

        // Give the detached artwork download time to finish and hop back to main.
        try await Task.sleep(for: .seconds(1))
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
    }

    @Test("artwork of a previous video is not applied to the next video")
    func staleArtworkAcrossVideos() async throws {
        let png = try writePNG()
        let service = NowPlayingService()
        defer { service.cleanup() }
        configure(service, title: "A", thumbnailURL: png)
        configure(service, title: "B")

        try await Task.sleep(for: .seconds(1))
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "B")
        #expect(info?[MPMediaItemPropertyArtwork] == nil)
    }
}
