import Foundation

struct TopShelfItem: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let thumbnailURL: URL?
    let streamURL: URL?

    // Rich metadata for cinematic Top Shelf
    var description: String?
    var kudos: Int?
    var duration: Int?
    var date: Date?

    /// Whether the API marked this item NSFW. `nil` only for items cached
    /// before this field shipped; readers treat those as unsafe when NSFW
    /// content is hidden.
    var nsfw: Bool?

    init(
        id: String,
        title: String,
        thumbnailURL: URL?,
        streamURL: URL?,
        description: String? = nil,
        kudos: Int? = nil,
        duration: Int? = nil,
        date: Date? = nil,
        nsfw: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.streamURL = streamURL
        self.description = description
        self.kudos = kudos
        self.duration = duration
        self.date = date
        self.nsfw = nsfw
    }
}
