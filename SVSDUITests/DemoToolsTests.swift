import XCTest

/// Covers the two demo affordances: jumping between screens from the dev menu,
/// and the stand-in Messages thread that "Send a Text" opens.
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
        app.buttons["What’s your name?"].tap()
        XCTAssertTrue(
            app.staticTexts["What’s your name?"].waitForExistence(timeout: 6),
            "expected the name screen after jumping"
        )
    }

    /// Like the real composer, the thread opens empty: Bloom never writes the
    /// message for you. Whatever you type sends as a bubble.
    func testSendATextOpensAnEmptyThread() {
        let app = launchApp(["-ShowFriends", "-ShowToday"])
        XCTAssertTrue(app.staticTexts["Recent"].waitForExistence(timeout: 6))

        // Its label names the friend: "Send Jadden a text".
        let send = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Send ' AND label ENDSWITH ' a text'")).firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 6))
        send.tap()

        let composer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "elementType IN {49, 50}"))   // textField / textView
            .firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 6), "expected the composer")
        composer.tap()
        composer.typeText("Coffee later?")

        app.buttons["Send"].tap()
        XCTAssertTrue(
            app.staticTexts["Coffee later?"].waitForExistence(timeout: 5),
            "expected the sent message as a bubble"
        )
    }
}
