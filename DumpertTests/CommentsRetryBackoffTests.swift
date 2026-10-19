import Testing
import Foundation
@testable import Dumpert

/// Answers every comments request with HTTP 500 and counts the hits.
final class CommentsAlways500Protocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var hits = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.hits += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Comments retry backoff", .serialized)
struct CommentsRetryBackoffTests {

    /// 3 attempts back off 1s + 2s between them. A third sleep (4s) after the
    /// last failed attempt only delays the "laden mislukt" state.
    @Test("fetchTopComments does not sleep after the final failed attempt")
    func noSleepAfterFinalAttempt() async {
        CommentsAlways500Protocol.hits = 0
        let client = DumpertAPIClient(protocolClasses: [CommentsAlways500Protocol.self])

        let start = ContinuousClock.now
        _ = try? await client.fetchTopComments(for: "100000001_aaaaaaaa")
        let elapsed = ContinuousClock.now - start

        #expect(CommentsAlways500Protocol.hits == 3)
        #expect(elapsed < .seconds(5), "took \(elapsed)")
    }
}
