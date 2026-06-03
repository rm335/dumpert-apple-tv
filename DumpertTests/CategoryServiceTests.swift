import Testing
import Foundation
@testable import Dumpert

/// Tests for CategoryService: that each channel is routed to the correct
/// endpoint, that the DumpertTV feed is ordered newest-first in the data layer,
/// and that a page reports the raw ids it fetched (so pagination can keep going
/// even when everything was filtered out for display).
@Suite("Category Service Tests")
struct CategoryServiceTests {

    // MARK: - Helpers

    /// Records which endpoint method was hit and returns canned, per-endpoint
    /// items so routing can be asserted by which response comes back.
    private final class RoutingMockAPIClient: APIClientProtocol, @unchecked Sendable {
        var latestItems: [MediaItem] = []
        var searchItems: [MediaItem] = []
        var dumpertTVItems: [MediaItem] = []
        private(set) var calledMethods: [String] = []
        private(set) var lastSearchQuery: String?
        private(set) var lastDumpertTVPage: Int?

        func fetchHotshiz() async throws -> [MediaItem] { [] }
        func fetchTopWeek(date: Date) async throws -> [MediaItem] { [] }
        func fetchTopMonth(date: Date) async throws -> [MediaItem] { [] }
        func fetchTopDay(date: Date) async throws -> [MediaItem] { [] }
        func fetchLatest(page: Int) async throws -> [MediaItem] {
            calledMethods.append("latest"); return latestItems
        }
        func fetchSearch(query: String, page: Int, order: Dumpert.SortOrder?) async throws -> [MediaItem] {
            calledMethods.append("search"); lastSearchQuery = query; return searchItems
        }
        func fetchClassics(page: Int) async throws -> [MediaItem] { [] }
        func fetchDumpertTV(page: Int) async throws -> [MediaItem] {
            calledMethods.append("dumpertTV"); lastDumpertTVPage = page; return dumpertTVItems
        }
        func fetchRelated(id: String) async throws -> [MediaItem] { [] }
        func fetchItem(id: String) async throws -> MediaItem? { nil }
        func fetchTopComments(for itemId: String) async throws -> [DumpertComment] { [] }
    }

    private func makeIsolatedCache() -> CacheService {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DumpertTests-\(UUID().uuidString)", isDirectory: true)
        return CacheService(cacheDirectory: dir)
    }

    private func makeVideo(id: String, date: Date?, kudos: Int = 100) -> MediaItem {
        .video(Video(
            id: id,
            title: id,
            descriptionText: "",
            date: date,
            duration: 0,
            kudosTotal: kudos,
            thumbnailURL: nil,
            streamURL: nil,
            tags: [],
            isNSFW: false
        ))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return Calendar.current.date(from: c)!
    }

    // MARK: - Routing

    @Test("Nieuw routes to the latest endpoint")
    func nieuwRoutesToLatest() async throws {
        let mock = RoutingMockAPIClient()
        mock.latestItems = [makeVideo(id: "latest-1", date: nil)]
        let service = CategoryService(apiClient: mock, cacheService: makeIsolatedCache())

        let page = try await service.fetchItems(
            for: .nieuwBinnen, curationEntries: [], minimumKudos: 0
        )

        #expect(page.items.map(\.id) == ["latest-1"])
        #expect(mock.calledMethods == ["latest"])
    }

    @Test("DumpertTV routes to its own endpoint, never search")
    func dumpertTVRoutesToOwnEndpoint() async throws {
        let mock = RoutingMockAPIClient()
        mock.dumpertTVItems = [makeVideo(id: "tv-1", date: nil)]
        mock.searchItems = [makeVideo(id: "search-1", date: nil)]
        let service = CategoryService(apiClient: mock, cacheService: makeIsolatedCache())

        let page = try await service.fetchItems(
            for: .dumperttv, page: 3, curationEntries: [], minimumKudos: 0
        )

        #expect(page.items.map(\.id) == ["tv-1"])
        #expect(mock.calledMethods == ["dumpertTV"])
        #expect(!mock.calledMethods.contains("search"))
        #expect(mock.lastDumpertTVPage == 3)
    }

