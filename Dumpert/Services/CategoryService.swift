import Foundation

actor CategoryService {
    private let apiClient: any APIClientProtocol
    private let cacheService: CacheService

    init(apiClient: any APIClientProtocol, cacheService: CacheService) {
        self.apiClient = apiClient
        self.cacheService = cacheService
    }

    /// One fetched page of a category feed: the curated/filtered `items` to show
    /// plus the `rawIDs` the endpoint actually returned (before curation/kudos
    /// filtering). The caller drives pagination off `rawIDs` so a page that's
    /// entirely filtered out for display still counts as "the server had more",
    /// and a page that only repeats already-seen ids signals "stop".
    struct CategoryPage: Sendable {
        let items: [MediaItem]
        let rawIDs: [String]

        static let empty = CategoryPage(items: [], rawIDs: [])
    }

    func fetchItems(
        for category: VideoCategory,
        page: Int = 0,
        order: SortOrder? = .dateNewest,
        curationEntries: [CurationEntry],
        minimumKudos: Int,
        reetenMinimumMinutes: Int = 10
    ) async throws -> CategoryPage {
        let fetched: [MediaItem]
        switch category.endpoint {
        case .latest:
            fetched = try await apiClient.fetchLatest(page: page)
        case .dumpertTV:
            fetched = try await apiClient.fetchDumpertTV(page: page)
        case .search:
            fetched = try await apiClient.fetchSearch(query: category.searchQuery, page: page, order: order)
        }

        // Cache the raw results (display ordering/filtering is reapplied on load).
        await cacheService.cacheMediaItems(fetched, for: "\(category.rawValue)_\(page)")

        let items = applyCurationAndFilter(
            items: fetched,
            category: category,
            curationEntries: curationEntries,
            minimumKudos: minimumKudos,
            reetenMinimumMinutes: reetenMinimumMinutes
        )
        return CategoryPage(items: items, rawIDs: fetched.map(\.id))
    }

    func loadCachedItems(
        for category: VideoCategory,
        page: Int = 0,
        curationEntries: [CurationEntry],
        minimumKudos: Int,
        reetenMinimumMinutes: Int = 10
    ) async -> [MediaItem] {
        guard let cached = await cacheService.loadCachedMediaItems(for: "\(category.rawValue)_\(page)") else {
            return []
        }
        return applyCurationAndFilter(
            items: cached,
            category: category,
            curationEntries: curationEntries,
            minimumKudos: minimumKudos,
            reetenMinimumMinutes: reetenMinimumMinutes
        )
    }

    private func applyCurationAndFilter(
        items: [MediaItem],
        category: VideoCategory,
        curationEntries: [CurationEntry],
        minimumKudos: Int,
        reetenMinimumMinutes: Int
    ) -> [MediaItem] {
        let categoryEntries = curationEntries.filter { $0.category == category }
        let removedIds = Set(categoryEntries.filter { $0.action == .remove }.map(\.videoId))
        let addedIds = Set(categoryEntries.filter { $0.action == .add }.map(\.videoId))
        let minimumDurationSeconds = reetenMinimumMinutes * 60

        let filtered = items.filter { item in
            if removedIds.contains(item.id) { return false }
            if addedIds.contains(item.id) { return true }
            if category == .reeten && minimumDurationSeconds > 0 && item.duration < minimumDurationSeconds {
                return false
            }
            return item.kudosTotal >= minimumKudos
        }

        // DumpertTV's endpoint returns each page in a date-arbitrary order (pages
        // mix years) with no server-side sort, so order newest-first here in the
        // data layer rather than in the view. Each page is sorted independently and
        // appended by the caller, so the already-loaded set never reorders when a
        // new page arrives. Undated items sink to the bottom; ties break on id so
        // the order is stable and deterministic across re-fetches.
        guard category.endpoint == .dumpertTV else { return filtered }
        return filtered.sorted { lhs, rhs in
            let lDate = lhs.date ?? .distantPast
            let rDate = rhs.date ?? .distantPast
            if lDate != rDate { return lDate > rDate }
            return lhs.id < rhs.id
        }
    }
}
