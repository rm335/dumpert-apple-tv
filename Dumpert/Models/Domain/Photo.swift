import Foundation

struct Photo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let descriptionText: String
    let date: Date?
    let kudosTotal: Int
    let viewsTotal: Int
    let thumbnailURL: URL?
    let imageURL: URL?
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
            self.date = Photo.dateFormatter.date(from: dateString)
                ?? Photo.iso8601Formatter.date(from: dateString)
        } else {
            self.date = nil
        }

        // Find image URL from variants: prefer "foto" version
        let media = item.media?.first
        let variants = media?.variants ?? []
        let imageVariant = variants.first(where: { $0.version == "foto" })
            ?? variants.first
        self.imageURL = imageVariant.flatMap { URL(string: $0.uri) }

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
        kudosTotal: Int,
        viewsTotal: Int = 0,
        thumbnailURL: URL?,
        imageURL: URL?,
        tags: [String],
        isNSFW: Bool
    ) {
        self.id = id
        self.title = title
        self.descriptionText = descriptionText
        self.date = date
        self.kudosTotal = kudosTotal
        self.viewsTotal = viewsTotal
        self.thumbnailURL = thumbnailURL
        self.imageURL = imageURL
        self.tags = tags
        self.isNSFW = isNSFW
    }
}
