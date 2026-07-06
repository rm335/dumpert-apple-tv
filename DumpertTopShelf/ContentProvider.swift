@preconcurrency import TVServices
import os

class ContentProvider: TVTopShelfContentProvider {
    private let logger = Logger(subsystem: "nl.dumpert.tvos.topshelf", category: "content")

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        NSLog("[TopShelf] loadTopShelfContent CALLED")
        logger.notice("=== Top Shelf loadTopShelfContent called ===")
        TopShelfDataStore.diagnose()

        // Try cached data first; if stale, fetch fresh from API
        let hotshiz = TopShelfDataStore.loadHotshiz()

        if !hotshiz.isEmpty && !TopShelfDataStore.isStale {
            logger.notice("Using cached data (\(hotshiz.count) items)")
            return Self.buildCarouselContent(from: hotshiz)
        }

        // Fetch fresh data from API
        logger.notice("Cache is stale or empty — fetching fresh data from API")
        let freshItems = await TopShelfFetcher.fetchHotshiz()

        if !freshItems.isEmpty {
            return Self.buildCarouselContent(from: freshItems)
        } else if !hotshiz.isEmpty {
            logger.notice("API fetch failed — using stale cached data")
            return Self.buildCarouselContent(from: hotshiz)
        } else {
            logger.fault("No items available — Top Shelf will be empty")
            return nil
        }
    }

    // MARK: - Cinematic Carousel Content

    private static func buildCarouselContent(from items: [TopShelfItem]) -> TVTopShelfCarouselContent {
        let carouselItems = items.prefix(10).map(makeCarouselItem)
        NSLog("[TopShelf] Returning carousel content with \(carouselItems.count) items")
        return TVTopShelfCarouselContent(style: .details, items: carouselItems)
    }

    private static func makeCarouselItem(_ item: TopShelfItem) -> TVTopShelfCarouselItem {
        let carouselItem = TVTopShelfCarouselItem(identifier: item.id)

        // Context title shown above the main content
        carouselItem.contextTitle = String(localized: "Trending op Dumpert", comment: "Top Shelf carousel context title")

        // Summary text (description or title)
        if let description = item.description, !description.isEmpty {
            carouselItem.summary = description
        } else {
            carouselItem.summary = item.title
        }

        // Duration
        if let duration = item.duration, duration > 0 {
            carouselItem.duration = TimeInterval(duration)
        }

        // Creation date
        if let date = item.date {
            carouselItem.creationDate = date
        }

        // Named attributes: kudos badge and source
        var attributes: [TVTopShelfNamedAttribute] = []

        if let kudos = item.kudos {
            let formatted = formatKudos(kudos)
            attributes.append(TVTopShelfNamedAttribute(
                name: "Kudos",
                values: [formatted]
            ))
        }

        attributes.append(TVTopShelfNamedAttribute(
            name: String(localized: "Bron", comment: "Top Shelf named attribute: source"),
            values: ["Dumpert"]
        ))

        carouselItem.namedAttributes = attributes

        // Media options badge
        carouselItem.mediaOptions = .videoResolutionHD

        // High-res image
        if let url = item.thumbnailURL {
            carouselItem.setImageURL(url, for: .screenScale1x)
            carouselItem.setImageURL(url, for: .screenScale2x)
        }

        // Stream URL as preview video (plays on focus hover)
        if let streamURL = item.streamURL {
            carouselItem.previewVideoURL = streamURL
        }

        // Deep link actions
        if let deepLinkURL = URL(string: "dumpert://video/\(item.id)") {
            carouselItem.playAction = TVTopShelfAction(url: deepLinkURL)
            carouselItem.displayAction = TVTopShelfAction(url: deepLinkURL)
        }

        return carouselItem
    }

    // MARK: - Formatting Helpers

    private static func formatKudos(_ kudos: Int) -> String {
        if abs(kudos) >= 1000 {
            // Locale-aware separator: "1,2k" for Dutch users, "1.2k" for English.
            return String(format: "%.1fk", locale: .current, Double(kudos) / 1000)
        }
        return "\(kudos)"
    }
}
