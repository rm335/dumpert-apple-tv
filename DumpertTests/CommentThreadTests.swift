import Testing
import Foundation
@testable import Dumpert

@Suite("Comment thread mapping")
struct CommentThreadTests {
    private final class BundleToken {}
    private enum FixtureError: Error { case notFound(String) }

    private func loadFixture(_ name: String) throws -> Data {
        guard let url = Bundle(for: BundleToken.self).url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ) else {
            throw FixtureError.notFound(name)
        }
        return try Data(contentsOf: url)
    }

    @Test("Decode nested child comments and map to a thread")
    func decodeAndMapThread() throws {
        let data = try loadFixture("comments")
        let response = try JSONDecoder().decode(CommentsAPIResponse.self, from: data)
        let comments = DumpertComment.comments(from: response)

        // Banned top-level author dropped (its 100 kudos would sort first);
        // remainder sorted by kudos descending.
        #expect(comments.map(\.id) == [102, 101])
        #expect(comments[0].kudosCount == 42)
        #expect(comments[0].replies.isEmpty)

        // Replies: banned reply author dropped, API order preserved,
        // unknown author id falls back to "Onbekend".
        let replies = comments[1].replies
        #expect(replies.map(\.id) == [201, 203])
        #expect(replies[0].authorUsername == "topper")
        #expect(replies[1].authorUsername == "Onbekend")
    }

    @Test("creationDate parses the comments API timestamp")
    func creationDateParsing() {
        let comment = DumpertComment(
            id: 1,
            authorUsername: "topper",
            displayContent: "test",
            kudosCount: 0,
            creationDatetime: "2026-09-04T06:54:46Z",
            replies: []
        )
        #expect(comment.creationDate != nil)

        let missing = DumpertComment(
            id: 2,
            authorUsername: "topper",
            displayContent: "test",
            kudosCount: 0,
            creationDatetime: nil,
            replies: []
        )
        #expect(missing.creationDate == nil)
    }
}
