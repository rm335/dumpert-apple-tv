import Testing
import Foundation
@testable import Dumpert

/// Regression tests for SearchViewModel.
///
/// Bug: `isSearching` could get stuck at `true` whenever the in-flight task
/// was cancelled (via CancellationError, URLError(.cancelled), or by clearing
/// the query). The view then kept displaying a skeleton/loading state
/// indefinitely, even though no work was running.
@Suite("Search View Model Tests")
@MainActor
struct SearchViewModelTests {

    // MARK: - Mock API

    private final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
        enum Response {
            case items([MediaItem])
            case error(Error)
            case cancellation       // simulates URLError(.cancelled) — common path
            case swiftCancellation  // simulates CancellationError — rare path
            case slow(seconds: Double, items: [MediaItem])
        }

        var searchResponse: Response = .items([])

        func fetchHotshiz() async throws -> [MediaItem] { [] }
        func fetchTopWeek(date: Date) async throws -> [MediaItem] { [] }
        func fetchTopMonth(date: Date) async throws -> [MediaItem] { [] }
        func fetchTopDay(date: Date) async throws -> [MediaItem] { [] }
        func fetchLatest(page: Int) async throws -> [MediaItem] { [] }
        func fetchClassics(page: Int) async throws -> [MediaItem] { [] }
        func fetchDumpertTV(page: Int) async throws -> [MediaItem] { [] }
        func fetchRelated(id: String) async throws -> [MediaItem] { [] }
        func fetchItem(id: String) async throws -> MediaItem? { nil }
        func fetchTopComments(for itemId: String) async throws -> [DumpertComment] { [] }

