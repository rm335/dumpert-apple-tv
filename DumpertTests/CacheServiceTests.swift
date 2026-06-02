import Testing
import Foundation
@testable import Dumpert

@Suite("Cache Service Tests")
struct CacheServiceTests {

    /// Returns a fresh, isolated cache so parallel suites can't race on the
    /// shared Caches/DumpertCache directory used in production.
    private func makeIsolatedCache() -> CacheService {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DumpertTests-\(UUID().uuidString)", isDirectory: true)
        return CacheService(cacheDirectory: dir)
    }

    @Test("Watch progress round-trip")
    func watchProgressRoundTrip() async {
        let cache = makeIsolatedCache()
        let progress: [String: WatchProgress] = [
            "v1": WatchProgress(videoId: "v1", watchedSeconds: 30, totalSeconds: 100),
            "v2": WatchProgress(videoId: "v2", watchedSeconds: 90, totalSeconds: 100),
        ]

        await cache.saveWatchProgress(progress)
        let loaded = await cache.loadWatchProgress()

        #expect(loaded["v1"]?.watchedSeconds == 30)
        #expect(loaded["v2"]?.watchedSeconds == 90)
        #expect(loaded["v2"]?.isCompleted == true)
    }

    @Test("Settings round-trip")
    func settingsRoundTrip() async {
        let cache = makeIsolatedCache()
        let settings = UserSettingsSnapshot(
            minimumKudos: 50,
            autoplayEnabled: false,
            hideWatched: true,
            thumbnailPreviewEnabled: false
        )

        await cache.saveSettings(settings)
        let loaded = await cache.loadSettings()

        #expect(loaded.minimumKudos == 50)
        #expect(loaded.autoplayEnabled == false)
    }

    @Test("Curation entries round-trip")
    func curationRoundTrip() async {
        let cache = makeIsolatedCache()
        let entries = [
            CurationEntry(videoId: "v1", category: .reeten, action: .add),
            CurationEntry(videoId: "v2", category: .dashcam, action: .remove),
        ]

        await cache.saveCurationEntries(entries)
        let loaded = await cache.loadCurationEntries()

        #expect(loaded.count == 2)
        #expect(loaded[0].videoId == "v1")
        #expect(loaded[1].action == .remove)
    }

    @Test("Search history round-trip")
    func searchHistoryRoundTrip() async {
        let cache = makeIsolatedCache()
        let entries = [
            SearchHistoryEntry(query: "dashcam"),
            SearchHistoryEntry(query: "fail"),
        ]

        await cache.saveSearchHistory(entries)
        let loaded = await cache.loadSearchHistory()

        #expect(loaded.count == 2)
        #expect(loaded[0].query == "dashcam")
    }

    @Test("Media item cache round-trip preserves viewsTotal")
    func mediaItemViewsRoundTrip() async {
        let cache = makeIsolatedCache()
        let video = Video(
            id: "v1", title: "Test", descriptionText: "", date: nil,
            duration: 42, kudosTotal: 7, viewsTotal: 63_759,
            thumbnailURL: nil, streamURL: nil, tags: [], isNSFW: false
        )

        await cache.cacheMediaItems([.video(video)], for: "k1")
        let loaded = await cache.loadCachedMediaItems(for: "k1")

        #expect(loaded?.count == 1)
        #expect(loaded?.first?.viewsTotal == 63_759)
        #expect(loaded?.first?.kudosTotal == 7)
    }

    @Test("Legacy cached media without viewsTotal decodes as zero")
    func legacyCacheBackwardCompatible() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DumpertTests-\(UUID().uuidString)", isDirectory: true)
        let cache = CacheService(cacheDirectory: dir)

        // On-disk format that predates the viewsTotal field.
        let legacyJSON = """
        [{"id":"v1","title":"Oud","descriptionText":"","duration":42,"kudosTotal":7,"tags":[],"isNSFW":false,"mediaType":"video"}]
        """
        try Data(legacyJSON.utf8).write(to: dir.appendingPathComponent("videos_legacy.json"))

        let loaded = await cache.loadCachedMediaItems(for: "legacy")

        #expect(loaded?.count == 1)
        #expect(loaded?.first?.kudosTotal == 7)
        #expect(loaded?.first?.viewsTotal == 0)
    }
}
