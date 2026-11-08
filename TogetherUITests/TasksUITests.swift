import XCTest

/// Create → complete → Undo on the Tasks tab, and the reminder preview in the task sheet.
@MainActor
final class TasksUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-initialTab", "tasks", "-activeSpace", "shared", "-noNotifications", "YES"]
        app.launch()
    }

    /// Scrolls until `element` is above the tab bar.
    private func reveal(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let limit = app.tabBars.firstMatch.frame.minY - 20
        for _ in 0..<6 where element.frame.maxY > limit {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
    }

    private func newTask(_ title: String) {
        let new = app.buttons["New task"]
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        let field = app.textFields["Task title"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText(title)
    }

    func testCreateCompleteUndo() {
        newTask("Water the plants")
        app.buttons["Add task"].tap()
        XCTAssertTrue(app.staticTexts["Task added"].waitForExistence(timeout: 2))

        let check = app.buttons["Complete Water the plants"]
        reveal(check)
        check.tap()
        XCTAssertTrue(app.staticTexts["Task done"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Reopen Water the plants"].exists, "moved to Done")

        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["Complete Water the plants"].waitForExistence(timeout: 2), "back in To do")
    }

    func testRepeatingTaskRollsForward() {
        let check = app.buttons["Complete Pay the internet bill"]
        reveal(check)
        check.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Done · next one")).firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Complete Pay the internet bill"].exists, "a repeating task stays in To do")
    }

    func testReminderPreviewForMe() {
        newTask("Return the parcel")
        app.buttons["Me"].tap()
        app.buttons["Tomorrow"].tap()
        XCTAssertTrue(app.staticTexts["Remind me"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["You’ll get this · Tomorrow 9:00"].exists)
        app.buttons["Add task"].tap()
        XCTAssertTrue(app.staticTexts["Reminder set for Tomorrow 9:00"].waitForExistence(timeout: 2))
    }

    func testAnyoneHasNoReminder() {
        newTask("Defrost the fridge")
        app.buttons["Tomorrow"].tap()
        XCTAssertFalse(app.staticTexts["Remind me"].exists)
        app.buttons["Sam"].tap()
        XCTAssertTrue(app.staticTexts["Remind Sam"].waitForExistence(timeout: 2))
    }
}
