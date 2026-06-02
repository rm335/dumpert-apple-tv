import Foundation

/// Protocol for the API client, enabling test mocking.
protocol APIClientProtocol: Sendable {
    func fetchHotshiz() async throws -> [MediaItem]
    func fetchTopWeek(date: Date) async throws -> [MediaItem]
    func fetchTopMonth(date: Date) async throws -> [MediaItem]
    func fetchTopDay(date: Date) async throws -> [MediaItem]
    func fetchLatest(page: Int) async throws -> [MediaItem]
    func fetchSearch(query: String, page: Int, order: SortOrder?) async throws -> [MediaItem]
    func fetchClassics(page: Int) async throws -> [MediaItem]
    func fetchRelated(id: String) async throws -> [MediaItem]
    func fetchItem(id: String) async throws -> MediaItem?
    func fetchTopComments(for itemId: String) async throws -> [DumpertComment]
}

extension DumpertAPIClient: @preconcurrency APIClientProtocol {}
