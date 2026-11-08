import XCTest

/// End-to-end checks of the Groceries tab that unit tests can't cover: keyboard focus, swipes, the toast.
@MainActor
final class GroceriesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-initialTab", "groceries", "-activeSpace", "shared"]
        app.launch()
    }

    private var field: XCUIElement { app.textFields["Add to Shared groceries"] }

    /// A grocery row (its accessibility element combines name and note; the quantity is its value).
    private func row(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", name, name + ", "))
            .firstMatch
    }

    /// Scrolls the list until `element` is in the visible part above the QuickAdd bar.
    private func reveal(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let list = app.collectionViews.firstMatch
        let limit = field.frame.minY - 20
        for _ in 0..<6 where element.frame.maxY > limit {
            list.swipeUp(velocity: .slow)
        }
    }

    func testQuickAddParsesQuantitiesAndKeepsFocus() {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("1 kg apples\n500 g coffee beans\n3x eggs\n")

        XCTAssertTrue(row("Apples").waitForExistence(timeout: 2))
        XCTAssertEqual(row("Apples").value as? String, "Quantity 1 kg")
        XCTAssertEqual(row("Coffee beans").value as? String, "Quantity 500 g")
        XCTAssertEqual(row("Eggs").value as? String, "Quantity 3")
        XCTAssertEqual(field.value as? String, "Add to Shared groceries", "field is cleared (placeholder shows)")
        XCTAssertTrue(field.value(forKey: "hasKeyboardFocus") as? Bool ?? false, "focus stays in the field")
    }

    func testCheckingShowsUndoToastAndUndoRestores() {
        let check = app.buttons["Mark bought: Tomatoes"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        check.tap()

        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2), "toast with Undo appears")
        XCTAssertTrue(app.staticTexts["Tomatoes bought"].exists)
        XCTAssertFalse(app.buttons["Mark bought: Tomatoes"].exists)

        undo.tap()
        XCTAssertTrue(app.buttons["Mark bought: Tomatoes"].waitForExistence(timeout: 2), "back in To buy")
    }

    func testSwipeToDeleteAndUndo() {
        let bread = app.buttons["Mark bought: Sourdough bread"]
        reveal(bread)
        row("Sourdough bread").swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 2), "swipe reveals Delete")
        delete.tap()

        XCTAssertTrue(app.staticTexts["Sourdough bread removed"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Mark bought: Sourdough bread"].exists)
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["Mark bought: Sourdough bread"].waitForExistence(timeout: 2))
    }

    func testSuggestionAddAndSkip() {
        let addEggs = app.buttons["Add Eggs"]
        XCTAssertTrue(addEggs.waitForExistence(timeout: 5))
        addEggs.tap()
        XCTAssertTrue(app.staticTexts["Eggs added to the list"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Mark bought: Eggs"].exists)

        app.buttons["Not this week: Bananas"].tap()
        XCTAssertTrue(app.staticTexts["Skipped Bananas this week"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Add Bananas"].exists)
    }

    func testEditItem() {
        let spinach = row("Spinach")
        reveal(app.buttons["Mark bought: Spinach"])
        spinach.tap()

        let qty = app.textFields["Quantity"]
        XCTAssertTrue(qty.waitForExistence(timeout: 2))
        qty.tap()
        qty.typeText("200 g")
        app.buttons["Save"].tap()

        XCTAssertTrue(row("Spinach").waitForExistence(timeout: 2))
        XCTAssertEqual(row("Spinach").value as? String, "Quantity 200 g")
    }
}
