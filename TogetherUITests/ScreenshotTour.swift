import XCTest

/// Opt-in: walks the auth, onboarding, invite and Settings screens and attaches a screenshot of each, in light,
/// dark and Dynamic Type XXL. Run with
/// `TEST_RUNNER_SCREENSHOT_TOUR=1 xcodebuild test … -only-testing:TogetherUITests/ScreenshotTour`
/// and export the attachments from the .xcresult (`xcrun xcresulttool export attachments`).
@MainActor
final class ScreenshotTour: XCTestCase {
    private var app: XCUIApplication!
    private var suffix = ""

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_TOUR"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_SCREENSHOT_TOUR=1 to take the screenshot tour")
        }
        continueAfterFailure = true
    }

    override func tearDown() async throws {
        XCUIDevice.shared.appearance = .light
    }

    func testLight() { tour(dark: false, xxl: false) }
    func testDark() { tour(dark: true, xxl: false) }
    func testXXL() { tour(dark: false, xxl: true) }

    private func tour(dark: Bool, xxl: Bool) {
        XCUIDevice.shared.appearance = dark ? .dark : .light
        suffix = xxl ? "xxl" : dark ? "dark" : "light"
        var extra: [String] = []
        if xxl { extra = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"] }

        app = XCUIApplication()
        app.launchArguments = ["-signedOut", "YES", "-noNotifications", "YES", "-initialSpace", "shared"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 5))
        shot("1-welcome")

        app.buttons["I already have an account"].tap()
        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 3))
        email.tap()
        email.typeText("alex@example.com")
        let password = app.secureTextFields["Password"]
        password.tap()
        if app.staticTexts["Use Strong Password?"].waitForExistence(timeout: 1) { app.buttons["Close"].firstMatch.tap(); password.tap() }
        password.typeText("wrongpass1")
        app.buttons["authSubmit"].tap()
        XCTAssertTrue(app.staticTexts["That password doesn’t match this email. Try again or reset it."].waitForExistence(timeout: 3))
        shot("2-login-error")

        app.buttons["Sign up"].firstMatch.tap()
        email.tap()
        email.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "robin@example.com")
        password.tap()
        if app.staticTexts["Use Strong Password?"].waitForExistence(timeout: 1) { app.buttons["Close"].firstMatch.tap(); password.tap() }
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "password1")
        shot("3-signup")
        app.buttons["authSubmit"].tap()

        let name = app.textFields["Your name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Robin")
        shot("4-name")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Share with someone?"].waitForExistence(timeout: 3))
        shot("5-share")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Invite your partner")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Send invite link"].waitForExistence(timeout: 5))
        sleep(1)
        shot("6-invite")
        app.buttons["Not now"].tap()

        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        sleep(1)
        shot("7-settings-top")
        app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        shot("8-settings-bottom")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name)-\(suffix)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
