import Foundation
import os

actor DumpertAPIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private var etags: [URL: String] = [:]
    private var cachedResponses: [URL: Data] = [:]
    private let maxCachedResponses = 50
    private var nsfwEnabled: Bool = true

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = [
            "Accept": "application/json"
        ]
        // The NSFW opt-in cookie is managed explicitly per request; never
        // attach or store cookies implicitly, so a server-stored cookie can't
        // silently override the user's preference.
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    func setNSFWEnabled(_ enabled: Bool) {
        nsfwEnabled = enabled
    }

    private func fetch(endpoint: APIEndpoint) async throws -> DumpertAPIResponse {
        let url = endpoint.url
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConstants.userAgent, forHTTPHeaderField: "User-Agent")
        if nsfwEnabled {
            request.setValue(APIConstants.nsfwOptInCookie, forHTTPHeaderField: "Cookie")
        }

        // Conditional request with ETag
        if let etag = etags[url] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        // Handle 304 Not Modified
        if httpResponse.statusCode == 304, let cached = cachedResponses[url] {
            return try decoder.decode(DumpertAPIResponse.self, from: cached)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        // Store ETag and cache response (capped to prevent unbounded growth)
        if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
            if cachedResponses.count >= maxCachedResponses {
                // Evict oldest entry (first key)
                if let oldest = etags.keys.first(where: { $0 != url }) {
                    etags.removeValue(forKey: oldest)
                    cachedResponses.removeValue(forKey: oldest)
                }
            }
            etags[url] = etag
            cachedResponses[url] = data
        }

        do {
            return try decoder.decode(DumpertAPIResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func fetchWithRetry(endpoint: APIEndpoint, maxRetries: Int = 3) async throws -> DumpertAPIResponse {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                return try await fetch(endpoint: endpoint)
            } catch let error as APIError {
                // Only retry on 5xx server errors
                if case .httpError(let statusCode) = error, (500...599).contains(statusCode) {
                    lastError = error
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw error
            } catch {
                // Retry on network errors
                lastError = error
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
            }
        }
        throw lastError ?? APIError.noData
    }

    private func fetchMediaItems(endpoint: APIEndpoint) async throws -> [MediaItem] {
        let response = try await fetchWithRetry(endpoint: endpoint)
        return (response.items ?? []).map { MediaItem(from: $0) }
    }

    // MARK: - Public API

    func fetchHotshiz() async throws -> [MediaItem] {
        try await fetchMediaItems(endpoint: .hotshiz)
    }

    func fetchTopWeek(date: Date = Date()) async throws -> [MediaItem] {
        try await fetchMediaItems(endpoint: .topWeek(date: date))
    }

    func fetchTopMonth(date: Date = Date()) async throws -> [MediaItem] {
        try await fetchMediaItems(endpoint: .topMonth(date: date))
    }

    func fetchTopDay(date: Date = Date()) async throws -> [MediaItem] {
        try await fetchMediaItems(endpoint: .topDay(date: date))
    }

    func fetchLatest(page: Int = 0) async throws -> [MediaItem] {
        try await fetchMediaItems(endpoint: .latest(page: page))
    }

    func fetchDumpertTV(page: Int = 0) async throws -> [MediaItem] {
        try await fetchMediaItems(endpoint: .dumpertTV(page: page))
    }

    func fetchSearch(query: String, page: Int = 0, order: SortOrder? = .dateNewest) async throws -> [MediaItem] {
        try await fetchMediaItems(endpoint: .search(query: query, page: page, order: order))
    }

    func fetchClassics(page: Int = 0) async throws -> [MediaItem] {
        try await fetchMediaItems(endpoint: .classics(page: page))
    }

    func fetchRelated(id: String) async throws -> [MediaItem] {
        try await fetchMediaItems(endpoint: .related(id: id))
    }

    func fetchItem(id: String) async throws -> MediaItem? {
        let response = try await fetchWithRetry(endpoint: .info(id: id))
        return response.items?.first.map { MediaItem(from: $0) }
    }

    // MARK: - Comments API

    private static let commentsBaseURL = "https://comment.dumpert.nl/api/v1.0"

    func fetchTopComments(for itemId: String) async throws -> [DumpertComment] {
        // Convert underscore ID (100146773_1e4d8897) to slash format (100146773/1e4d8897)
        let slashId = itemId.replacingOccurrences(of: "_", with: "/")
        guard let url = URL(string: "\(Self.commentsBaseURL)/articles/\(slashId)/comments") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConstants.userAgent, forHTTPHeaderField: "User-Agent")

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if (500...599).contains(statusCode) {
                        lastError = APIError.httpError(statusCode: statusCode)
                        let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                        try await Task.sleep(nanoseconds: delay)
                        continue
                    }
                    throw APIError.httpError(statusCode: statusCode)
                }

                let apiResponse = try decoder.decode(CommentsAPIResponse.self, from: data)
                let rawComments = apiResponse.comments ?? []
                let authors = apiResponse.authors ?? []

                // Build author lookup by ID
                let authorMap = Dictionary(uniqueKeysWithValues: authors.map { ($0.id, $0) })
                let bannedAuthorIds = Set(authors.filter { $0.banned == true }.map(\.id))

                // Map raw comments to DumpertComment, filtering banned authors
                return rawComments
                    .filter { !bannedAuthorIds.contains($0.author) }
                    .map { raw in
                        DumpertComment(
                            id: raw.id,
                            authorUsername: authorMap[raw.author]?.username ?? "Onbekend",
                            displayContent: raw.content,
                            kudosCount: raw.kudosCount,
                            creationDatetime: raw.creationDatetime
                        )
                    }
                    .sorted { $0.kudosCount > $1.kudosCount }
            } catch let error as APIError {
                throw error
            } catch {
                // Retry on network errors (URLError, connection failures, etc.)
                lastError = error
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
            }
        }
        throw lastError ?? APIError.noData
    }
}
