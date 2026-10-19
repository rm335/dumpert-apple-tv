import Testing
import Foundation
@testable import Dumpert

/// Answers the stub video's /related request with an empty 200 and counts hits.
final class EmptyRelatedProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var hits = 0

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.absoluteString.contains("/related/relfetch_stub") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.hits += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"success":true,"items":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// The periodic time observer runs checkUpNext once a second. A "no related
/// videos" answer must not make every following tick fetch again.
@Suite("Related videos fetch", .serialized)
@MainActor
struct RelatedFetchTests {

    @Test("An empty related result is fetched once, not on every tick")
    func emptyRelatedResultIsNotRefetched() async {
        EmptyRelatedProtocol.hits = 0
        let video = Video(
            id: "relfetch_stub", title: "t", descriptionText: "", date: nil, duration: 100,
            kudosTotal: 100, thumbnailURL: nil,
            streamURL: URL(string: "https://example.com/v.m3u8"), tags: [], isNSFW: false
        )
        let repo = VideoRepository(apiClient: DumpertAPIClient(protocolClasses: [EmptyRelatedProtocol.self]))
        repo.settings.autoplayEnabled = true
        let vm = VideoPlayerViewModel(video: video, playlist: [video], repository: repo)
        vm.duration = 100
        vm.currentTime = 80 // 20s left, inside the 30s fetch window

        for _ in 0..<5 {
            vm.checkUpNext()
            try? await Task.sleep(for: .milliseconds(200))
        }

        #expect(EmptyRelatedProtocol.hits == 1, "related endpoint hit \(EmptyRelatedProtocol.hits) times in 5 ticks")
    }
}
