import CoreGraphics
import Foundation
import Testing
@testable import Together

/// Opt-in: the app's API layer against the local stack (`make dev-up && make dev-seed` in ../back). Off unless
/// `INTEGRATION=1`; the seeded accounts come from the environment (../back/dev/seed-users.env), never from the repo:
///
///     set -a; source ../back/dev/seed-users.env; set +a
///     TEST_RUNNER_INTEGRATION=1 TEST_RUNNER_API_BASE_URL=http://localhost:8080 \
///     TEST_RUNNER_SEED_ALEX_EMAIL=$SEED_ALEX_EMAIL TEST_RUNNER_SEED_ALEX_PASSWORD=$SEED_ALEX_PASSWORD \
///     TEST_RUNNER_SEED_SAM_EMAIL=$SEED_SAM_EMAIL TEST_RUNNER_SEED_SAM_PASSWORD=$SEED_SAM_PASSWORD \
///     xcodebuild test … -only-testing:TogetherTests/APILiveTests
///
/// Each test leaves the seeded world as it found it (what it adds, it removes).
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION"] == "1"), .serialized)
struct APILiveTests {
    static let env = ProcessInfo.processInfo.environment
    static let baseURL = URL(string: env["API_BASE_URL"] ?? "http://localhost:8080")!

    /// A signed-in phone: its own vault, client, store and sync.
    @MainActor
    final class Phone {
        let vault: TokenVault
        let client: APIClient
        let store: AppStore
        let toasts = ToastCenter()
        var sync: RemoteSync!
        let user: AuthUser
        var signedOut = false

        /// One login per account for the whole run: the API allows 10 sign-ins per email per 15 minutes. Phones of
        /// the same account share the token pair (it outlives the run; nothing here refreshes it).
        static var sessions: [String: AuthResult] = [:]

        init(email: String, password: String, fresh: Bool = false) async throws {
            let anonymous = APIClient(baseURL: APILiveTests.baseURL, vault: nil)
            let result: AuthResult
            if !fresh, let cached = Self.sessions[email] {
                result = cached
            } else {
                result = try await APIAuthService(client: anonymous).login(email: email, password: password)
                if !fresh { Self.sessions[email] = result }
            }
            user = result.user
            var box: Phone?
            vault = TokenVault(tokens: result.tokens,
                               rotate: { try await APIAuthService.refresh($0, baseURL: APILiveTests.baseURL) },
                               didChange: { _ in })
            client = APIClient(baseURL: APILiveTests.baseURL, vault: vault) { await MainActor.run { box?.signedOut = true } }
            store = AppStore(data: .empty)
            box = self
        }

        static func alex(fresh: Bool = false) async throws -> Phone {
            try await Phone(email: try #require(env["SEED_ALEX_EMAIL"]), password: try #require(env["SEED_ALEX_PASSWORD"]),
                            fresh: fresh)
        }

        static func sam() async throws -> Phone {
            try await Phone(email: try #require(env["SEED_SAM_EMAIL"]), password: try #require(env["SEED_SAM_PASSWORD"]))
        }

        /// Loads everything, like the app after sign-in; `stream` opens the event streams.
        func open(stream: Bool = false) async {
            sync = RemoteSync(client: client, store: store, toasts: toasts,
                              me: Person(id: user.id, name: user.displayName, tint: .alex))
            await sync.loadAll()
            if stream { sync.setForeground(true) }
        }

        func settle() async throws {
            try await APILiveTests.until("changes sent") { self.sync.isIdle }
        }

        func close() { sync?.stop() }
    }

