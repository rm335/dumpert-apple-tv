import Testing
@testable import Dumpert

@Suite("Focus restore after player")
struct FocusRestoreTests {
    private let snapshot = ["a", "b", "c", "d"]

    @Test("last played still shown: focus it")
    func stillPresent() {
        #expect(FocusRestore.target(lastPlayed: "b", snapshot: snapshot, current: snapshot) == "b")
    }

    @Test("last played hidden: focus the next survivor")
    func goneTakesNext() {
        #expect(FocusRestore.target(lastPlayed: "b", snapshot: snapshot, current: ["a", "c", "d"]) == "c")
        #expect(FocusRestore.target(lastPlayed: "b", snapshot: snapshot, current: ["a", "d"]) == "d")
    }

    @Test("last played hidden at the end: focus the previous survivor")
    func goneAtEndTakesPrevious() {
        #expect(FocusRestore.target(lastPlayed: "d", snapshot: snapshot, current: ["a", "b", "c"]) == "c")
    }

    @Test("nothing to restore")
    func nilCases() {
        #expect(FocusRestore.target(lastPlayed: nil, snapshot: snapshot, current: snapshot) == nil)
        #expect(FocusRestore.target(lastPlayed: "zzz", snapshot: snapshot, current: snapshot) == nil)
        #expect(FocusRestore.target(lastPlayed: "a", snapshot: snapshot, current: []) == nil)
        #expect(FocusRestore.target(lastPlayed: "a", snapshot: [], current: []) == nil)
    }
}
