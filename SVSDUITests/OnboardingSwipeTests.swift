import XCTest

/// Covers turning onboarding pages by swipe, including the rules about when a
/// swipe is allowed to move you.
final class OnboardingSwipeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(step: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-OnboardStep", "\(step)"]
        app.launch()
        return app
    }

    private func waitFor(_ app: XCUIApplication, _ text: String, line: UInt = #line) {
        XCTAssertTrue(
            app.staticTexts[text].waitForExistence(timeout: 5),
            "expected \"\(text)\" on screen",
            line: line
        )
    }

    /// Each permission page raises its prompt by itself; once it's answered,
    /// a swipe moves you on.
    private func answerPrompt(_ app: XCUIApplication, _ button: String, line: UInt = #line) {
        let allow = app.buttons[button].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 5), "expected the \"\(button)\" prompt", line: line)
        allow.tap()
    }

    func testSwipeMovesForwardAndBackThroughPermissions() {
        let app = launch(step: 4)
        waitFor(app, "Contacts")
        answerPrompt(app, "Allow Full Access")

        app.swipeLeft()
        waitFor(app, "Background location")
        answerPrompt(app, "Allow While Using App")

        app.swipeLeft()
        waitFor(app, "Photos")

        app.swipeRight()
        waitFor(app, "Background location")

        app.swipeRight()
        waitFor(app, "Contacts")
    }

    /// The name screen gates forward on having a name, exactly as its button does.
    func testSwipeForwardIsBlockedUntilTheFieldIsFilled() {
        let app = launch(step: 2)
        waitFor(app, "What’s your name?")

        app.swipeLeft()
        waitFor(app, "What’s your name?")

        app.textFields["Your name"].tap()
        app.typeText("Amber")

        app.swipeLeft()
        XCTAssertTrue(
            app.staticTexts["welcome amber!"].waitForExistence(timeout: 5),
            "expected the celebrate screen once a name is in"
        )
    }

    /// Swiping back off the code prompt returns to the number on the same page,
    /// which is the only way to correct a wrong one.
    func testSwipeBackFromCodeReturnsToNumber() {
        let app = launch(step: 1)
        waitFor(app, "We’ll need your number.")

        app.textFields["Phone number"].tap()
        app.typeText("7655550142")

        app.swipeLeft()
        waitFor(app, "Enter your code.")

        app.swipeRight()
        waitFor(app, "We’ll need your number.")
    }
}

/// The permission screens raise their prompt on their own, and "next" stays
/// greyed until it's answered.
final class PermissionPromptTests: XCTestCase {
    func testPromptAppearsAndUnlocksNext() {
        let app = XCUIApplication()
        app.launchArguments = ["-OnboardStep", "4"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Contacts"].waitForExistence(timeout: 5))
        let next = app.buttons["next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "next should wait for an answer")

        let allow = app.buttons["Allow Full Access"].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 5), "expected the Contacts prompt to come up by itself")
        allow.tap()

        XCTAssertTrue(next.isEnabled, "answering the prompt should unlock next")
    }
}
