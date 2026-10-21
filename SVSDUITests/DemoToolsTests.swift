import XCTest

/// Covers the two demo affordances: jumping between screens from the dev menu,
/// and the stand-in Messages thread that "Send a text" opens.
final class DemoToolsTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launchApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    func testDevMenuJumpsToAnotherScreen() {
        let app = launchApp(["-ShowFriends", "-ShowToday"])
        XCTAssertTrue(app.staticTexts["Recent"].waitForExistence(timeout: 6))

        app.buttons["Developer menu"].tap()
        XCTAssertTrue(app.navigationBars["Jump to"].waitForExistence(timeout: 5))

        // Pick an entry that is on screen without scrolling the sheet.
        app.buttons["Permission · Contacts"].tap()
        XCTAssertTrue(
            app.staticTexts["Enabling permissions"].waitForExistence(timeout: 6),
            "expected the contacts permission screen after jumping"
        )
    }

    func testSendATextOpensTheThreadWithTheSuggestionReady() {
        let app = launchApp(["-ShowFriends", "-ShowToday"])
        XCTAssertTrue(app.staticTexts["Recent"].waitForExistence(timeout: 6))

        app.buttons["Send a text"].tap()

        let composer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "elementType IN {49, 50}"))   // textField / textView
            .firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 6), "expected the composer")
        XCTAssertEqual(composer.value as? String, "Grab a coffee?")

        app.buttons["Send"].tap()
        XCTAssertTrue(
            app.staticTexts["Grab a coffee?"].waitForExistence(timeout: 5),
            "expected the sent message as a bubble"
        )
    }
}
