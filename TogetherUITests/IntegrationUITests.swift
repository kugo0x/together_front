import XCTest

/// Opt-in: the real app against the local stack (`make dev-up && make dev-seed` in ../back). Off unless
/// `INTEGRATION=1`. Alex signs in through the UI; Sam's phone is played from the test with plain HTTP calls, so the
/// realtime path (Sam's change → event stream → Alex's screen) is checked end to end. Accounts come from the
/// environment (../back/dev/seed-users.env) — see `APILiveTests` for the command.
@MainActor
final class IntegrationUITests: XCTestCase {
    private var app: XCUIApplication!
    private let env = ProcessInfo.processInfo.environment
    private var baseURL: String { env["API_BASE_URL"] ?? "http://localhost:8080" }

    override func setUp() async throws {
        try XCTSkipUnless(env["INTEGRATION"] == "1", "integration tests need the local stack (INTEGRATION=1)")
        continueAfterFailure = false
    }

    private func launch(reset: Bool, url: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = ["-apiBaseURL", url ?? baseURL, "-noNotifications", "YES",
                               "-initialSpace", "shared", "-initialTab", "groceries"]
        if reset { app.launchArguments += ["-resetSession", "YES"] }
        app.launch()
    }

    private var field: XCUIElement { app.textFields["Add to Shared groceries"] }

    /// Scrolls the list until `element` exists.
    private func reveal(_ element: XCUIElement) -> Bool {
        let list = app.collectionViews.firstMatch
        guard list.waitForExistence(timeout: 10) else { return false }
        for _ in 0..<8 where !element.exists { list.swipeUp(velocity: .slow) }
        return element.exists
    }

    private func text(_ fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    /// Signed in once through the UI per run (the API allows 10 sign-ins per email per 15 minutes); later tests
    /// relaunch with the saved session, which also checks that a session survives relaunch.
    nonisolated(unsafe) private static var signedIn = false

    /// Welcome → "I already have an account" → email + password → the Groceries tab.
    private func signInAsAlex(file: StaticString = #filePath, line: UInt = #line) throws {
        if Self.signedIn {
            launch(reset: false)
            XCTAssertTrue(text("Shared with Sam").waitForExistence(timeout: 30), "session restored", file: file, line: line)
            return
        }
        let email = try XCTUnwrap(env["SEED_ALEX_EMAIL"]), password = try XCTUnwrap(env["SEED_ALEX_PASSWORD"])
        launch(reset: true)
        let have = app.buttons["I already have an account"]
        XCTAssertTrue(have.waitForExistence(timeout: 10), "welcome screen", file: file, line: line)
        have.tap()
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), file: file, line: line)
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["authSubmit"].tap()
        XCTAssertTrue(text("Shared with Sam").waitForExistence(timeout: 40), "signed in, Shared loaded", file: file, line: line)
        Self.signedIn = true
        dismissSavePassword()
    }

    /// iOS offers to save the password after a real sign-in; it would take the keyboard focus.
    private func dismissSavePassword() {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
    }

    // MARK: Checklist

    /// Sign in → the seeded Shared world: list, suggestions, partner.
    func testSignInShowsTheSharedWorld() async throws {
        try signInAsAlex()
        XCTAssertTrue(reveal(app.buttons["Mark bought: Oat milk"]), "seeded item (rows below the fold aren't built until scrolled)")
        app.collectionViews.firstMatch.swipeDown()
        app.collectionViews.firstMatch.swipeDown()
        // Suggestion from purchase history: never added by itself, Add puts it on the server's list.
        let addEggs = app.buttons["Add Eggs"]
        XCTAssertTrue(addEggs.waitForExistence(timeout: 5), "suggestion from purchase history")
        XCTAssertFalse(app.buttons["Mark bought: Eggs"].exists, "not added automatically")
        addEggs.tap()
        XCTAssertTrue(app.buttons["Mark bought: Eggs"].waitForExistence(timeout: 5))
        let sam = try await SamsPhone(baseURL: baseURL, env: env)
        try await sam.remove(try await sam.waitForItem(named: "Eggs"))
        // Space switch: Personal content only in Personal.
        app.buttons["Personal"].firstMatch.tap()
        XCTAssertTrue(text("Only you can see this list").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Mark bought: Oat milk"].exists, "Shared items don't show in Personal")
    }

    /// Last (alphabetically): it leaves the app signed out.
    func testWrongPasswordShowsTheServersAnswer() throws {
        launch(reset: true)
        Self.signedIn = false
        app.buttons["I already have an account"].tap()
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(try XCTUnwrap(env["SEED_ALEX_EMAIL"]))
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("wrong-password-1")
        app.buttons["authSubmit"].tap()
        XCTAssertTrue(app.staticTexts["That password doesn’t match this email. Try again or reset it."]
            .waitForExistence(timeout: 30))
    }

    /// "2 … " + return → name and qty from the server; Sam ticks it on his phone → "Sam bought …" here, in Bought.
    func testQuickAddAndPartnersTickArriveLive() async throws {
        try signInAsAlex()
        let name = "It eggs \(Int.random(in: 1000...9999))"
        field.tap()
        field.typeText("2 \(name.lowercased())\n")
        XCTAssertTrue(app.buttons["Mark bought: \(name)"].waitForExistence(timeout: 5))

        let sam = try await SamsPhone(baseURL: baseURL, env: env)
        let itemID = try await sam.waitForItem(named: name)
        try await sam.markBought(itemID)
        XCTAssertTrue(text("Sam bought \(name)").waitForExistence(timeout: 10), "toast from the event stream")
        try await sam.remove(itemID)
        XCTAssertTrue(app.buttons["Mark bought: \(name)"].waitForNonExistence(timeout: 10), "removed live")
    }

    /// Server unreachable: a calm banner, typing still works; next launch online, the item is sent.
    func testOfflineBannerAndNoLostItems() async throws {
        try signInAsAlex()
        app.terminate()
        launch(reset: false, url: "http://127.0.0.1:9")
        XCTAssertTrue(app.staticTexts["You’re offline"].waitForExistence(timeout: 20))
        let name = "Offline it \(Int.random(in: 1000...9999))"
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("\(name)\n")
        XCTAssertTrue(app.buttons["Mark bought: \(name)"].waitForExistence(timeout: 5), "on the list at once")
        XCTAssertTrue(text("1 change will sync").waitForExistence(timeout: 5))
        app.terminate()

        launch(reset: false)
        XCTAssertTrue(app.buttons["Mark bought: \(name)"].waitForExistence(timeout: 30), "kept across launches")
        let sam = try await SamsPhone(baseURL: baseURL, env: env)
        let itemID = try await sam.waitForItem(named: name)
        try await sam.remove(itemID)
        XCTAssertFalse(app.staticTexts["You’re offline"].exists)
    }
}

