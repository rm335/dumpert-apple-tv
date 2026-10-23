import XCTest

/// Siri Remote navigation checks. Everything is driven with `XCUIRemote` and
/// asserted through tvOS focus (`hasFocus`), so the tests read like a user
/// pressing buttons. Tab buttons are found by their SF Symbol identifier so the
/// tests do not depend on the simulator language. Needs network (live feed).
@MainActor
final class NavigationUITests: XCTestCase {
    private let remote = XCUIRemote.shared
    private var app: XCUIApplication!

    private let tabOrder = ["flame.fill", "sparkles", "square.grid.2x2.fill", "eye.fill", "magnifyingglass", "gearshape.fill"]
    private let pillLabels: Set<String> = ["Reeten", "VrijMiCo", "Dashcam", "Classics", "DumpertTV"]

    override func setUp() async throws {
        continueAfterFailure = true // let the run finish and flush screenshots even on a failure
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 30), "Home screen never appeared")
        // Wait for the feed: the first video card (label holds ", Video,").
        XCTAssertTrue(card(app.buttons).firstMatch.waitForExistence(timeout: 30), "No video cards loaded")
        pause(1.5)
    }

    // MARK: - Helpers

    private func pause(_ seconds: Double) { usleep(UInt32(seconds * 1_000_000)) }

    private func press(_ button: XCUIRemote.Button, times: Int = 1, wait: Double = 0.7) {
        for _ in 0..<times {
            remote.press(button)
            pause(wait)
        }
    }

    /// A video card: its accessibility label always contains ", Video,".
    private func card(_ query: XCUIElementQuery) -> XCUIElementQuery {
        query.matching(NSPredicate(format: "label CONTAINS ', Video,'"))
    }

    /// The focused element. Mostly a Button; falls back to any element so a
    /// focused Menu (sort/filter pickers) or search field does not crash the query.
    private func focusedButton() -> XCUIElement {
        let focus = NSPredicate(format: "hasFocus == true")
        let button = app.buttons.matching(focus).firstMatch
        if button.exists { return button }
        let any = app.descendants(matching: .any).matching(focus)
        return any.count > 0 ? any.element(boundBy: any.count - 1) : button
    }

    private func title(of element: XCUIElement) -> String {
        // "NSFW, Title, Video, 0:14, ..." -> drop everything from ", Video,"
        element.label.components(separatedBy: ", Video,").first ?? element.label
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Moves focus to a tab and one step down into its content.
    private func goToTab(_ symbol: String) {
        let tabs = app.tabBars.buttons
        for _ in 0..<8 where !tabs.matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists {
            press(.up, wait: 0.5)
        }
        let target = tabs[symbol]
        let targetIndex = tabOrder.firstIndex(of: symbol)!
        for _ in 0..<tabOrder.count {
            if target.hasFocus { break }
            let current = tabOrder.firstIndex { tabs[$0].hasFocus } ?? targetIndex
            press(current < targetIndex ? .right : .left, wait: 0.5)
        }
        XCTAssertTrue(target.hasFocus, "Could not focus tab \(symbol)")
        pause(1.5)
        press(.down, wait: 1.0)
    }

    // MARK: - Toppers

    /// Up/Down must walk row by row (Vandaag -> Week -> Vandaag), never jump
    /// from the far right of one row past a shorter row.
    func testToppersRowsAreWalkedOneByOne() {
        // The app launches with focus on the tab bar: Down = hero, Down again = first row.
        press(.down, times: 2, wait: 1.0)
        attach("toppers-first-row")
        XCTAssertTrue(card(app.buttons).matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists, "Focus did not enter first row (focused: \(focusedButton().label))")
        press(.right, times: 3)

        press(.down, wait: 1.0)
        let rowTwo = focusedButton()
        let rowTwoY = rowTwo.frame.midY
        attach("toppers-row-2")
        XCTAssertLessThan(rowTwo.frame.width, 900, "Focus is on a card, not the hero")

        press(.up, wait: 1.0)
        let back = focusedButton()
        attach("toppers-back-up")
        XCTAssertLessThan(back.frame.width, 900, "Up from row 2 must land on a card in row 1, not the hero")
        XCTAssertLessThan(back.frame.midY, rowTwoY, "Up from row 2 must move to the row above")

        // One more Up leaves the rows for the hero.
        press(.up, wait: 1.0)
        XCTAssertGreaterThan(focusedButton().frame.width, 1000, "Up from row 1 must reach the hero")
    }

    // MARK: - Categorieen

    /// Up from the grid must enter the pill bar on the SELECTED pill.
    func testCategoriesUpReturnsToSelectedPill() {
        goToTab("square.grid.2x2.fill")
        attach("categories-entered")
        // Entering the bar must land on a pill (the selected one). Then move one
        // pill sideways and select it, so the selection differs from the entry pill.
        XCTAssertTrue(pillLabels.contains(focusedButton().label), "Entering the bar must focus a pill, got '\(focusedButton().label)'")
        press(focusedButton().label == "Reeten" ? .right : .left, wait: 0.6)
        let selected = focusedButton().label
        XCTAssertTrue(pillLabels.contains(selected))
        press(.select, wait: 3.0)

        // Down into the grid (skips sort/filter menus), then to a right column.
        for _ in 0..<5 where !focusedButton().label.contains(", Video,") { press(.down, wait: 1.2) }
        XCTAssertTrue(focusedButton().label.contains(", Video,"), "Never reached the grid")
        press(.right, times: 2)

        for _ in 0..<5 where !pillLabels.contains(focusedButton().label) { press(.up, wait: 1.0) }
        attach("categories-up-to-pills")
        XCTAssertEqual(focusedButton().label, selected, "Up from the grid must land on the selected pill")
    }

    // MARK: - Focus restore after the player

    func testFocusReturnsToTheSameCardAfterPlayer() {
        goToTab("sparkles")
        for _ in 0..<5 where !focusedButton().label.contains(", Video,") { press(.down, wait: 1.0) }
        press(.right, wait: 0.8)
        let before = title(of: focusedButton())
        XCTAssertFalse(before.isEmpty)

        press(.select, wait: 8.0) // open the player and let it start
        attach("player-open")
        press(.menu, wait: 3.0)   // close it

        let after = focusedButton()
        attach("after-player-closed")
        XCTAssertTrue(after.exists, "Nothing has focus after closing the player")
        XCTAssertEqual(title(of: after), before, "Focus must return to the card that was opened")
    }

    // MARK: - Settings

    /// Pressing "Nu verversen" must not throw focus to another row.
    func testSettingsRefreshKeepsFocus() {
        goToTab("gearshape.fill")
        // Row label: "Refresh now, Fetch the latest content" ("Nu verversen" in Dutch).
        let refresh = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'refresh now' OR label CONTAINS[c] 'nu verversen'")).firstMatch
        for _ in 0..<30 where !refresh.hasFocus { press(.down, wait: 0.5) }
        attach("settings-at-refresh-row")
        // Never press Select anywhere else: neighbours are destructive (Clear cache, Restore defaults).
        guard refresh.hasFocus else { return XCTFail("Never reached the refresh row") }

        press(.select, wait: 0.8)
        XCTAssertTrue(refresh.hasFocus, "Focus left the refresh row while refreshing")
        pause(6)
        attach("settings-after-refresh")
        XCTAssertTrue(refresh.hasFocus, "Focus left the refresh row after refreshing")
    }

    // MARK: - Search

    /// Tap a suggestion: focus must follow to the first result.
    func testSearchSuggestionMovesFocusToResults() {
        goToTab("magnifyingglass")
        // Focus starts on the keyboard. Walk down to a popular-tag chip
        // (labels: "Popular search: <tag>"; never press Select on a keyboard key).
        for _ in 0..<8 where !focusedButton().label.hasPrefix("Popular search:") { press(.down, wait: 0.8) }
        let chipLabel = focusedButton().label
        attach("search-before-tap")
        guard chipLabel.hasPrefix("Popular search:") else { return XCTFail("No popular chip reachable (focused: \(chipLabel))") }
        press(.select, wait: 1.0)

        let firstResult = card(app.buttons).firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 20), "No results for chip \(chipLabel)")
        pause(1.5)
        attach("search-after-results")
        XCTAssertTrue(
            card(app.buttons).matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists,
            "Focus must be on a result card after picking '\(chipLabel)'"
        )
    }

    // MARK: - Player overlays

    /// Opens Settings > Up Next, focuses the row whose label contains `row`,
    /// opens its picker and chooses the option whose label contains `option`.
    /// Only presses Select on a row/option it has positively identified.
    private func chooseSetting(row rowText: String, option optionText: String) -> Bool {
        let any = app.descendants(matching: .any)
        let row = any.matching(NSPredicate(format: "label BEGINSWITH[c] %@", rowText)).firstMatch
        for _ in 0..<40 where !row.hasFocus {
            // Walk toward the row (it may be above the current focus after a picker pops back).
            press(row.exists && row.frame.minY < focusedButton().frame.minY ? .up : .down, wait: 0.4)
        }
        guard row.hasFocus else { XCTFail("Settings row '\(rowText)' not reachable"); return false }
        press(.select, wait: 1.2)
        let option = any.matching(NSPredicate(format: "label BEGINSWITH[c] %@", optionText)).firstMatch
        for _ in 0..<8 where !option.hasFocus {
            guard option.exists else { break }
            press(option.frame.minY < focusedButton().frame.minY ? .up : .down, wait: 0.5)
        }
        guard option.hasFocus else { XCTFail("Option '\(optionText)' not reachable"); return false }
        press(.select, wait: 1.2) // picks the option and pops back to the list
        return true
    }

    /// Menu on the Up Next card must cancel the card and keep the player open.
    /// The test first sets "No minimum" + a 10 second countdown through the UI,
    /// so even a short clip shows the card (default: only clips of 60s or more).
    func testMenuOnUpNextCancelsCardNotPlayer() {
        goToTab("gearshape.fill")
        // Main list row "Next video" opens the Up Next screen (rows: Show overlay,
        // Countdown, Minimum video length). BEGINSWITH: "Autoplay" also mentions "next video".
        let nextVideoRow = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] 'Next video'")).firstMatch
        for _ in 0..<40 where !nextVideoRow.hasFocus { press(.down, wait: 0.4) }
        guard nextVideoRow.hasFocus else { return XCTFail("Settings row 'Next video' not reachable") }
        press(.select, wait: 1.5)
        guard chooseSetting(row: "Minimum video length", option: "No minimum"),
              chooseSetting(row: "Countdown", option: "10 seconds") else { return }
        attach("up-next-settings-done")

        goToTab("flame.fill")
        press(.down, times: 1, wait: 1.0)   // hero -> first row (tab bar -> hero was goToTab's step)
        press(.select, wait: 1.0)           // open player
        let cancel = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Cancel next' OR label CONTAINS[c] 'Annuleer volgende'")).firstMatch
        guard cancel.waitForExistence(timeout: 75) else {
            attach("no-up-next")
            return XCTFail("Up Next card never appeared")
        }
        attach("up-next-visible")
        press(.menu, wait: 1.5)
        attach("up-next-after-menu")
        // Without the fix Menu falls through to tvOS and sends the app to the Home screen.
        XCTAssertEqual(app.state, .runningForeground, "Menu on the Up Next card must not leave the app")
        XCTAssertFalse(cancel.exists, "Menu should dismiss the Up Next card")
        // Player still open: no browse card has focus yet.
        let focusedCard = card(app.buttons).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertFalse(focusedCard.exists, "Menu closed the whole player")

        // A second Menu closes the player: focus lands back on a card of the browse screen.
        press(.menu, wait: 3.0)
        attach("up-next-after-second-menu")
        XCTAssertEqual(app.state, .runningForeground, "Second Menu must close the player, not leave the app")
        XCTAssertTrue(focusedCard.exists, "Second Menu should return to the browse screen with a card focused")
    }
}
