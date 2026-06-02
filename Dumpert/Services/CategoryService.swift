import Foundation

actor CategoryService {
    private let apiClient: DumpertAPIClient
    private let cacheService: CacheService

    init(apiClient: DumpertAPIClient, cacheService: CacheService) {
        self.apiClient = apiClient
        self.cacheService = cacheService
    }

    func fetchItems(
        for category: VideoCategory,
        page: Int = 0,
        order: SortOrder? = .dateNewest,
        curationEntries: [CurationEntry],
        minimumKudos: Int,
        reetenMinimumMinutes: Int = 10
    ) async throws -> [MediaItem] {
        let items: [MediaItem]
        if category.usesLatestEndpoint {
            items = try await apiClient.fetchLatest(page: page)
        } else if category.usesDumpertTVEndpoint {
            items = try await apiClient.fetchDumpertTV(page: page)
        } else {
            items = try await apiClient.fetchSearch(query: category.searchQuery, page: page, order: order)
        }

        // Cache results
        await cacheService.cacheMediaItems(items, for: "\(category.rawValue)_\(page)")

        return applyCurationAndFilter(
            items: items,
            category: category,
            curationEntries: curationEntries,
            minimumKudos: minimumKudos,
            reetenMinimumMinutes: reetenMinimumMinutes
        )
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

        return items.filter { item in
            if removedIds.contains(item.id) { return false }
            if addedIds.contains(item.id) { return true }
            if category == .reeten && minimumDurationSeconds > 0 && item.duration < minimumDurationSeconds {
                return false
            }
            return item.kudosTotal >= minimumKudos
        }
    }
}
