import XCTest

final class SpotifyFreeUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Search → play scenario from Phase 8.5.
    /// Requires a running local backend on http://localhost:3000 (or the
    /// `SPOTIFY_FREE_BACKEND_URL` build setting pointed somewhere that works).
    func testSearchAndPlay() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Search"].tap()

        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("Blinding Lights")

        let firstRow = app.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        // MiniPlayer appears with the track title within 3s
        let miniTitle = app.staticTexts["Blinding Lights"].firstMatch
        XCTAssertTrue(miniTitle.waitForExistence(timeout: 3))
    }

    func testCreatePlaylistPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Library"].tap()
        app.navigationBars.buttons["add"].tap()
        let nameField = app.textFields["Name"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Test123")
        app.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Test123"].waitForExistence(timeout: 2))

        app.terminate()
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Test123"].waitForExistence(timeout: 3))
    }
}
