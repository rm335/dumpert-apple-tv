import XCTest

/// Verifies the custom transport bar menu built by
/// `VideoPlayerViewModel.rebuildTransportBarMenu()` actually renders in the
/// player: opening a clip and revealing its controls surfaces a custom
/// "Vorige"/"Volgende" skip cell (tvOS exposes them as Cells).
///
/// Which clip opens is not deterministic (the Toppers hero auto-rotates) and the
/// transport bar auto-hides seconds after the last press, so this drives Select
/// (open clip / reveal controls) + Down (focus the bar) in a loop and asserts —
/// plus screenshots — the moment a custom skip cell is on screen. The "hide at
/// the ends" nuance is pure hasNextVideo/hasPreviousVideo gating.
final class TransportBarUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTransportBarShowsCustomSkipCells() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.buttons.firstMatch.waitForExistence(timeout: 20),
            "Home screen never appeared"
        )

        let remote = XCUIRemote.shared
        let next = app.cells["Volgende"]
        let prev = app.cells["Vorige"]

        var found = false
        for _ in 0..<15 {
            remote.press(.select)
            usleep(1_000_000)
            remote.press(.down)
            usleep(700_000)

            if next.exists || prev.exists {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "player-transport-bar"
                shot.lifetime = .keepAlways
                add(shot)
                found = true
                break
            }
        }

        XCTAssertTrue(
            found,
            "Expected a custom 'Volgende'/'Vorige' skip cell in the transport bar"
        )
    }
}
