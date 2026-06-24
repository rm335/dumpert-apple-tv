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

    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case kudosCount = "kudos_count"
        case creationDatetime = "creation_datetime"
        case author
    }
}

struct DumpertComment: Sendable, Identifiable {
    let id: Int
    let authorUsername: String
    let displayContent: String
    let kudosCount: Int
    let creationDatetime: String?
}
