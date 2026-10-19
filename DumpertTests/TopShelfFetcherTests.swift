import Testing
import Foundation
@testable import Dumpert

private class BundleToken {}

@Suite("Top Shelf Fetcher Tests")
struct TopShelfFetcherTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: BundleToken.self).url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    @Test("Top Shelf kudos match the app's kudos for the same live API items")
    func kudosMatchApp() throws {
        let data = try fixture("hotshiz")
        let shelf = try #require(JSONDecoder().decode(TopShelfFetcher.Response.self, from: data).items)
        let app = try #require(JSONDecoder().decode(DumpertAPIResponse.self, from: data).items)

        #expect(!shelf.isEmpty)
        #expect(shelf.map(\.kudosTotal) == app.map { $0.stats?.kudosTotal })
    }
}