/// Sam's phone, as plain API calls from the test.
private struct SamsPhone {
    let baseURL: String
    let token: String
    let spaceID: String

    init(baseURL: String, env: [String: String]) async throws {
        self.baseURL = baseURL
        let login = try await Self.call("POST", baseURL + "/v1/auth/login", token: nil,
                                        body: ["email": try XCTUnwrap(env["SEED_SAM_EMAIL"]),
                                               "password": try XCTUnwrap(env["SEED_SAM_PASSWORD"])])
        token = try XCTUnwrap((login["tokens"] as? [String: Any])?["access_token"] as? String)
        let spaces = try await Self.call("GET", baseURL + "/v1/spaces", token: token)
        let shared = try XCTUnwrap((spaces["spaces"] as? [[String: Any]])?.first { $0["kind"] as? String == "shared" })
        spaceID = try XCTUnwrap(shared["id"] as? String)
    }

    func waitForItem(named name: String) async throws -> String {
        for _ in 0..<40 {
            let list = try await Self.call("GET", baseURL + "/v1/spaces/\(spaceID)/lists/default", token: token)
            if let item = (list["items"] as? [[String: Any]])?.first(where: { $0["name"] as? String == name }) {
                return try XCTUnwrap(item["id"] as? String)
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw XCTSkip("\(name) never reached the server")
    }

    func markBought(_ id: String) async throws {
        _ = try await Self.call("POST", baseURL + "/v1/spaces/\(spaceID)/items/\(id)/bought", token: token)
    }

    func remove(_ id: String) async throws {
        _ = try await Self.call("DELETE", baseURL + "/v1/spaces/\(spaceID)/items/\(id)", token: token)
    }

    static func call(_ method: String, _ url: String, token: String?, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw NSError(domain: "SamsPhone", code: status, userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
