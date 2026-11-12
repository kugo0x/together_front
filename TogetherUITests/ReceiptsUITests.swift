import XCTest

/// Scan receipt → photos → reading → review → confirm / discard / cancel / offline, and History. No camera in
/// tests: `-receiptPhotos N` hands the sheet N blank photos, `-receiptFixture <name>[,<name>…]` makes the stand-in
/// recognizer answer like the backend would (the next fixture for each receipt of a queue).
@MainActor
final class ReceiptsUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(_ fixture: String, photos: Int = 1, separate: Bool? = nil, delay: Int = 1500) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-signedIn", "YES", "-initialTab", "groceries", "-initialSpace", "shared",
                               "-noNotifications", "YES", "-receiptFixture", fixture,
                               "-receiptPhotos", "\(photos)", "-receiptDelay", "\(delay)"]
        if let separate { app.launchArguments += ["-receiptSeparate", separate ? "YES" : "NO"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["7 to buy · Shared with Sam"].waitForExistence(timeout: 8), "list loaded")
    }

    private func tapHittable(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let matches = app.buttons.matching(identifier: label)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5), "no \(label)", file: file, line: line)
        for i in 0..<matches.count where matches.element(boundBy: i).isHittable {
            matches.element(boundBy: i).tap()
            return
        }
        XCTFail("\(label) is not on screen", file: file, line: line)
    }

    /// The list is long: scroll until the control is on screen, then tap it.
    private func scrollAndTap(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[label].firstMatch
        for _ in 0..<8 where !(button.exists && button.isHittable) { app.swipeUp() }
        XCTAssertTrue(button.isHittable, "no \(label)", file: file, line: line)
        button.tap()
    }

    /// Case-insensitive (the progress caption is shown in capitals).
    private func anyText(_ fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    /// Corner Market ticks 3 items; Biedronka matches nothing on the English list, so it's only filed.
    private func confirmShownReceipt(file: StaticString = #filePath, line: UInt = #line) {
        if text("Corner Market").exists {
            tapHittable("Mark 3 as bought", file: file, line: line)
        } else {
            XCTAssertTrue(text("Biedronka").exists, file: file, line: line)
            tapHittable("Save to history", file: file, line: line)
        }
    }

    private func text(_ fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    /// Opens the sheet on the photo of one receipt and sends it.
    private func startScan(file: StaticString = #filePath, line: UInt = #line) {
        tapHittable("Scan receipt", file: file, line: line)
        XCTAssertTrue(app.staticTexts["1 photo of this receipt"].waitForExistence(timeout: 5), "photo ready", file: file, line: line)
        tapHittable("Read receipt", file: file, line: line)
        XCTAssertTrue(app.staticTexts["Reading the receipt…"].waitForExistence(timeout: 3), "skeleton while reading",
                      file: file, line: line)
    }

    /// Corner Market: Oat milk, Tomatoes, Sourdough bread on the list; Dark chocolate extra; "GRK YGHRT" → Greek yogurt?
    func testReviewFixAndConfirm() {
        launch("corner")
        startScan()
        XCTAssertTrue(app.staticTexts["Review receipt"].waitForExistence(timeout: 6))
        XCTAssertTrue(text("Corner Market").exists)
        XCTAssertTrue(app.buttons["Mark 3 as bought"].exists)
        XCTAssertTrue(app.staticTexts["On your list"].exists)
        XCTAssertTrue(app.staticTexts["Not on your list"].exists)

        tapHittable("Greek yogurt")                       // "Did you mean Greek yogurt?"
        XCTAssertTrue(app.buttons["Mark 4 as bought"].waitForExistence(timeout: 2))
        tapHittable("Exclude Oat milk")                   // bought for someone else
        XCTAssertTrue(app.buttons["Mark 3 as bought"].waitForExistence(timeout: 2))

        tapHittable("Mark 3 as bought")
        XCTAssertTrue(app.staticTexts["3 items marked bought · 43,44 zł"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Scan another receipt"].exists)
        tapHittable("Done")

        // Bought "via receipt"; oat milk still to buy.
        XCTAssertTrue(app.buttons["Mark bought: Oat milk"].waitForExistence(timeout: 2))
        scrollAndTap("Show")
        XCTAssertTrue(text("via receipt").waitForExistence(timeout: 2))

        // The trip is in History with its total and the month line.
        scrollAndTap("History")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
        XCTAssertTrue(text("Groceries in").exists)
        XCTAssertTrue(app.staticTexts["43,44 zł"].exists)
    }

    /// A trip added twice comes out of History: from inside the trip, or with a swipe on its row.
    func testDeleteTripsFromHistory() {
        launch("corner")
        scrollAndTap("History")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
        let trips = app.buttons.matching(NSPredicate(format: "label CONTAINS 'zł'"))
        XCTAssertTrue(trips.firstMatch.waitForExistence(timeout: 3))
        let count = trips.count

        trips.firstMatch.tap()
        scrollAndTap("Delete trip")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
        XCTAssertEqual(trips.count, count - 1)

        trips.firstMatch.swipeLeft()
        tapHittable("Delete")
        XCTAssertEqual(trips.count, count - 2)
    }

    func testDiscardChangesNothing() {
        launch("corner")
        startScan()
        XCTAssertTrue(app.staticTexts["Review receipt"].waitForExistence(timeout: 6))
        tapHittable("Discard")
        XCTAssertFalse(app.staticTexts["Review receipt"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["7 to buy · Shared with Sam"].exists, "nothing applied")
        XCTAssertFalse(text("Corner Market").exists)
    }

    func testCancelWhileReadingGoesBackToThePhotos() {
        launch("corner", delay: 4000)
        startScan()
        tapHittable("Cancel")
        XCTAssertTrue(app.staticTexts["1 photo of this receipt"].waitForExistence(timeout: 3), "the photo is kept")
        XCTAssertTrue(app.staticTexts["The photo is sent to read the receipt and isn’t kept."].exists)
        XCTAssertFalse(app.staticTexts["Review receipt"].waitForExistence(timeout: 5), "the cancelled read never lands")
    }

    func testOfflineOffersRetry() {
        launch("offline")
        startScan()
        XCTAssertTrue(app.staticTexts["You’re offline"].waitForExistence(timeout: 6))
        tapHittable("Try again")
        XCTAssertTrue(app.staticTexts["Reading the receipt…"].waitForExistence(timeout: 2), "the same photo is sent again")
        XCTAssertTrue(app.staticTexts["You’re offline"].waitForExistence(timeout: 6))
        tapHittable("Use another photo")
        XCTAssertTrue(app.buttons["Choose from Photos"].waitForExistence(timeout: 2))
    }

    func testUnreadablePhotoAsksForAnother() {
        launch("unreadable")
        startScan()
        XCTAssertTrue(app.staticTexts["Couldn’t read this receipt"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["Try again"].exists, "retrying the same photo won't help")
        tapHittable("Try another photo")
        XCTAssertTrue(app.buttons["Choose from Photos"].waitForExistence(timeout: 2))
    }

    /// A long receipt in two photos: reorder, remove, add — one call, one review, one trip.
    func testTwoPhotosOfOneReceipt() {
        launch("corner", photos: 2, separate: false)
        tapHittable("Scan receipt")
        XCTAssertTrue(app.staticTexts["2 photos of this receipt, top to bottom"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add another photo of this receipt"].exists)
        XCTAssertTrue(app.buttons["Add from Photos"].exists)
        XCTAssertFalse(app.buttons["Move photo 1 up"].isEnabled)
        tapHittable("Move photo 1 down")
        XCTAssertTrue(app.buttons["Remove photo 2"].exists)

        tapHittable("Read receipt")
        XCTAssertTrue(app.staticTexts["Reading the receipt…"].waitForExistence(timeout: 3))
        XCTAssertFalse(text("Receipt 1 of").exists, "one receipt, no queue")
        XCTAssertTrue(app.staticTexts["Review receipt"].waitForExistence(timeout: 6))
        tapHittable("Mark 3 as bought")
        XCTAssertTrue(app.staticTexts["3 items marked bought · 43,44 zł"].waitForExistence(timeout: 3))
        tapHittable("Done")

        scrollAndTap("History")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
        XCTAssertTrue(text("4 trips with receipts").exists, "two photos, one trip (3 in the mock November)")
    }

    /// Two different receipts: read together, reviewed one by one, a trip each.
    func testQueueOfTwoReceipts() {
        launch("corner,biedronka", photos: 2)
        tapHittable("Scan receipt")
        XCTAssertTrue(app.buttons["These are parts of one receipt"].waitForExistence(timeout: 5), "asked, never guessed")
        tapHittable("Separate receipts")

        // Both are read at once, so either may come first.
        XCTAssertTrue(anyText("Receipt 1 of 2").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Review receipt"].waitForExistence(timeout: 6))
        confirmShownReceipt()
        XCTAssertTrue(anyText("Receipt 2 of 2").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Review receipt"].waitForExistence(timeout: 1), "already read while the first was reviewed")
        XCTAssertTrue(app.buttons["Skip this receipt"].exists)
        confirmShownReceipt()

        XCTAssertTrue(app.staticTexts["2 receipts saved · 3 items marked bought"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Scan another receipt"].exists)
        tapHittable("Done")
        scrollAndTap("History")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
        XCTAssertTrue(text("5 trips with receipts").exists, "a trip per receipt")
        XCTAssertTrue(text("Corner Market").exists)
        XCTAssertTrue(text("Biedronka").exists)
    }

    /// `total_matches: false` — the review asks to check the prices.
    func testLinesThatDontAddUpAskToCheckPrices() {
        launch("mismatch")
        startScan()
        XCTAssertTrue(app.staticTexts["Review receipt"].waitForExistence(timeout: 6))
        XCTAssertTrue(text("don’t add up to the receipt’s total (47,44 zł)").exists)
        XCTAssertTrue(app.buttons["Choose from your list"].exists, "the chips wrap instead of being cut off")
    }

    /// `receipt_too_long`: back to the photos to add the rest of the receipt.
    func testTooLongReceiptIsScannedInParts() {
        launch("tooLong")
        startScan()
        XCTAssertTrue(app.staticTexts["This receipt is too long for one go"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["Try again"].exists)
        tapHittable("Scan in parts")
        XCTAssertTrue(app.staticTexts["1 photo of this receipt"].waitForExistence(timeout: 3), "the photo is kept")
        XCTAssertTrue(app.staticTexts["Add another photo of this receipt"].exists)
    }

    /// 429 — no retry and no "another photo" until the limit resets.
    func testDailyLimit() {
        launch("limit")
        startScan()
        XCTAssertTrue(app.staticTexts["That’s all the scans for today"].waitForExistence(timeout: 6))
        XCTAssertTrue(text("in about 6 hours").exists)
        XCTAssertFalse(app.buttons["Try again"].exists)
        XCTAssertFalse(app.buttons["Try another photo"].exists)
        tapHittable("Cancel")
        XCTAssertTrue(app.staticTexts["7 to buy · Shared with Sam"].waitForExistence(timeout: 3))
    }
}
