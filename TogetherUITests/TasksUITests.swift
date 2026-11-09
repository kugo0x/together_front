import XCTest

/// Create → complete → Undo on the Tasks tab, and the reminder preview in the task sheet.
@MainActor
final class TasksUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-signedIn", "YES", "-initialTab", "tasks", "-initialSpace", "shared", "-noNotifications", "YES"]
        // Fallback: if a notification permission alert ever shows, dismiss it instead of blocking the test.
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            for label in ["Don’t Allow", "Don't Allow", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
    }

    /// Taps the sheet's primary action, which must be reachable with the keyboard up.
    private func tapAddTask() {
        let add = app.buttons["Add task"]
        XCTAssertTrue(add.waitForExistence(timeout: 2))
        XCTAssertTrue(add.isHittable, "Add task stays above the keyboard")
        add.tap()
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
        tapAddTask()
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
        tapAddTask()
        XCTAssertTrue(app.staticTexts["Reminder set for Tomorrow 9:00"].waitForExistence(timeout: 2))
    }

    func testAnyoneHasNoReminder() {
        newTask("Defrost the fridge")
        app.buttons["Tomorrow"].tap()
        XCTAssertFalse(app.staticTexts["Remind me"].exists)
        app.buttons["Sam"].tap()
        XCTAssertTrue(app.staticTexts["Remind Sam"].waitForExistence(timeout: 2))
    }

    /// A time inside the receiver's quiet hours shows the warning and is saved as 8:00 next morning.
    func testQuietHoursWarningAndShiftToEight() {
        newTask("Return the parcel\n") // return closes the keyboard so the reminder section is visible
        XCTAssertEqual(app.textFields["Task title"].value as? String, "Return the parcel", "return isn't a line break")
        app.buttons["Sam"].tap()
        app.buttons["Today"].tap()
        let pickTime = app.buttons["Pick time"]
        XCTAssertTrue(pickTime.waitForExistence(timeout: 2))
        pickTime.tap()
        setTime(hour: 23, minute: 0)

        let warning = app.staticTexts["That’s in Sam’s quiet hours (22:00–8:00). It will arrive at 8:00."]
        XCTAssertTrue(warning.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Sam will get this · Tomorrow 8:00"].exists)
        for _ in 0..<4 where !warning.isHittable {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(warning.isHittable, "warning is on screen")
        attachScreenshot("quiet-hours-\(XCUIDevice.shared.appearance == .dark ? "dark" : "light")")

        tapAddTask()
        XCTAssertTrue(app.staticTexts["Sam will be reminded Tomorrow 8:00"].waitForExistence(timeout: 2))
    }

    func testQuietHoursWarningDark() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        testQuietHoursWarningAndShiftToEight()
    }

    /// Opens the compact time picker and spins its wheels (12- or 24-hour, depending on the region).
    private func setTime(hour: Int, minute: Int) {
        let picker = app.datePickers.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 2))
        picker.tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.firstMatch.waitForExistence(timeout: 2))
        if wheels.count == 3 {
            wheels.element(boundBy: 0).adjust(toPickerWheelValue: String((hour + 11) % 12 + 1))
            wheels.element(boundBy: 1).adjust(toPickerWheelValue: String(format: "%02d", minute))
            wheels.element(boundBy: 2).adjust(toPickerWheelValue: hour < 12 ? "AM" : "PM")
        } else {
            wheels.element(boundBy: 0).adjust(toPickerWheelValue: String(format: "%02d", hour))
            wheels.element(boundBy: 1).adjust(toPickerWheelValue: String(format: "%02d", minute))
        }
        // Close the wheel popover.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