    static func until(_ what: String, timeout: Duration = .seconds(15), _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting for \(what)")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    static func unique(_ name: String) -> String { "\(name) \(Int.random(in: 1000...9999))" }

    // MARK: Auth

    @Test func wrongPasswordIsInvalidCredentials() async throws {
        let auth = APIAuthService(client: APIClient(baseURL: Self.baseURL, vault: nil))
        await #expect(throws: AuthError.invalidCredentials) {
            try await auth.login(email: try #require(Self.env["SEED_ALEX_EMAIL"]), password: "not-the-password")
        }
    }

    /// An expired access token is refreshed once and the call retried; replaying the old refresh token ends the
    /// session.
    @Test func refreshRotatesOnceThenReplayIsRefused() async throws {
        let alex = try await Phone.alex(fresh: true) // this test ends its session
        let tokens = try #require(await alex.vault.tokens)
        var stale = tokens
        stale.accessToken = "expired.or.forged.token"
        await alex.vault.set(stale)
        let me = try await alex.client.send(.get("v1/me"), as: MeDTO.self)
        #expect(me.id == alex.user.id)
        let rotated = try #require(await alex.vault.tokens)
        #expect(rotated.refreshToken != tokens.refreshToken, "a new pair")
        #expect(!alex.signedOut)

        // The used refresh token again: the server revokes the session.
        await #expect(throws: (any Error).self) { try await APIAuthService.refresh(tokens.refreshToken, baseURL: Self.baseURL) }
        await alex.vault.set(AuthTokens(accessToken: "x", accessExpiresAt: .now, refreshToken: rotated.refreshToken,
                                        refreshExpiresAt: .distantFuture))
        await #expect(throws: APIError.signedOut) { try await alex.client.send(.get("v1/me")) }
        #expect(alex.signedOut, "the app signs out")
    }

    // MARK: Load

    @Test func loadsTheSeededWorld() async throws {
        let alex = try await Phone.alex()
        await alex.open()
        defer { alex.close() }
        let store = alex.store
        #expect(store.partner?.name == "Sam")
        #expect(store.me.id == alex.user.id)
        #expect(store.toBuy(in: .shared).contains { $0.name == "Oat milk" })
        #expect(store.bought(in: .shared).contains { $0.name == "Pasta" })
        #expect(store.suggestions(in: .shared).map(\.name).contains("Eggs"))
        #expect(store.notes(in: .shared).contains { $0.title.contains("Gdańsk") })
        #expect(!store.activeTasks(in: .shared).isEmpty)
        #expect(!store.trips(in: .shared).isEmpty)
        #expect(store.trips(in: .shared).contains { $0.total == Decimal(string: "74.2") })
        // Nothing Personal of Alex's in Shared, and the other way round.
        #expect(!store.groceries(in: .personal).isEmpty)
        let personalIDs = Set(store.groceries(in: .personal).map(\.id))
        #expect(store.groceries(in: .shared).allSatisfy { !personalIDs.contains($0.id) })
    }

    // MARK: Groceries + realtime

    /// Alex adds, ticks and removes; Sam's phone sees each step on the event stream ("Alex bought …").
    @Test func groceriesSyncBetweenPhones() async throws {
        let alex = try await Phone.alex(), sam = try await Phone.sam()
        await alex.open()
        await sam.open(stream: true)
        defer { alex.close(); sam.close() }
        try await Task.sleep(for: .milliseconds(500)) // the stream is connected

        let name = Self.unique("Integration milk")
        let item = try #require(alex.store.addItem(text: "2 \(name.lowercased())", in: .shared))
        #expect(item.qty == "2")
        try await alex.settle()
        let serverID = alex.sync.serverID(for: item.id)
        #expect(serverID != item.id, "the server's ID is known")
        #expect(alex.store.item(item.id, in: .shared) != nil, "the row keeps its local ID")

        try await Self.until("Sam sees it") { sam.store.toBuy(in: .shared).contains { $0.id == serverID } }
        #expect(sam.store.toBuy(in: .shared).first { $0.id == serverID }?.addedBy?.name == alex.user.displayName)

        alex.store.markBought(item.id, in: .shared)
        try await alex.settle()
        try await Self.until("Sam sees it bought") {
            sam.store.bought(in: .shared).contains { $0.id == serverID && $0.boughtBy?.id == alex.user.id }
        }

        // Undo (unticks on the server too).
        alex.store.unmarkBought(item.id, in: .shared)
        try await alex.settle()
        try await Self.until("Sam sees it open again") { sam.store.toBuy(in: .shared).contains { $0.id == serverID } }

        let removed = try #require(alex.store.removeItem(item.id, in: .shared))
        try await alex.settle()
        try await Self.until("Sam sees it gone") { !sam.store.groceries(in: .shared).contains { $0.id == serverID } }

        // Undo of a removal re-adds it on the server.
        alex.store.undoRemove(removed)
        try await alex.settle()
        let readded = alex.sync.serverID(for: item.id)
        try await Self.until("Sam sees it back") { sam.store.toBuy(in: .shared).contains { $0.id == readded } }
        alex.store.removeItem(item.id, in: .shared)
        try await alex.settle()
    }

    /// Changes made while the server can't be reached wait (on disk, for groceries) and go out when it's back.
    @Test func offlineChangesAreKeptAndSent() async throws {
        let alex = try await Phone.alex()
        await alex.open()
        let tokens = try #require(await alex.vault.tokens)
        alex.close()

        // The same account on a phone that can't reach the server.
        let offlineVault = TokenVault(tokens: tokens, rotate: { _ in throw APIError.offline }, didChange: { _ in })
        let offlineClient = APIClient(baseURL: URL(string: "http://127.0.0.1:9")!, vault: offlineVault)
        let store = AppStore(data: .empty)
        let me = Person(id: alex.user.id, name: alex.user.displayName, tint: .alex)
        let offline = RemoteSync(client: offlineClient, store: store, toasts: ToastCenter(), me: me)
        await offline.loadAll()
        #expect(store.connection == .offline(pending: 0))
        let name = Self.unique("Offline bread")
        store.addItem(name: name, in: .shared)
        try await Self.until("the banner counts it") { store.connection == .offline(pending: 1) }
        offline.stop()

        // Next launch, online: the item is shown and sent.
        let back = try await Phone.alex()
        await back.open()
        defer { back.close() }
        #expect(back.store.toBuy(in: .shared).contains { $0.name == name }, "still on the list")
        try await back.settle()
        let check = try await Phone.alex()
        await check.open()
        defer { check.close() }
        let saved = try #require(check.store.toBuy(in: .shared).first { $0.name == name }, "on the server")
        check.store.removeItem(saved.id, in: .shared)
        try await check.settle()
    }

    /// A change the server refuses is rolled back and explained.
    @Test func refusedChangeIsRolledBack() async throws {
        let alex = try await Phone.alex()
        await alex.open()
        defer { alex.close() }
        let ghost = GroceryItem(listID: alex.store.defaultList(for: .shared).id, name: "Ghost", addedBy: alex.store.me)
        alex.store.applyingServer { alex.store.groceryItems.insert(ghost, at: 0) } // not on the server
        alex.store.markBought(ghost.id, in: .shared)
        try await alex.settle()
        #expect(alex.store.item(ghost.id, in: .shared) == nil, "re-fetched: it isn't there")
        #expect(alex.toasts.current != nil, "a toast explains")
    }

    // MARK: Tasks

    @Test func taskCompleteAndUndoReachTheServer() async throws {
        let alex = try await Phone.alex(), sam = try await Phone.sam()
        await alex.open()
        await sam.open(stream: true)
        defer { alex.close(); sam.close() }
        try await Task.sleep(for: .milliseconds(500))
        let title = Self.unique("Integration task")
        let partner = try #require(alex.store.partner)
        let tomorrow = alex.store.today.adding(days: 1)
        let task = try #require(alex.store.createTask(
            .init(title: title, dueDay: tomorrow, repeatRule: .weekly, assignee: partner,
                  reminderAt: tomorrow.at(hour: 23, minute: 0, calendar: alex.store.calendar)),
            in: .shared))
        #expect(task.reminder?.remindAt != task.reminder?.requested, "23:00 is in quiet hours")
        try await alex.settle()
        let serverID = alex.sync.serverID(for: task.id)
        try await Self.until("Sam sees the task") { sam.store.tasks(in: .shared).contains { $0.id == serverID } }
        let seen = try #require(sam.store.tasks(in: .shared).first { $0.id == serverID })
        #expect(seen.assignee?.id == sam.user.id)
        #expect(seen.reminder.map { TimeOfDay($0.remindAt, calendar: sam.store.calendar).hour } == 8, "moved to 8:00")

