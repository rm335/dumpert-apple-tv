import Testing
import Foundation
@testable import Dumpert

/// Answers every request to the stub article with HTTP 500 and counts the hits.
final class Always500Protocol: URLProtocol, @unchecked Sendable {
    static let marker = "retrytest0/stub0000"
    nonisolated(unsafe) static var hits = 0

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.absoluteString.contains(marker) == true
    }
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

@Suite("API client retry", .serialized)
struct APIClientRetryTests {

    /// 3 attempts back off 1s + 2s between them. A 4th sleep after the last
    /// failed attempt only delays the error: total must stay well under 7s.
    @Test("Comments 5xx retry does not sleep after the final attempt")
    func commentsNoSleepAfterFinalAttempt() async {
        URLProtocol.registerClass(Always500Protocol.self)
        defer { URLProtocol.unregisterClass(Always500Protocol.self) }
        Always500Protocol.hits = 0

        let client = DumpertAPIClient(protocolClasses: [Always500Protocol.self])
        let start = ContinuousClock.now
        _ = try? await client.fetchTopComments(for: "retrytest0_stub0000")
        let elapsed = ContinuousClock.now - start

        #expect(Always500Protocol.hits == 3)
        #expect(elapsed < .seconds(5), "took \(elapsed)")
    }
}
