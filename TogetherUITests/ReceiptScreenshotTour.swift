import XCTest

/// Opt-in: walks the receipt screens and attaches a screenshot of each, for comparing with the design in light,
/// dark and large text. Run with `TEST_RUNNER_RECEIPT_TOUR=1` (set appearance / text size with `simctl ui` first);
/// export with `xcrun xcresulttool export attachments`.
@MainActor
final class ReceiptScreenshotTour: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RECEIPT_TOUR"] == "1", "screenshot tour is opt-in")
        continueAfterFailure = true
    }

    private func launch(_ extra: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-signedIn", "YES", "-initialTab", "groceries", "-initialSpace", "shared",
                               "-noNotifications", "YES"] + extra
        app.launch()
        _ = app.staticTexts["7 to buy · Shared with Sam"].waitForExistence(timeout: 8)
    }

    private func shot(_ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ label: String) {
        let button = app.buttons[label].firstMatch
        _ = button.waitForExistence(timeout: 8)
        button.tap()
    }

    func testOneReceiptInTwoPhotos() {
        launch(["-receiptPhotos", "2", "-receiptSeparate", "NO", "-receiptFixture", "corner", "-receiptDelay", "3000"])
        tap("Scan receipt")
        _ = app.buttons["Read receipt"].waitForExistence(timeout: 5)
        shot("1-pages")
        tap("Read receipt")
        shot("2-reading")
        _ = app.staticTexts["Review receipt"].waitForExistence(timeout: 8)
        shot("3-review")
        tap("Mark 3 as bought")
        shot("4-finished")
    }

    func testQueue() {
        launch(["-receiptPhotos", "2", "-receiptFixture", "corner,biedronka", "-receiptDelay", "2000"])
        tap("Scan receipt")
        _ = app.buttons["Separate receipts"].waitForExistence(timeout: 5)
        shot("5-grouping")
        tap("Separate receipts")
        _ = app.staticTexts["Review receipt"].waitForExistence(timeout: 8)
        shot("6-queue-review")
    }

    func testCaptureAndOffline() {
        launch(["-receiptFixture", "offline", "-receiptDelay", "1000"])
        tap("Scan receipt")
        _ = app.buttons["Choose from Photos"].waitForExistence(timeout: 5)
        shot("7-capture")
        app.terminate()
        launch(["-receiptPhotos", "1", "-receiptFixture", "offline", "-receiptDelay", "1000"])
        tap("Scan receipt")
        tap("Read receipt")
        _ = app.staticTexts["You’re offline"].waitForExistence(timeout: 6)
        shot("8-offline")
    }

    func testMismatchAndErrors() {
        launch(["-receiptPhotos", "1", "-receiptFixture", "mismatch", "-receiptDelay", "1000"])
        tap("Scan receipt")
        tap("Read receipt")
        _ = app.staticTexts["Review receipt"].waitForExistence(timeout: 6)
        let chips = app.buttons["Choose from your list"]
        for _ in 0..<6 where !(chips.exists && chips.isHittable) { app.swipeUp() }
        shot("9-mismatch")
        for _ in 0..<6 { app.swipeUp() }
        shot("9b-total")
        app.terminate()
        launch(["-receiptPhotos", "1", "-receiptFixture", "tooLong", "-receiptDelay", "1000"])
        tap("Scan receipt")
        tap("Read receipt")
        _ = app.buttons["Scan in parts"].waitForExistence(timeout: 6)
        shot("10-too-long")
        app.terminate()
        launch(["-receiptPhotos", "1", "-receiptFixture", "limit", "-receiptDelay", "1000"])
        tap("Scan receipt")
        tap("Read receipt")
        _ = app.staticTexts["That’s all the scans for today"].waitForExistence(timeout: 6)
        shot("11-limit")
    }
}
