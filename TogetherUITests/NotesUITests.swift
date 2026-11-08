import XCTest

/// Notes: search stays in the space, Move to Shared → Undo, delete → Undo, and writing a note with a checklist
/// with the keyboard up.
@MainActor
final class NotesUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(_ space: String) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-initialTab", "notes", "-initialSpace", space, "-noNotifications", "YES"]
        app.launch()
    }

    /// A note row (the row is one button whose label starts with the title).
    private func row(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// The on-screen one when several buttons share a label (toolbar vs sheet, list vs keyboard bar).
    private func tapHittable(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let matches = app.buttons.matching(identifier: label)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 3), "no \(label)", file: file, line: line)
        for i in 0..<matches.count where matches.element(boundBy: i).isHittable {
            matches.element(boundBy: i).tap()
            return
        }
        XCTFail("\(label) is not on screen (hidden by the keyboard?)", file: file, line: line)
    }

    private var searchField: XCUIElement {
        let field = app.searchFields["Search notes"]
        if !field.exists { app.collectionViews.firstMatch.swipeDown(velocity: .slow) }
        return field
    }

    func testSearchStaysInTheActiveSpace() {
        launch("shared")
        XCTAssertTrue(row("Weekend in Gdańsk").waitForExistence(timeout: 5))
        let field = searchField
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("gift")
        XCTAssertTrue(row("Gift ideas for Mum’s birthday").waitForExistence(timeout: 2))
        XCTAssertFalse(row("Gift ideas for Sam").exists, "a Personal note never shows in Shared search")
        XCTAssertFalse(row("Weekend in Gdańsk").exists)

        field.typeText(" zzz")
        XCTAssertTrue(app.staticTexts["No notes match “gift zzz”"].waitForExistence(timeout: 2))
    }

    func testMoveToSharedAndUndo() {
        launch("personal")
        let note = row("Weekend plans")
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        XCTAssertTrue(app.staticTexts["Private — only you can see this note."].waitForExistence(timeout: 3))

        tapHittable("Move to Shared")
        XCTAssertTrue(app.staticTexts["Move to Shared?"].waitForExistence(timeout: 3))
        tapHittable("Move to Shared")

        XCTAssertTrue(app.staticTexts["Shared with Sam — you can both edit this note."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Moved to Shared"].exists)
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["Private — only you can see this note."].waitForExistence(timeout: 3))
    }

    func testDeleteAndUndo() {
        launch("shared")
        let note = row("Wi‑Fi and building info")
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        tapHittable("Delete note")
        XCTAssertTrue(app.staticTexts["Note deleted"].waitForExistence(timeout: 3))
        XCTAssertFalse(row("Wi‑Fi and building info").exists)
        app.buttons["Undo"].tap()
        XCTAssertTrue(row("Wi‑Fi and building info").waitForExistence(timeout: 3))
    }

    func testNewNoteWithChecklistWhileTyping() {
        launch("shared")
        let new = app.buttons["New note"]
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()

        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.typeText("Packing\n")                 // return moves on to the body
        app.textFields["Note"].typeText("For the trip")
        tapHittable("Add checklist item")           // reachable with the keyboard up
        app.textFields["Checklist item"].firstMatch.typeText("Passport\n")
        XCTAssertTrue(app.textFields.matching(identifier: "Checklist item").element(boundBy: 1).waitForExistence(timeout: 2),
                      "return adds the next line")
        app.typeText("Chargers")
        tapHittable("Done")

        XCTAssertTrue(app.buttons["Tick Passport"].waitForExistence(timeout: 2))
        app.buttons["Tick Passport"].tap()
        XCTAssertTrue(app.buttons["Untick Passport"].waitForExistence(timeout: 2))

        app.navigationBars.buttons.firstMatch.tap()  // back to Notes
        XCTAssertTrue(row("Packing").waitForExistence(timeout: 3))
    }
}
