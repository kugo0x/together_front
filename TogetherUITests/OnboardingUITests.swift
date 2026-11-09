import XCTest

/// Signed out → sign up / log in → onboarding → the app; the invite sheet; Settings.
@MainActor
final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(_ arguments: [String]) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-noNotifications", "YES", "-initialSpace", "shared"] + arguments
        app.launch()
    }

    private func tapHittable(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let matches = app.buttons.matching(identifier: label)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5), "no \(label)", file: file, line: line)
        for i in 0..<matches.count where matches.element(boundBy: i).isHittable {
            matches.element(boundBy: i).tap()
            return
        }
        XCTFail("\(label) is not on screen (hidden by the keyboard?)", file: file, line: line)
    }

    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    /// Types into the password field. On a new-password field iOS may first offer "Use Strong Password?"
    /// (system AutoFill) — close it so it doesn't take the keystrokes.
    private func typePassword(_ password: String) {
        let field = app.secureTextFields["Password"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        if app.staticTexts["Use Strong Password?"].waitForExistence(timeout: 1.5) {
            app.buttons["Close"].firstMatch.tap()
            field.tap()
        }
        field.typeText(password)
    }

    /// The form's main button ("Create account" / "Log in"), pinned above the keyboard.
    private var submit: XCUIElement { app.buttons["authSubmit"] }

    private func signIn(email: String, password: String, mode: String) {
        tapHittable(mode == "signup" ? "Get started" : "I already have an account")
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 3))
        emailField.tap()
        emailField.typeText(email)
        typePassword(password)
        XCTAssertTrue(submit.isHittable, "the main button stays above the keyboard")
        submit.tap()
    }

    /// Settings is a list: rows below the fold exist only once scrolled to.
    private func scrollSettings(to label: String) {
        let button = app.buttons[label].firstMatch
        for _ in 0..<6 where !(button.exists && button.isHittable) {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
    }

    // MARK: Sign up / log in

    func testSignUpThenNameThenJustMe() {
        launch(["-signedOut", "YES"])
        signIn(email: "robin@example.com", password: "password1", mode: "signup")

        let name = app.textFields["Your name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What should we call you?"].exists)
        name.typeText("Robin")
        tapHittable("Continue")

        XCTAssertTrue(app.staticTexts["Share with someone?"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Just me for now")).firstMatch.tap()

        XCTAssertTrue(text(containing: ", Robin").waitForExistence(timeout: 5), "Home greets by name")
        XCTAssertTrue(app.staticTexts["Shared works best with two"].exists, "a new account starts alone")
        XCTAssertTrue(app.staticTexts["Welcome, Robin"].exists)
    }

    func testValidationAndWrongPassword() {
        launch(["-signedOut", "YES"])
        tapHittable("I already have an account")
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 3))
        emailField.tap()
        emailField.typeText("alex@")
        app.secureTextFields["Password"].tap()
        XCTAssertTrue(app.staticTexts["Enter an email like name@example.com"].waitForExistence(timeout: 2))
        XCTAssertFalse(submit.isEnabled, "disabled until the email and password are valid")

        emailField.tap()
        emailField.typeText("example.com")
        typePassword("wrongpass1")
        submit.tap()
        XCTAssertTrue(app.staticTexts["That password doesn’t match this email. Try again or reset it."]
            .waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Get started"].exists == false, "still on the form")
    }

    func testShowHidePassword() {
        launch(["-signedOut", "YES"])
        tapHittable("Get started")
        typePassword("password1")
        tapHittable("Show password")
        XCTAssertEqual(app.textFields["Password"].value as? String, "password1")
        tapHittable("Hide password")
        XCTAssertTrue(app.secureTextFields["Password"].exists)
    }

    func testExistingAccountGoesStraightIn() {
        launch(["-signedOut", "YES"])
        signIn(email: "alex@example.com", password: "together123", mode: "login")
        XCTAssertTrue(text(containing: ", Alex").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["What should we call you?"].exists)
    }

    func testJoinWithAnInviteCode() {
        launch(["-signedOut", "YES"])
        signIn(email: "robin@example.com", password: "password1", mode: "signup")
        let name = app.textFields["Your name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Robin")
        tapHittable("Continue")

        let code = app.textFields["Invite code"]
        XCTAssertTrue(code.waitForExistence(timeout: 3))
        code.tap()
        code.typeText("TGT-0000")
        tapHittable("Join")
        XCTAssertTrue(app.staticTexts["That code didn’t work. Ask for a new invite."].waitForExistence(timeout: 3))

        code.tap()
        code.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "tgt7kq2")
        tapHittable("Join")
        XCTAssertTrue(app.staticTexts["You joined Sam’s Shared space"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Shared works best with two"].exists)
    }

    // MARK: Invite

    func testInviteEndsWithPartnerJoining() {
        launch(["-signedIn", "YES", "-initialTab", "home", "-alone", "YES"])
        tapHittable("Invite")
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Code TGT-")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 3))
        tapHittable("Send invite link")
        // The system share sheet exposes its actions as cells, not buttons.
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "the system share sheet")
        copy.tap()
        XCTAssertTrue(app.staticTexts["Sam joined your Shared space"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["Shared works best with two"].exists)
    }

    // MARK: Settings

    private func openSettings() {
        tapHittable("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    func testSuggestionsToggleHidesTheTeaser() {
        launch(["-signedIn", "YES", "-initialTab", "groceries"])
        XCTAssertTrue(app.staticTexts["Before Saturday’s shop"].waitForExistence(timeout: 5))
        openSettings()
        let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Grocery suggestions")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        tapHittable("Done")
        XCTAssertFalse(app.staticTexts["Before Saturday’s shop"].waitForExistence(timeout: 1), "card hidden when off")
    }

    func testLeaveSharedNeedsConfirmation() {
        launch(["-signedIn", "YES", "-initialTab", "home"])
        openSettings()
        scrollSettings(to: "Leave Shared space")
        tapHittable("Leave Shared space")
        XCTAssertTrue(app.staticTexts["Leave the Shared space?"].waitForExistence(timeout: 3))
        tapHittable("Stay")
        XCTAssertTrue(app.buttons["Leave Shared space"].waitForExistence(timeout: 3), "nothing changed")
        XCTAssertFalse(app.buttons["Invite your partner"].exists)

        tapHittable("Leave Shared space")
        XCTAssertTrue(app.staticTexts["Leave the Shared space?"].waitForExistence(timeout: 3))
        tapHittable("Leave Shared space")
        // Left: the row is gone (only a member can leave). No swipe-down here — at the top it closes the sheet.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["Leave Shared space"])
        waitForExpectations(timeout: 3)
        tapHittable("Done")
        XCTAssertTrue(app.staticTexts["Shared works best with two"].waitForExistence(timeout: 3))
    }

    func testLogOutReturnsToWelcome() {
        launch(["-signedIn", "YES", "-initialTab", "home"])
        openSettings()
        scrollSettings(to: "Log out")
        tapHittable("Log out")
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 5))
    }
}