        // Repeating: completing rolls the date forward, on the server.
        alex.store.completeTask(task.id, in: .shared)
        try await alex.settle()
        #expect(alex.store.task(task.id, in: .shared)?.dueDay == tomorrow.adding(days: 7))
        try await Self.until("Sam sees it rolled") {
            sam.store.tasks(in: .shared).first { $0.id == serverID }?.dueDay == tomorrow.adding(days: 7)
        }
        alex.store.reopenTask(task.id, in: .shared)
        try await alex.settle()
        #expect(alex.store.task(task.id, in: .shared)?.dueDay == tomorrow)

        alex.store.deleteTask(task.id, in: .shared)
        try await alex.settle()
        try await Self.until("Sam sees it deleted") { !sam.store.tasks(in: .shared).contains { $0.id == serverID } }
    }

    // MARK: Notes

    /// Both edit the same note: the second save conflicts (409) and is merged — my field, their other field.
    @Test func noteConflictIsMerged() async throws {
        let alex = try await Phone.alex(), sam = try await Phone.sam()
        await alex.open()
        await sam.open()
        defer { alex.close(); sam.close() }
        let note = alex.store.createNote(in: .shared, title: Self.unique("Conflict"), body: "First line")
        try await alex.settle()
        let serverID = alex.sync.serverID(for: note.id)
        await sam.sync.reload(.shared)
        let samsNote = try #require(sam.store.notes(in: .shared).first { $0.id == serverID })
        let alexNote = try #require(alex.store.note(note.id, in: .shared))

        _ = sam.store.updateNote(samsNote.id, in: .shared, title: "Sam's title", body: samsNote.body, ifMatch: samsNote.version)
        try await sam.settle()
        _ = alex.store.updateNote(alexNote.id, in: .shared, title: alexNote.title, body: "Alex's body", ifMatch: alexNote.version)
        try await alex.settle()

        let merged = try #require(alex.store.note(note.id, in: .shared))
        #expect(merged.title == "Sam's title", "their field")
        #expect(merged.body == "Alex's body", "my field")
        #expect(alex.store.noteMerges[note.id] == 1, "the editor is told")

        alex.store.deleteNote(note.id, in: .shared)
        try await alex.settle()
    }

