import Foundation

struct Video: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let descriptionText: String
    let date: Date?
    let duration: Int
    let kudosTotal: Int
    let viewsTotal: Int
    let thumbnailURL: URL?
    let streamURL: URL?
    /// Direct MP4 URL (720p/1080p) for frame extraction. Unlike HLS streams,
    /// AVAssetImageGenerator can seek and extract frames from MP4 files.
    let videoFileURL: URL?
    let tags: [String]
    let isNSFW: Bool

    private nonisolated(unsafe) static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f
    }()
    private nonisolated(unsafe) static let iso8601Formatter = ISO8601DateFormatter()

    init(from item: DumpertItem) {
        self.id = item.id
        self.title = item.title
        self.descriptionText = item.description?.strippingHTML() ?? ""

        if let dateString = item.date {
            self.date = Video.dateFormatter.date(from: dateString)
                ?? Video.iso8601Formatter.date(from: dateString)
        } else {
            self.date = nil
        }

        let media = item.media?.first
        self.duration = media?.duration ?? 0

        // Find best stream URL: prefer "stream" (HLS), then "1080p", then "720p"
        let variants = media?.variants ?? []
        let streamVariant = variants.first(where: { $0.version == "stream" })
            ?? variants.first(where: { $0.version == "1080p" })
            ?? variants.first(where: { $0.version == "720p" })
            ?? variants.first
        self.streamURL = streamVariant.flatMap { URL(string: $0.uri) }

        // Direct MP4 for frame extraction: prefer 720p (smaller), then 1080p
        let fileVariant = variants.first(where: { $0.version == "720p" })
            ?? variants.first(where: { $0.version == "1080p" })
        self.videoFileURL = fileVariant.flatMap { URL(string: $0.uri) }

        // Prefer still-large from stills dict, then still, then thumbnail
        let stillLarge = item.stills?["still-large"] ?? item.stills?["still"]
        self.thumbnailURL = stillLarge.flatMap { URL(string: $0) }
            ?? item.still.flatMap { URL(string: $0) }
            ?? item.thumbnail.flatMap { URL(string: $0) }

        self.kudosTotal = item.stats?.kudosTotal ?? 0
        self.viewsTotal = item.stats?.viewsTotal ?? 0
        self.tags = item.tags?
            .components(separatedBy: " ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
        self.isNSFW = item.nsfw ?? false
    }

    init(
        id: String,
        title: String,
        descriptionText: String,
        date: Date?,
        duration: Int,
        kudosTotal: Int,
        viewsTotal: Int = 0,
        thumbnailURL: URL?,
        streamURL: URL?,
        videoFileURL: URL? = nil,
        tags: [String],
        isNSFW: Bool
    ) {
        self.id = id
        self.title = title
        self.descriptionText = descriptionText
        self.date = date
        self.duration = duration
        self.kudosTotal = kudosTotal
        self.viewsTotal = viewsTotal
        self.thumbnailURL = thumbnailURL
        self.streamURL = streamURL
        self.videoFileURL = videoFileURL
        self.tags = tags
        self.isNSFW = isNSFW
    }
}
