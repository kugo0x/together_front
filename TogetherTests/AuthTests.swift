import Foundation
import Testing
@testable import Together

// MARK: - Validation

struct AuthValidationTests {
    @Test(arguments: ["alex@example.com", " sam@together.app ", "a.b+c@mail.co.uk"])
    func validEmails(_ email: String) {
        #expect(AuthValidation.isValidEmail(email))
    }

    @Test(arguments: ["", "alex", "alex@", "alex@example", "@example.com", "al ex@example.com", "alex@exa mple.com"])
    func invalidEmails(_ email: String) {
        #expect(!AuthValidation.isValidEmail(email))
    }

    @Test func passwordNeedsEightToTwoHundredFiftySix() {
        #expect(!AuthValidation.isValidPassword("1234567"))
        #expect(AuthValidation.isValidPassword("12345678"))
        #expect(AuthValidation.isValidPassword(String(repeating: "a", count: 256)))
        #expect(!AuthValidation.isValidPassword(String(repeating: "a", count: 257)))
    }

    @Test func namesAreTrimmedAndCapped() {
        #expect(AuthValidation.cleanName("  Robin \n") == "Robin")
        #expect(AuthValidation.cleanName("   ") == nil)
        #expect(AuthValidation.cleanName(String(repeating: "x", count: 80))?.count == 50)
    }

    @Test func errorCopy() {
        #expect(AuthError.invalidCredentials.message == "That password doesn’t match this email. Try again or reset it.")
        #expect(AuthError.cancelled.message == nil)
    }
}

// MARK: - Invites

struct InviteTests {
    @Test("Codes are case-insensitive and the prefix is optional", arguments: ["TGT-7KQ2", "tgt-7kq2", "tgt7kq2", "7KQ2", " TGT 7KQ2 "])
    func normalize(_ input: String) {
        #expect(InviteCode.normalize(input) == "TGT-7KQ2")
    }

    @Test(arguments: ["", "TGT-7KQ", "TGT-7KQ22", "hello", "TGT-ŁÓDŹ"])
    func notACode(_ input: String) {
        #expect(InviteCode.normalize(input) == nil)
    }

    @Test func createdInvitesLookLikeTheAPI() async throws {
        let invite = try await FakeInviteService().createInvite()
        #expect(invite.code.range(of: #"^TGT-[0-9A-Z]{4}$"#, options: .regularExpression) != nil)
        #expect(invite.link.absoluteString == "https://together.app/invite/\(invite.code)")
    }

    @Test func acceptingByCode() async throws {
        let service = FakeInviteService()
        #expect(try await service.accept(code: "tgt7kq2") == .sam)
        await #expect(throws: InviteError.invalidCode) { try await service.accept(code: "nop") }
        await #expect(throws: InviteError.notFound) { try await service.accept(code: "TGT-0000") }
    }

    @Test func partnerJoinsAfterTheLinkIsShared() async throws {
        let service = FakeInviteService(joinDelay: .milliseconds(10))
        let invite = try await service.createInvite()
        #expect(try await service.waitForJoin(invite) == .sam)
    }
}

// MARK: - Keychain

struct KeychainTests {
    @Test func inMemoryKeychain() throws {
        let keychain = InMemoryKeychain()
        #expect(try keychain.data(for: "k") == nil)
        try keychain.set(Data("one".utf8), for: "k")
        try keychain.set(Data("two".utf8), for: "k")
        #expect(try keychain.data(for: "k") == Data("two".utf8))
        try keychain.remove("k")
        #expect(try keychain.data(for: "k") == nil)
        try keychain.remove("k") // removing nothing is fine
    }

    /// The real Keychain, in the simulator's test host, under a throwaway service name.
    @Test func systemKeychainRoundTrip() throws {
        let keychain = SystemKeychain(service: "app.together.tests.\(UUID().uuidString)")
        defer { try? keychain.remove("session") }
        #expect(try keychain.data(for: "session") == nil)
        try keychain.set(Data("a".utf8), for: "session")
        try keychain.set(Data("b".utf8), for: "session") // update, not duplicate
        #expect(try keychain.data(for: "session") == Data("b".utf8))
        try keychain.remove("session")
        #expect(try keychain.data(for: "session") == nil)
    }
}

// MARK: - Session state machine

@MainActor
struct SessionTests {
    let keychain = InMemoryKeychain()
    let service = FakeAuthService(delay: .zero)

    func makeSession() -> Session { Session(service: service, keychain: keychain) }

    @Test func startsSignedOut() {
        #expect(makeSession().state == .signedOut)
    }

    @Test func signUpThenNameThenSolo() async throws {
        let session = makeSession()
        try await session.register(email: "Robin@Example.com", password: "password1")
        #expect(session.state == .onboarding(.name))
        #expect(session.user?.email == "robin@example.com")

        try await session.setName("  Robin ")
        #expect(session.state == .onboarding(.share))
        #expect(session.user?.displayName == "Robin")

        session.finishOnboarding(.solo)
        #expect(session.state == .signedIn)
        #expect(session.arrival == .solo)
    }

    @Test func onboardingResumesAfterARelaunch() async throws {
        try await makeSession().register(email: "robin@example.com", password: "password1")
        #expect(makeSession().state == .onboarding(.name))
    }

