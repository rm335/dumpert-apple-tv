import Testing
import Foundation
@testable import Dumpert

/// `TopShelfDataStore.isStale` gates the extension's hotshiz carousel, so it must
/// describe the age of the hotshiz list, not of whichever list was saved last.
@Suite("Top Shelf staleness", .serialized)
struct TopShelfStalenessTests {
    private let keys = ["topshelf_hotshiz", "topshelf_topweek", "topshelf_latest", "topshelf_last_updated"]

    private func item(_ id: String) -> TopShelfItem {
        TopShelfItem(id: id, title: id, thumbnailURL: nil, streamURL: nil, nsfw: false)
    }

    @Test("Saving another list does not refresh the staleness clock of an old hotshiz cache")
    func otherListDoesNotFreshenHotshiz() throws {
        let defaults = try #require(UserDefaults(suiteName: TopShelfDataStore.appGroupIdentifier))
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer { for (key, value) in saved { defaults.set(value, forKey: key) } }

        TopShelfDataStore.save(hotshiz: [item("old")])
        defaults.set(Date().addingTimeInterval(-3600), forKey: "topshelf_last_updated")
        #expect(TopShelfDataStore.isStale)

        // Toppers came back empty (save skipped), the other lists saved fine.
        TopShelfDataStore.save(hotshiz: [])
        TopShelfDataStore.save(topWeek: [item("week")])
        TopShelfDataStore.save(latest: [item("new")])

        #expect(TopShelfDataStore.isStale, "hotshiz is still 1 hour old")
    }
}
