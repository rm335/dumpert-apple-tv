import Testing
@testable import Dumpert

@Suite("Tag search hand-off")
@MainActor
struct TagSearchHandOffTests {
    @Test("Pending query is consumed exactly once")
    func consumeOnce() {
        let coordinator = PlaybackCoordinator.shared
        coordinator.requestTagSearch("vuurwerk")
        #expect(coordinator.pendingSearchQuery == "vuurwerk")

        #expect(coordinator.consumePendingSearchQuery() == "vuurwerk")
        #expect(coordinator.pendingSearchQuery == nil)
        #expect(coordinator.consumePendingSearchQuery() == nil)
    }
}
