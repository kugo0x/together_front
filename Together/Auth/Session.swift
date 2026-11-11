import Foundation
import Observation

/// Who is signed in and how far through onboarding they are. The root view switches on `state`:
/// signed out → welcome / auth, onboarding → name → share, signed in → the app shell.
///
/// The session (tokens, user, onboarding step) is saved in the Keychain, so it survives relaunches.
@MainActor
@Observable
final class Session {
    enum OnboardingStep: String, Codable, Sendable {
        /// "What should we call you?"
        case name
        /// "Share with someone?" — invite or just me.
        case share
    }

    enum State: Equatable {
        case signedOut
        case onboarding(OnboardingStep)
        case signedIn
    }

    private struct Stored: Codable {
        var user: AuthUser
        var tokens: AuthTokens
        var onboarding: OnboardingStep?
    }

    static let keychainKey = "session"

    private(set) var state: State = .signedOut
    private(set) var user: AuthUser?
    /// A request in flight (buttons show "Creating account…").
    private(set) var isBusy = false
    /// How onboarding ended, for the shell to act on once when it appears.
    enum Arrival: Equatable {
        /// "Just me for now" — Shared starts empty, with the invite banner.
        case solo
        /// "Invite your partner" — the invite sheet opens.
        case invite
        /// Joined someone's Shared space with their code.
        case joined(Person)
    }

    /// Set by `finishOnboarding`; the shell takes it (and clears it).
    var arrival: Arrival?

    @ObservationIgnored private(set) var tokens: AuthTokens?
    @ObservationIgnored private let service: AuthService
    @ObservationIgnored private let keychain: KeychainStore
    /// Holds the tokens the API client sends (signed in against the API); `nil` with the fakes.
    @ObservationIgnored var vault: TokenVault?
    /// Why the session ended on its own (refresh token expired or revoked) — the welcome screen says so once.
    var endedMessage: String?

    init(service: AuthService, keychain: KeychainStore) {
        self.service = service
        self.keychain = keychain
        restore()
    }

    // MARK: Sign in

    func register(email: String, password: String) async throws {
        try await run { try await self.service.register(email: email, password: password, displayName: nil) }
    }

    func login(email: String, password: String) async throws {
        try await run { try await self.service.login(email: email, password: password) }
    }

    func signInWithApple(identityToken: String, nonce: String, displayName: String?) async throws {
        try await run {
            try await self.service.signInWithApple(identityToken: identityToken, nonce: nonce, displayName: displayName)
        }
    }

    func signInWithGoogle(idToken: String, nonce: String) async throws {
        try await run { try await self.service.signInWithGoogle(idToken: idToken, nonce: nonce) }
    }

    func forgotPassword(email: String) async throws {
        try await service.forgotPassword(email: email)
    }

    // MARK: Onboarding

    /// Step 1: the name. Saved to the profile, then on to "Share with someone?".
    func setName(_ name: String) async throws {
        guard let name = AuthValidation.cleanName(name) else { throw AuthError.validationFailed(field: "display_name") }
        try await rename(to: name)
        if case .onboarding = state { move(to: .onboarding(.share)) }
    }

    /// Step 2 done: invited someone, joined with a code, or "Just me for now".
    func finishOnboarding(_ arrival: Arrival) {
        guard case .onboarding = state else { return }
        self.arrival = arrival
        move(to: .signedIn)
    }

    /// Settings → name.
    func rename(to name: String) async throws {
        guard let tokens, let clean = AuthValidation.cleanName(name) else { return }
        user = try await service.updateDisplayName(clean, tokens: tokens)
        save()
    }

    // MARK: Sign out

    func logout() async {
        await willSignOut?()
        if let tokens { try? await service.logout(tokens: tokens) }
        clear()
    }

    /// Runs before signing out while the session still works (forget this phone's push token).
    @ObservationIgnored var willSignOut: (() async -> Void)?

    func deleteAccount() async throws {
        if let tokens { try await service.deleteAccount(tokens: tokens) }
        clear()
    }

    /// Starts signed in without a network call — UI tests and screenshots (`-signedIn YES`).
    func adopt(_ result: AuthResult) {
        apply(result)
    }

    // MARK: Private

    private func run(_ call: @escaping () async throws -> AuthResult) async throws {
        isBusy = true
        defer { isBusy = false }
        let result = try await call()
        await vault?.set(result.tokens)
        apply(result)
    }

    /// The API client rotated the tokens (or found the session over): store the new pair at once — the old
    /// refresh token no longer works.
    func tokensRotated(_ fresh: AuthTokens?) {
        guard let fresh else { return signedOutByServer() }
        tokens = fresh
        save()
    }

    /// A 401 that a refresh couldn't fix: back to the welcome screen, saying why.
    func signedOutByServer() {
        guard state != .signedOut else { return }
        endedMessage = "You’ve been signed out. Sign in again to continue."
        clear()
    }

    /// Picks up profile changes made elsewhere (the name, from the other phone).
    func refreshUser(_ user: AuthUser) {
        guard self.user != nil else { return }
        self.user = user
        save()
    }

    private func apply(_ result: AuthResult) {
        user = result.user
        tokens = result.tokens
        // New accounts (and anyone still without a name) go through onboarding.
        let needsName = result.isNewUser || result.user.displayName.isEmpty
        move(to: needsName ? .onboarding(.name) : .signedIn)
    }

    private func move(to state: State) {
        self.state = state
        save()
    }

    private func save() {
        guard let user, let tokens else { return }
        let onboarding: OnboardingStep? = if case .onboarding(let step) = state { step } else { nil }
        if let data = try? JSONEncoder().encode(Stored(user: user, tokens: tokens, onboarding: onboarding)) {
            try? keychain.set(data, for: Self.keychainKey)
        }
    }

    /// The tokens a previous launch saved, before a `Session` exists (the API client starts with them).
    static func storedTokens(in keychain: KeychainStore) -> AuthTokens? {
        guard let data = try? keychain.data(for: keychainKey) else { return nil }
        return (try? JSONDecoder().decode(Stored.self, from: data))?.tokens
    }

    private func restore() {
        guard let data = try? keychain.data(for: Self.keychainKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        user = stored.user
        tokens = stored.tokens
        state = stored.onboarding.map(State.onboarding) ?? .signedIn
    }

    private func clear() {
        try? keychain.remove(Self.keychainKey)
        user = nil
        tokens = nil
        state = .signedOut
        if let vault { Task { await vault.set(nil) } }
    }
}
