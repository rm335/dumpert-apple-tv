import Foundation
import os

/// Lightweight API fetcher for the Top Shelf extension.
/// Fetches hotshiz directly without depending on the main app's API client.
enum TopShelfFetcher: Sendable {
    private static let logger = Logger(subsystem: "nl.dumpert.tvos.topshelf", category: "fetcher")
    private static let hotshizURL = URL(string: "https://post.dumpert.nl/api/v1.0/hotshiz")!

    // MARK: - Minimal API models

    private struct Response: Codable {
        let items: [Item]?
    }

    private struct Item: Codable {
        let id: String
        let title: String
        let description: String?
        let still: String?
        let stills: [String: String]?
        let media: [Media]?
        let stats: Stats?
        let date: String?
        let nsfw: Bool?

        /// Canonical NSFW mapping, matching the app's domain models
        /// (`Video`/`Photo`): an absent flag means safe.
        var isNSFW: Bool { nsfw ?? false }

        var thumbnailURL: URL? {
            let urlString = stills?["still-large"] ?? stills?["still"] ?? still
            return urlString.flatMap { URL(string: $0) }
        }

        var streamURL: URL? {
            let variants = media?.first?.variants ?? []
            let best = variants.first(where: { $0.version == "stream" })
                ?? variants.first(where: { $0.version == "1080p" })
                ?? variants.first(where: { $0.version == "720p" })
                ?? variants.first
            return best.flatMap { URL(string: $0.uri) }
        }

        var kudosTotal: Int? {
            guard let stats else { return nil }
            return (stats.kudos_positive ?? 0) - (stats.kudos_negative ?? 0)
        }

        var videoDuration: Int? {
            media?.first?.duration
        }

        var parsedDate: Date? {
            DumpertDate.parse(date)
        }
    }

    private struct Stats: Codable {
        let kudos_positive: Int?
        let kudos_negative: Int?
    }

    private struct Media: Codable {
        let variants: [Variant]?
        let duration: Int?
    }

    private struct Variant: Codable {
        let uri: String
        let version: String
    }

    // MARK: - Fetch

    static func fetchHotshiz() async -> [TopShelfItem] {
        logger.info("Fetching hotshiz from API: \(hotshizURL.absoluteString)")

        let allowNSFW = TopShelfDataStore.nsfwEnabled

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        var headers: [AnyHashable: Any] = ["Accept": "application/json"]
        // Same policy as DumpertAPIClient: only opt into NSFW when the user
        // allows it.
        if allowNSFW {
            headers["Cookie"] = APIConstants.nsfwOptInCookie
        }
        config.httpAdditionalHeaders = headers
        // Cookies are managed explicitly above; never attach or store cookies
        // implicitly, so a server-stored cookie can't override the preference.
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: config)

        var request = URLRequest(url: hotshizURL)
        request.setValue(APIConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Retry up to 2 times with backoff
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    logger.error("No HTTP response on attempt \(attempt)")
                    continue
                }

                logger.info("API response: HTTP \(http.statusCode) on attempt \(attempt)")

                guard (200...299).contains(http.statusCode) else {
                    if (500...599).contains(http.statusCode) {
                        try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
                        continue
                    }
                    logger.error("API returned \(http.statusCode)")
                    return []
                }

                let decoded = try JSONDecoder().decode(Response.self, from: data)
                // Defense in depth: drop NSFW items client-side too, in case the
                // cookie didn't fully filter them server-side.
                let source = (decoded.items ?? []).filter { allowNSFW || !$0.isNSFW }
                let items = source.prefix(10).map { item in
                    TopShelfItem(
                        id: item.id,
                        title: item.title,
                        thumbnailURL: item.thumbnailURL,
                        streamURL: item.streamURL,
                        description: item.description,
                        kudos: item.kudosTotal,
                        duration: item.videoDuration,
                        date: item.parsedDate,
                        nsfw: item.isNSFW
                    )
                }

                logger.info("Fetched \(items.count) items from API")

                // Cache for next time
                if !items.isEmpty {
                    TopShelfDataStore.save(hotshiz: Array(items))
                }

                return Array(items)
            } catch {
                logger.error("API fetch attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
                }
            }
        }

        logger.error("All API fetch attempts failed")
        return []
    }
}
