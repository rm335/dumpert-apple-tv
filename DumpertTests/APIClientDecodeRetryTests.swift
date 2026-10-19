import Testing
import Foundation
@testable import Dumpert

/// Answers requests to the stub article with a fixed 200 body and counts the hits.
final class Always200Protocol: URLProtocol, @unchecked Sendable {
    static let marker = "decodetest0/stub0000"
    nonisolated(unsafe) static var hits = 0
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.absoluteString.contains(marker) == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.hits += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("API client decode failures", .serialized)
struct APIClientDecodeRetryTests {

    /// A 200 with an unreadable body is not a transient network fault: retrying
    /// cannot fix it and only delays the error by 1s + 2s of backoff.
    @Test("Comments decode failure is not retried")
    func commentsDecodeFailureNotRetried() async {
        URLProtocol.registerClass(Always200Protocol.self)
        defer { URLProtocol.unregisterClass(Always200Protocol.self) }
        Always200Protocol.hits = 0
        Always200Protocol.body = Data("<html>not json</html>".utf8)

        let client = DumpertAPIClient()
        let start = ContinuousClock.now
        var thrown: Error?
        do { _ = try await client.fetchTopComments(for: "decodetest0_stub0000") } catch { thrown = error }
        let elapsed = ContinuousClock.now - start

        #expect(Always200Protocol.hits == 1, "hits \(Always200Protocol.hits)")
        #expect(elapsed < .seconds(1), "took \(elapsed)")
        guard case .decodingError? = thrown as? APIError else {
            Issue.record("expected APIError.decodingError, got \(String(describing: thrown))")
            return
        }
    }

    /// Same contract for the item feeds: decoding fails once, no retries.
    @Test("Feed decode failure is not retried")
    func feedDecodeFailureNotRetried() async {
        URLProtocol.registerClass(Always200Protocol.self)
        defer { URLProtocol.unregisterClass(Always200Protocol.self) }
        Always200Protocol.hits = 0
        Always200Protocol.body = Data("<html>not json</html>".utf8)

        let client = DumpertAPIClient()
        var thrown: Error?
        do { _ = try await client.fetchItem(id: "decodetest0_stub0000") } catch { thrown = error }

        #expect(Always200Protocol.hits == 1, "hits \(Always200Protocol.hits)")
        guard case .decodingError? = thrown as? APIError else {
            Issue.record("expected APIError.decodingError, got \(String(describing: thrown))")
            return
        }
    }
}
