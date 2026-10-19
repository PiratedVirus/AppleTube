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
        XCTAssertTrue(app.buttons["Create Station"].exists)
        XCTAssertTrue(app.buttons["Share Song…"].exists)
    }

    /// A playlist's ⋯ menu offers Edit Cover, and the editor shows the generated cover.
    func testPlaylistMenuOpensCoverEditor() {
        app.launchArguments = ["-openRoute", "playlist:VLPLWifY4ZVngjfsRWcaplbD2m1muE3b5Wn-"]
        app.launch()
        let more = app.buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 30), "no ⋯ button on the playlist page")
        sleep(3)
        more.tap()
        XCTAssertTrue(app.buttons["Play Next"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share Playlist…"].exists)
        attachScreenshot("ui_playlist_menu")
        app.buttons["Edit Cover…"].tap()
        XCTAssertTrue(app.navigationBars["Edit Cover"].waitForExistence(timeout: 5), "cover editor didn't open")
        app.switches["Use Original Artwork"].firstMatch.tap()
        sleep(1)
        attachScreenshot("ui_cover_editor")
        app.buttons["Lavender"].tap()
        sleep(1)
        attachScreenshot("ui_cover_editor2")
    }

    /// The profile button opens Settings; Customize Home lists Home's shelves.
    func testSettingsAndCustomizeHome() {
        app.launchArguments = []
        app.launch()
        let profile = app.buttons["Account and Settings"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        sleep(6)   // let Home load so its shelves are known
        profile.tap()
        XCTAssertTrue(app.staticTexts["Accent Colour"].waitForExistence(timeout: 5), "settings didn't open")
        attachScreenshot("ui_settings1")
        app.buttons["Customize Home"].tap()
        XCTAssertTrue(app.navigationBars["Customize Home"].waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot("ui_settings2")
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

    /// Keeps a screenshot in the test results (Xcode → Reports).
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
