import XCTest

/// Home: quick actions open the real flows with focus, sections navigate, the invite banner shows when alone.
@MainActor
final class HomeUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(_ extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-signedIn", "YES", "-initialTab", "home", "-initialSpace", "shared", "-noNotifications", "YES"] + extra
        app.launch()
    }

    /// Taps the on-screen button with this label (other tabs may hold one with the same label).
    private func tapHittable(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let matches = app.buttons.matching(identifier: label)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5), "no \(label)", file: file, line: line)
        for i in 0..<matches.count where matches.element(boundBy: i).isHittable {
            matches.element(boundBy: i).tap()
            return
        }
        XCTFail("\(label) is not on screen", file: file, line: line)
    }

    /// Scrolls until `element` exists (lists build rows lazily) and sits above the tab bar.
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 5), file: file, line: line)
        let limit = app.tabBars.firstMatch.frame.minY - 20
        for _ in 0..<8 where !element.exists || element.frame.maxY > limit {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.exists, "never scrolled into view", file: file, line: line)
    }

    func testItemQuickActionFocusesGroceryQuickAdd() {
        launch()
        tapHittable("Add grocery item")
        let field = app.textFields["Add to Shared groceries"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        expectation(for: focused, evaluatedWith: field)
        waitForExpectations(timeout: 3)
        field.typeText("2 limes\n")
        let limes = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Limes")).firstMatch
        XCTAssertTrue(limes.waitForExistence(timeout: 2))
        XCTAssertEqual(limes.value as? String, "Quantity 2")
    }

    func testTaskQuickActionOpensTheTaskSheet() {
        launch()
        tapHittable("New task")
        let title = app.textFields["Task title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.typeText("Fix the shelf")
        tapHittable("Add task")
        XCTAssertTrue(app.staticTexts["Task added"].waitForExistence(timeout: 2))
    }

    func testNoteQuickActionOpensANewNote() {
        launch()
        tapHittable("New note")
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.typeText("Paint colours")
        XCTAssertTrue(app.staticTexts["Shared with Sam — you can both edit this note."].exists)
        app.navigationBars.buttons.firstMatch.tap() // back to Notes
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Paint colours")).firstMatch
            .waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Notes"].isSelected)
    }

    func testSectionsNavigate() {
        launch()
        tapHittable("All tasks")
        XCTAssertTrue(app.tabBars.buttons["Tasks"].isSelected)

        app.tabBars.buttons["Home"].tap()
        let note = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Weekend in Gdańsk")).firstMatch
        reveal(note)
        note.tap()
        XCTAssertTrue(app.staticTexts["Shared with Sam — you can both edit this note."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Notes"].isSelected)
    }

    func testSharedHomeShowsNothingPersonal() {
        launch()
        XCTAssertTrue(app.staticTexts["Pay the internet bill"].waitForExistence(timeout: 5))
        for personal in ["Call Mum", "Protein bars", "Weekend plans", "Gift ideas for Sam"] {
            XCTAssertFalse(app.staticTexts[personal].exists, "\(personal) is Personal")
        }
    }

    func testInviteBannerWhenAloneInShared() {
        launch(["-alone", "YES"])
        XCTAssertTrue(app.staticTexts["Shared works best with two"].waitForExistence(timeout: 5))
        tapHittable("Invite")
        XCTAssertTrue(app.staticTexts["Invite your partner"].waitForExistence(timeout: 3))
        tapHittable("Not now")

        app.buttons["Personal"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Call Mum"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Shared works best with two"].exists, "no banner in Personal")
    }
}