        func fetchSearch(query: String, page: Int, order: Dumpert.SortOrder?) async throws -> [MediaItem] {
            switch searchResponse {
            case .items(let items): return items
            case .error(let error): throw error
            case .cancellation: throw URLError(.cancelled)
            case .swiftCancellation: throw CancellationError()
            case .slow(let seconds, let items):
                try await Task.sleep(for: .seconds(seconds))
                return items
            }
        }
    }

    private func makeViewModel(mock: MockAPIClient) -> SearchViewModel {
        SearchViewModel(apiClient: mock, repository: VideoRepository())
    }

    private func videoItem(_ id: String) -> MediaItem {
        .video(Video(
            id: id,
            title: id,
            descriptionText: "",
            date: nil,
            duration: 60,
            kudosTotal: 1000,
            thumbnailURL: nil,
            streamURL: nil,
            tags: [],
            isNSFW: false
        ))
    }

    // MARK: - isSearching lifecycle

    @Test("isSearching is reset to false after a successful search")
    func isSearchingResetAfterSuccess() async {
        let mock = MockAPIClient()
        mock.searchResponse = .items([videoItem("v1"), videoItem("v2")])
        let vm = makeViewModel(mock: mock)
        vm.searchQuery = "test"

        await vm.search()

        #expect(vm.isSearching == false)
        #expect(vm.hasSearched == true)
        #expect(vm.results.count == 2)
    }

    @Test("isSearching is reset to false when the network call errors out")
    func isSearchingResetAfterError() async {
        struct TestError: Error {}
        let mock = MockAPIClient()
        mock.searchResponse = .error(TestError())
        let vm = makeViewModel(mock: mock)
        vm.searchQuery = "test"

        await vm.search()

        #expect(vm.isSearching == false)
        #expect(vm.error != nil)
    }

    @Test("isSearching is reset to false when URLError(.cancelled) is thrown")
    func isSearchingResetAfterURLCancellation() async {
        // URLSession throws URLError(.cancelled), NOT CancellationError.
        // The original code path swallowed this without resetting isSearching.
        let mock = MockAPIClient()
        mock.searchResponse = .cancellation
        let vm = makeViewModel(mock: mock)
        vm.searchQuery = "test"

        await vm.search()

        #expect(vm.isSearching == false)
    }

    @Test("isSearching is reset to false when CancellationError is thrown")
    func isSearchingResetAfterSwiftCancellation() async {
        let mock = MockAPIClient()
        mock.searchResponse = .swiftCancellation
        let vm = makeViewModel(mock: mock)
        vm.searchQuery = "test"

        await vm.search()

        #expect(vm.isSearching == false)
    }

    @Test("Clearing the query while a search is pending resets isSearching")
    func clearingQueryResetsIsSearching() async {
        let mock = MockAPIClient()
        mock.searchResponse = .slow(seconds: 1.0, items: [])
        let vm = makeViewModel(mock: mock)

        // Kick off a real search to flip isSearching on, then cancel it
        // by setting an empty query via the public binding.
        let task = Task { await vm.search() }
        vm.searchQuery = "test"
        // Trigger debounceSearch with an empty query
        vm.searchQuery = ""

        _ = await task.value
        #expect(vm.isSearching == false)
    }

    // MARK: - isLoadingMore lifecycle (loadMore pagination)

    @Test("isLoadingMore is reset to false after a successful loadMore")
    func isLoadingMoreResetAfterSuccess() async {
        let mock = MockAPIClient()
        mock.searchResponse = .items([videoItem("v1")])
        let vm = makeViewModel(mock: mock)
        vm.searchQuery = "test"
        await vm.search()
        #expect(vm.hasMore == true)

        mock.searchResponse = .items([videoItem("v2")])
        await vm.loadMore()

        #expect(vm.isLoadingMore == false)
        #expect(vm.results.count == 2)
    }

    @Test("isLoadingMore is reset to false when CancellationError is thrown during loadMore")
    func isLoadingMoreResetAfterSwiftCancellation() async {
        // Regression: loadMore() used to `return` on CancellationError without
        // resetting isLoadingMore, which permanently disabled pagination
        // because the guard `guard !isLoadingMore` at the top blocked all
        // subsequent calls.
        let mock = MockAPIClient()
        mock.searchResponse = .items([videoItem("v1")])
        let vm = makeViewModel(mock: mock)
        vm.searchQuery = "test"
        await vm.search()

        mock.searchResponse = .swiftCancellation
        await vm.loadMore()

        #expect(vm.isLoadingMore == false)
    }

    @Test("isLoadingMore is reset to false when URLError(.cancelled) is thrown during loadMore")
    func isLoadingMoreResetAfterURLCancellation() async {
        let mock = MockAPIClient()
        mock.searchResponse = .items([videoItem("v1")])
        let vm = makeViewModel(mock: mock)
        vm.searchQuery = "test"
        await vm.search()

        mock.searchResponse = .cancellation
        await vm.loadMore()

        #expect(vm.isLoadingMore == false)
    }

    @Test("loadMore can be invoked again after a cancelled loadMore")
    func loadMoreReusableAfterCancellation() async {
        // The real-world impact of the bug: after a single cancelled loadMore,
        // the user could never load any more pages because isLoadingMore
        // stayed true forever.
        let mock = MockAPIClient()
        mock.searchResponse = .items([videoItem("v1")])
        let vm = makeViewModel(mock: mock)
        vm.searchQuery = "test"
        await vm.search()

        mock.searchResponse = .swiftCancellation
        await vm.loadMore()
        #expect(vm.results.count == 1)

        mock.searchResponse = .items([videoItem("v2")])
        await vm.loadMore()
        #expect(vm.isLoadingMore == false)
        #expect(vm.results.count == 2)
    }

    @Test("isLoadingMore is reset to false when network errors out during loadMore")
    func isLoadingMoreResetAfterError() async {
        struct TestError: Error {}
        let mock = MockAPIClient()
        mock.searchResponse = .items([videoItem("v1")])
        let vm = makeViewModel(mock: mock)
        vm.searchQuery = "test"
        await vm.search()

        mock.searchResponse = .error(TestError())
        await vm.loadMore()

        #expect(vm.isLoadingMore == false)
        #expect(vm.error != nil)
    }

    @Test("Cache hit returns without leaving isSearching stuck")
    func cacheHitResetsIsSearching() async {
        let mock = MockAPIClient()
        mock.searchResponse = .items([videoItem("v1")])
        let vm = makeViewModel(mock: mock)
        vm.searchQuery = "test"

        // First search populates the cache
        await vm.search()
        #expect(vm.isSearching == false)
        #expect(vm.results.count == 1)

        // Second search must hit cache and still leave isSearching false
        mock.searchResponse = .error(URLError(.notConnectedToInternet))
        await vm.search()
        #expect(vm.isSearching == false)
        #expect(vm.results.count == 1)  // cache hit, not an error
        #expect(vm.error == nil)
    }

    @Test("Cache hit resets currentPage so loadMore restarts pagination at page 1")
    func cacheHitResetsPaginationCursor() async {
        // Regression: cache-hit path used to leave `currentPage` at whatever
        // value the previous session reached. After re-issuing a cached query,
        // the next loadMore() would skip every page between 0 and the stale
        // cursor — leaving visible gaps in the results.
        let mock = MockAPIClient()
        mock.searchResponse = .items([videoItem("v1")])
        let vm = makeViewModel(mock: mock)
        vm.searchQuery = "test"

        await vm.search()
        #expect(vm.currentPage == 0)

        // Walk pagination forward two pages to push currentPage to 2.
        mock.searchResponse = .items([videoItem("v2")])
        await vm.loadMore()
        mock.searchResponse = .items([videoItem("v3")])
        await vm.loadMore()
        #expect(vm.currentPage == 2)

        // Re-issue the same query. Cache hit must reset currentPage to 0 so
        // the next loadMore() asks the API for page 1, not page 3.
        mock.searchResponse = .error(URLError(.notConnectedToInternet))
        await vm.search()
        #expect(vm.currentPage == 0)
        #expect(vm.results.count == 1) // page 0 from cache only

        // Confirm the cursor advanced from 0 → 1 on the next loadMore.
        mock.searchResponse = .items([videoItem("v_page1")])
        await vm.loadMore()
        #expect(vm.currentPage == 1)
    }
}
