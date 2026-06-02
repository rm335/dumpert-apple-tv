import Foundation

enum MediaItem: Identifiable, Hashable, Sendable {
    case video(Video)
    case photo(Photo)

    var id: String {
        switch self {
        case .video(let v): v.id
        case .photo(let p): p.id
        }
    }

    var title: String {
        switch self {
        case .video(let v): v.title
        case .photo(let p): p.title
        }
    }

    var descriptionText: String {
        switch self {
        case .video(let v): v.descriptionText
        case .photo(let p): p.descriptionText
        }
    }

    var date: Date? {
        switch self {
        case .video(let v): v.date
        case .photo(let p): p.date
        }
    }

    var kudosTotal: Int {
        switch self {
        case .video(let v): v.kudosTotal
        case .photo(let p): p.kudosTotal
        }
    }

    var viewsTotal: Int {
        switch self {
        case .video(let v): v.viewsTotal
        case .photo(let p): p.viewsTotal
        }
    }

    var thumbnailURL: URL? {
        switch self {
        case .video(let v): v.thumbnailURL
        case .photo(let p): p.thumbnailURL
        }
    }

    var tags: [String] {
        switch self {
        case .video(let v): v.tags
        case .photo(let p): p.tags
        }
    }

    var isNSFW: Bool {
        switch self {
        case .video(let v): v.isNSFW
        case .photo(let p): p.isNSFW
        }
    }

    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }

    var isPhoto: Bool {
        if case .photo = self { return true }
        return false
    }

    var duration: Int {
        switch self {
        case .video(let v): v.duration
        case .photo: 0
        }
    }

    var streamURL: URL? {
        switch self {
        case .video(let v): v.streamURL
        case .photo: nil
        }
    }

    init(from item: DumpertItem) {
        if item.mediaType?.uppercased() == "FOTO" {
            self = .photo(Photo(from: item))
        } else {
            self = .video(Video(from: item))
        }
    }
}
