import Foundation

@Observable
@MainActor
final class SearchViewModel {
    var searchQuery = "" {
        didSet { debounceSearch() }
    }

    var filter = SearchFilter() {
        didSet { applyFilter() }
    }

    private(set) var results: [MediaItem] = []
    private(set) var filteredResults: [MediaItem] = []
    private(set) var isSearching = false
    private(set) var error: String?
    private(set) var currentPage = 0
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    private(set) var hasSearched = false
    /// Set when a load-more request fails. Surfaced as a toast by the view —
    /// NOT via `error`, whose full-screen branch would replace an on-screen
    /// results grid over a page-2 hiccup. Writable so the view can clear it
    /// after showing the toast.
    var loadMoreError: String?

    private let apiClient: any APIClientProtocol
    private let repository: VideoRepository
    private var searchTask: Task<Void, Never>?

    // In-memory search cache with 5-minute TTL
    private struct CachedResult {
        let items: [MediaItem]
        let timestamp: Date
        var isExpired: Bool { Date().timeIntervalSince(timestamp) > 300 }
    }
    private var searchCache: [String: CachedResult] = [:]

    init(apiClient: any APIClientProtocol, repository: VideoRepository) {
        self.apiClient = apiClient
        self.repository = repository
    }

    private func debounceSearch() {
        searchTask?.cancel()

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            filteredResults = []
            error = nil
            hasSearched = false
            isSearching = false
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.search()
        }
    }

    func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        let cacheKey = query.lowercased()

        // Check cache first
        if let cached = searchCache[cacheKey], !cached.isExpired {
            // Reset currentPage to 0 so subsequent loadMore() fetches page 1
            // rather than picking up where a previous (different or extended)
            // session left off — otherwise pages between 0 and the stale
            // currentPage are skipped entirely.
            currentPage = 0
            results = repository.filteredItems(cached.items)
            filteredResults = filter.apply(to: results)
            hasMore = !cached.items.isEmpty
            hasSearched = true
            isSearching = false
            // A stale error (e.g. from a failed load-more) would otherwise
            // keep the full-screen error state on screen: retry calls this
            // exact path, so without this line "Opnieuw proberen" visibly
            // did nothing until the cache expired.
            error = nil
            return
        }

        isSearching = true
        error = nil
        currentPage = 0
        defer { isSearching = false }

        do {
            let items = try await apiClient.fetchSearch(query: query, page: 0, order: .dateNewest)
            guard !Task.isCancelled else { return }
            searchCache[cacheKey] = CachedResult(items: items, timestamp: Date())
            results = repository.filteredItems(items)
            filteredResults = filter.apply(to: results)
            hasMore = !items.isEmpty
            hasSearched = true
            repository.recordSearch(query)

            // The NSFW/kudos filters can wipe out the entire first page while
            // later pages still hold visible results — without fetching ahead
            // the user hits a dead-end "Geen resultaten" (the load-more
            // trigger lives on result cards, which don't exist yet).
            // ponytail: 3-page cap; raise if real queries still dead-end.
            var page = 0
            while results.isEmpty && hasMore && page < 3 {
                guard !Task.isCancelled else { return }
                page += 1
                let more = try await apiClient.fetchSearch(query: query, page: page, order: .dateNewest)
                guard !Task.isCancelled else { return }
                if more.isEmpty {
                    hasMore = false
                    break
                }
                // Keep the cache the union of fetched pages, deduped, so a
                // cache hit replays the same result set without id clashes.
                let cachedItems = searchCache[cacheKey]?.items ?? items
                let knownIds = Set(cachedItems.map(\.id))
                searchCache[cacheKey] = CachedResult(
                    items: cachedItems + more.filter { !knownIds.contains($0.id) },
                    timestamp: Date()
                )
                let existingIds = Set(results.map(\.id))
                results.append(contentsOf: repository.filteredItems(more).filter { !existingIds.contains($0.id) })
                filteredResults = filter.apply(to: results)
                currentPage = page
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
            results = []
            filteredResults = []
            hasSearched = true
        }
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }
        let nextPage = currentPage + 1

        do {
            let newItems = try await apiClient.fetchSearch(query: query, page: nextPage, order: .dateNewest)
            // The user may have typed a new query (or a cache hit reset the
            // pagination) while this page was in flight — appending would mix
            // the old query's items into the new grid and skip a real page.
            guard !Task.isCancelled,
                  query == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                  nextPage == currentPage + 1
            else { return }
            if newItems.isEmpty {
                hasMore = false
            } else {
                let existingIds = Set(results.map(\.id))
                let unique = repository.filteredItems(newItems).filter { !existingIds.contains($0.id) }
                results.append(contentsOf: unique)
                filteredResults = filter.apply(to: results)
                currentPage = nextPage
            }
            loadMoreError = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            // Not `self.error`: the full-screen error branch renders before
            // the results grid, so a pagination failure would visibly wipe
            // loaded results off screen. Toast it instead; the list stays.
            loadMoreError = error.localizedDescription
        }
    }

    private func applyFilter() {
        filteredResults = filter.apply(to: results)
    }

    func resetFilters() {
        filter = SearchFilter()
    }
}