    @Test("Genre channels route to search with the right query")
    func genreRoutesToSearch() async throws {
        let mock = RoutingMockAPIClient()
        mock.searchItems = [makeVideo(id: "search-1", date: nil)]
        let service = CategoryService(apiClient: mock, cacheService: makeIsolatedCache())

        // reetenMinimumMinutes: 0 so the duration filter doesn't drop the 0-duration fixture.
        let page = try await service.fetchItems(
            for: .reeten, curationEntries: [], minimumKudos: 0, reetenMinimumMinutes: 0
        )

        #expect(page.items.map(\.id) == ["search-1"])
        #expect(mock.calledMethods == ["search"])
        #expect(mock.lastSearchQuery == "dumpertreeten")
    }

    // MARK: - DumpertTV ordering

    @Test("DumpertTV pages are sorted newest-first with undated items last")
    func dumpertTVSortsNewestFirst() async throws {
        let mock = RoutingMockAPIClient()
        // Deliberately scrambled, with a nil date and a tie on 2025-01-01.
        mock.dumpertTVItems = [
            makeVideo(id: "v-b", date: date(2019, 6, 1)),
            makeVideo(id: "v-d", date: nil),
            makeVideo(id: "v-a", date: date(2025, 1, 1)),
            makeVideo(id: "v-c", date: date(2023, 3, 3)),
            makeVideo(id: "v-e", date: date(2025, 1, 1)),
        ]
        let service = CategoryService(apiClient: mock, cacheService: makeIsolatedCache())

        let page = try await service.fetchItems(
            for: .dumperttv, curationEntries: [], minimumKudos: 0
        )

        // Newest first; the 2025 tie breaks on id (ascending) for a stable order;
        // the undated item sinks to the bottom.
        #expect(page.items.map(\.id) == ["v-a", "v-e", "v-c", "v-b", "v-d"])
    }

    @Test("Non-DumpertTV channels preserve server order")
    func searchPreservesServerOrder() async throws {
        let mock = RoutingMockAPIClient()
        mock.searchItems = [
            makeVideo(id: "s-old", date: date(2019, 1, 1)),
            makeVideo(id: "s-new", date: date(2025, 1, 1)),
        ]
        let service = CategoryService(apiClient: mock, cacheService: makeIsolatedCache())

        let page = try await service.fetchItems(
            for: .vrijmico, curationEntries: [], minimumKudos: 0
        )

        #expect(page.items.map(\.id) == ["s-old", "s-new"])
    }

    // MARK: - Pagination inputs

    @Test("rawIDs report every fetched item even when all are filtered out")
    func rawIDsSurviveFiltering() async throws {
        let mock = RoutingMockAPIClient()
        mock.dumpertTVItems = [
            makeVideo(id: "low-1", date: date(2025, 1, 1), kudos: 0),
            makeVideo(id: "low-2", date: date(2024, 1, 1), kudos: 0),
        ]
        let service = CategoryService(apiClient: mock, cacheService: makeIsolatedCache())

        // A high kudos threshold filters out everything for display...
        let page = try await service.fetchItems(
            for: .dumperttv, curationEntries: [], minimumKudos: 1000
        )

        #expect(page.items.isEmpty)
        // ...but rawIDs still reflect what the server returned, so pagination can
        // keep advancing to later pages that may qualify.
        #expect(Set(page.rawIDs) == ["low-1", "low-2"])
    }

    // MARK: - Category capability flags

    @Test("Category endpoint / sorting / curation flags are correct for every case")
    func categoryFlags() {
        let expected: [VideoCategory: (CategoryEndpoint, sorting: Bool, curation: Bool)] = [
            .nieuwBinnen: (.latest, false, false),
            .reeten: (.search, true, true),
            .vrijmico: (.search, true, true),
            .dashcam: (.search, true, true),
            .dumperttv: (.dumpertTV, false, false),
        ]
        // Guards against a new case slipping through untested.
        #expect(Set(expected.keys) == Set(VideoCategory.allCases))
        for category in VideoCategory.allCases {
            let e = expected[category]!
            #expect(category.endpoint == e.0)
            #expect(category.supportsSorting == e.sorting)
            #expect(category.supportsCuration == e.curation)
        }
    }
}
