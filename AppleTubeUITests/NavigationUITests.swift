import XCTest

/// Drives the real app in the simulator (signed out, live YouTube Music data) to check navigation and menus.
final class NavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private var backButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Back' OR identifier == 'BackButton'")).firstMatch
    }

    /// Opening a page and going back returns to the screen you came from in one step,
    /// by the back button and by the edge swipe.
    func testBackFromArtistReturnsToSearchInOneStep() {
        app.launchArguments = ["-startTab", "search", "-searchQuery", "coldplay"]
        app.launch()
        let artist = app.buttons["Coldplay, Artist"]
        XCTAssertTrue(artist.waitForExistence(timeout: 30), "no artist in search results")
        artist.tap()
        XCTAssertTrue(backButton.waitForExistence(timeout: 20), "artist page didn't open")
        backButton.tap()
        XCTAssertTrue(artist.waitForExistence(timeout: 5), "back button didn't return to results")
        XCTAssertFalse(backButton.exists, "more than one page was pushed")

        artist.tap()
        XCTAssertTrue(backButton.waitForExistence(timeout: 20))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertTrue(artist.waitForExistence(timeout: 5), "edge swipe didn't go back")
    }

    /// Long-pressing a song shows Apple Music's actions.
    func testLongPressSongShowsActions() {
        app.launchArguments = ["-startTab", "search", "-searchQuery", "coldplay"]
        app.launch()
        let song = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Song ·'")).firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 30), "no song in search results")
        song.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Play Next"].waitForExistence(timeout: 5), "context menu didn't open")
        XCTAssertTrue(app.buttons["Play Last"].exists)
        XCTAssertTrue(app.buttons["Start Station"].exists)
    }

    /// Tapping the Search tab while on it puts the cursor in the search field.
    func testRetappingSearchTabFocusesField() {
        app.launchArguments = ["-startTab", "search"]
        app.launch()
        let tab = app.tabBars.buttons["Search"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard didn't appear")
    }
}