    /// Move to Shared and its Undo, and delete + restore.
    @Test func noteMoveAndRestore() async throws {
        let alex = try await Phone.alex()
        await alex.open()
        defer { alex.close() }
        let note = alex.store.createNote(in: .personal, title: Self.unique("Private"), body: "x")
        try await alex.settle()
        let moved = try #require(alex.store.moveNote(note.id, from: .personal, to: .shared))
        try await alex.settle()
        #expect(alex.store.note(note.id, in: .shared) != nil)
        #expect(alex.toasts.current == nil, "no error")
        _ = alex.store.moveNote(note.id, from: .shared, to: moved.undo!.backTo)
        try await alex.settle()
        #expect(alex.store.note(note.id, in: .personal) != nil)

        alex.store.deleteNote(note.id, in: .personal)
        try await alex.settle()
        #expect(alex.store.restoreNote(note.id, in: .personal) != nil)
        try await alex.settle()
        await alex.sync.reload(.personal)
        #expect(alex.store.notes(in: .personal).contains { $0.title == note.title }, "restored on the server")
        alex.store.deleteNote(try #require(alex.store.notes(in: .personal).first { $0.title == note.title }).id, in: .personal)
        try await alex.settle()
    }

    // MARK: Receipts

    /// The demo recognizer reads Corner Market; confirming files a trip "via receipt".
    @Test func receiptScanAndConfirm() async throws {
        let alex = try await Phone.alex()
        await alex.open()
        defer { alex.close() }
        let recognizer = APIReceiptRecognizer(client: alex.client, spaceID: { kind in await alex.sync.spaceID(kind) })
        let photo = try ReceiptImage.jpeg(from: Self.blank())
        let scanned = try await recognizer.recognize([photo], in: .shared)
        #expect(!scanned.lines.isEmpty)
        let review = ReceiptReview(scanned: scanned, candidates: alex.store.receiptCandidates(in: .shared), now: .now)
        let tripsBefore = alex.store.trips(in: .shared).count
        let result = alex.store.confirmReceipt(review, in: .shared)
        try await alex.settle()
        #expect(alex.toasts.current == nil, "accepted")
        await alex.sync.reload(.shared)
        #expect(alex.store.trips(in: .shared).count == tripsBefore + 1)
        #expect(alex.store.trips(in: .shared).contains { $0.total == result.trip.total && $0.hasReceipt })
    }

    // MARK: Invites

    /// Two new accounts: one invites, the other joins with the code; the inviter hears about it.
    @Test func inviteAndJoin() async throws {
        let auth = APIAuthService(client: APIClient(baseURL: Self.baseURL, vault: nil))
        func newPhone(_ name: String) async throws -> (APIClient, AuthUser) {
            let email = "it-\(UUID().uuidString.prefix(8).lowercased())@together.test"
            let result = try await auth.register(email: email, password: "integration-\(UUID().uuidString)", displayName: name)
            #expect(result.isNewUser)
            let vault = TokenVault(tokens: result.tokens, rotate: { try await APIAuthService.refresh($0, baseURL: Self.baseURL) },
                                   didChange: { _ in })
            return (APIClient(baseURL: Self.baseURL, vault: vault), result.user)
        }
        let (inviterClient, inviter) = try await newPhone("Ola")
        let (joinerClient, joiner) = try await newPhone("Kuba")
        let invite = try await APIInviteService(client: inviterClient).createInvite()
        #expect(InviteCode.normalize(invite.code) == invite.code)
        let waiting = Task { try await APIInviteService(client: inviterClient).waitForJoin(invite) }
        let host = try await APIInviteService(client: joinerClient).accept(code: invite.code.lowercased())
        #expect(host.id == inviter.id && host.name == "Ola")
        let joined = try await waiting.value
        #expect(joined.id == joiner.id && joined.name == "Kuba")
        // Clean up the accounts.
        try await joinerClient.send(.delete("v1/me"))
        try await inviterClient.send(.delete("v1/me"))
    }

    static func blank() -> CGImage {
        let context = CGContext(data: nil, width: 600, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 1200))
        return context.makeImage()!
    }
}
