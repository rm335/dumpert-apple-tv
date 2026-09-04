import Foundation

struct CommentsAPIResponse: Codable, Sendable {
    let authors: [CommentAuthor]?
    let comments: [RawComment]?
}

struct CommentAuthor: Codable, Sendable {
    let id: Int
    let username: String
    let banned: Bool?
}

struct RawComment: Codable, Sendable {
    let id: Int
    let content: String
    let kudosCount: Int
    let creationDatetime: String?
    let author: Int
    /// Replies to this comment. The live API nests exactly one level deep
    /// (child comments never carry a `child_comments` key themselves), but the
    /// recursive type costs nothing and survives an API change.
    let childComments: [RawComment]?

    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case kudosCount = "kudos_count"
        case creationDatetime = "creation_datetime"
        case author
        case childComments = "child_comments"
    }
}

struct DumpertComment: Sendable, Identifiable {
    let id: Int
    let authorUsername: String
    let displayContent: String
    let kudosCount: Int
    let creationDatetime: String?
    let replies: [DumpertComment]

    var creationDate: Date? {
        DumpertDate.parse(creationDatetime)
    }
}

extension DumpertComment {
    /// Maps a raw comments payload to domain comments: resolves usernames,
    /// drops comments (and replies) from banned authors, keeps replies nested,
    /// and sorts top-level comments by kudos descending. Replies keep API
    /// (chronological) order.
    static func comments(from response: CommentsAPIResponse) -> [DumpertComment] {
        let authors = response.authors ?? []
        // uniquingKeysWith: the API should not repeat author ids, but
        // Dictionary(uniqueKeysWithValues:) would trap on a duplicate.
        let authorMap = Dictionary(authors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let bannedAuthorIds = Set(authors.filter { $0.banned == true }.map(\.id))

        func convert(_ raw: RawComment) -> DumpertComment? {
            guard !bannedAuthorIds.contains(raw.author) else { return nil }
            return DumpertComment(
                id: raw.id,
                authorUsername: authorMap[raw.author]?.username ?? "Onbekend",
                displayContent: raw.content,
                kudosCount: raw.kudosCount,
                creationDatetime: raw.creationDatetime,
                replies: (raw.childComments ?? []).compactMap(convert)
            )
        }

        return (response.comments ?? [])
            .compactMap(convert)
            .sorted { $0.kudosCount > $1.kudosCount }
    }
}