    @Test func signedInSurvivesARelaunch() async throws {
        let session = makeSession()
        try await session.login(email: "alex@example.com", password: FakeAuthService.alexPassword)
        #expect(session.state == .signedIn, "an existing account with a name skips onboarding")

        let relaunched = makeSession()
        #expect(relaunched.state == .signedIn)
        #expect(relaunched.user == FakeAuthService.alex)
    }

    @Test func wrongPasswordStaysSignedOut() async throws {
        let session = makeSession()
        await #expect(throws: AuthError.invalidCredentials) {
            try await session.login(email: "alex@example.com", password: "wrongpass1")
        }
        #expect(session.state == .signedOut)
        #expect(!session.isBusy)
        #expect(try keychain.data(for: Session.keychainKey) == nil)
    }

    @Test func emailTaken() async {
        await #expect(throws: AuthError.emailTaken) {
            try await makeSession().register(email: "ALEX@example.com", password: "password1")
        }
    }

    @Test func logOutClearsTheKeychain() async throws {
        let session = makeSession()
        try await session.login(email: "alex@example.com", password: FakeAuthService.alexPassword)
        await session.logout()
        #expect(session.state == .signedOut)
        #expect(session.user == nil)
        #expect(try keychain.data(for: Session.keychainKey) == nil)
        #expect(makeSession().state == .signedOut)
    }

    @Test func deleteAccountSignsOutAndRemovesTheAccount() async throws {
        let session = makeSession()
        try await session.register(email: "robin@example.com", password: "password1")
        try await session.setName("Robin")
        session.finishOnboarding(.solo)
        try await session.deleteAccount()
        #expect(session.state == .signedOut)
        await #expect(throws: AuthError.invalidCredentials) {
            try await session.login(email: "robin@example.com", password: "password1")
        }
    }

    @Test func appleSignInIsNewOnceThenKnown() async throws {
        let session = makeSession()
        try await session.signInWithApple(identityToken: "apple-token", nonce: "n", displayName: "Robin")
        #expect(session.state == .onboarding(.name))
        #expect(session.user?.displayName == "Robin")
        #expect(session.user?.providers == [.apple])
        try await session.setName("Robin")
        session.finishOnboarding(.invite)
        await session.logout()

        try await session.signInWithApple(identityToken: "apple-token", nonce: "n2", displayName: nil)
        #expect(session.state == .signedIn)
    }

    @Test func tokensAreNeverInUserDefaults() async throws {
        let session = makeSession()
        try await session.login(email: "alex@example.com", password: FakeAuthService.alexPassword)
        let defaults = UserDefaults.standard.dictionaryRepresentation().description
        #expect(!defaults.contains("fake-access"))
        #expect(!defaults.contains("fake-refresh"))
        #expect(try keychain.data(for: Session.keychainKey) != nil)
    }

    @Test func blankNameIsRejected() async throws {
        let session = makeSession()
        try await session.register(email: "robin@example.com", password: "password1")
        await #expect(throws: AuthError.validationFailed(field: "display_name")) { try await session.setName("  ") }
        #expect(session.state == .onboarding(.name))
    }
}

// MARK: - Store: membership and notification settings

@MainActor
struct SettingsStoreTests {
    @Test func leavingSharedKeepsPersonalOnly() {
        let store = AppStore(data: .make())
        let personal = (store.groceries(in: .personal).count, store.tasks(in: .personal).count, store.notes(in: .personal).count)
        store.leaveShared()
        #expect(store.partner == nil)
        #expect(store.groceries(in: .shared).isEmpty)
        #expect(store.tasks(in: .shared).isEmpty)
        #expect(store.notes(in: .shared).isEmpty)
        #expect(store.suggestions(in: .shared).isEmpty)
        #expect(store.home(in: .shared).showInvite)
        #expect((store.groceries(in: .personal).count, store.tasks(in: .personal).count, store.notes(in: .personal).count) == personal)
    }

    @Test func joiningAPartner() {
        let store = AppStore(data: .make())
        store.leaveShared()
        store.joinPartner(.sam)
        #expect(store.partner == .sam)
        #expect(!store.home(in: .shared).showInvite)
    }

    @Test func turningTaskRemindersOffCancelsAndOnRestores() throws {
        let notifications = FakeNotifications()
        let now = TaskStoreTests.now
        let store = AppStore(data: .make(now: now, calendar: warsaw), clock: { now }, calendar: warsaw, notifier: notifications)
        let task = try #require(store.createTask(
            .init(title: "Call the plumber", dueDay: day(2026, 11, 10), assignee: .alex, reminderAt: instant(2026, 11, 10, 9)),
            in: .shared
        ))
        #expect(notifications.pending[task.id.uuidString] != nil)
        store.notificationPrefs.taskReminders = false
        #expect(notifications.pending.isEmpty)
        // Back on: every one of my future reminders is scheduled again (including the mock "Pay the internet bill").
        store.notificationPrefs.taskReminders = true
        #expect(notifications.pending[task.id.uuidString]?.fireAt == instant(2026, 11, 10, 9))
        #expect(notifications.pending.values.allSatisfy { $0.fireAt > now })
    }
}
