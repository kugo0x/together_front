import Foundation

/// The backend auth endpoints (`/v1/auth/*`, `PATCH`/`DELETE /v1/me`). The app talks to this protocol only;
/// `FakeAuthService` stands in until phase 9 adds the HTTP implementation.
protocol AuthService: Sendable {
    /// POST /v1/auth/register — 409 `email_taken`.
    func register(email: String, password: String, displayName: String?) async throws -> AuthResult
    /// POST /v1/auth/login — 401 `invalid_credentials`.
    func login(email: String, password: String) async throws -> AuthResult
    /// POST /v1/auth/apple — identity token + the RAW nonce; the name only comes on the first sign-in.
    func signInWithApple(identityToken: String, nonce: String, displayName: String?) async throws -> AuthResult
    /// POST /v1/auth/google — the Google ID token and the raw nonce it was issued for.
    func signInWithGoogle(idToken: String, nonce: String) async throws -> AuthResult
    /// POST /v1/auth/password/forgot — always succeeds (no account enumeration).
    func forgotPassword(email: String) async throws
    /// PATCH /v1/me { display_name }.
    func updateDisplayName(_ name: String, tokens: AuthTokens) async throws -> AuthUser
    /// POST /v1/auth/logout — revokes the refresh token.
    func logout(tokens: AuthTokens) async throws
    /// DELETE /v1/me.
    func deleteAccount(tokens: AuthTokens) async throws
}

/// In-memory stand-in for the auth API with the same rules and error codes. Seeded with alex@example.com.
actor FakeAuthService: AuthService {
    private struct Account {
        var user: AuthUser
        var password: String?
    }

    private var accounts: [String: Account] = [:]
    private let delay: Duration
    private let clock: @Sendable () -> Date

    /// The seeded account (also what `-signedIn YES` starts as).
    static let alex = AuthUser(id: Person.alex.id,
                               email: "alex@example.com", displayName: "Alex", providers: [.email])
    static let alexPassword = "together123"

    init(delay: Duration = .milliseconds(600), clock: @escaping @Sendable () -> Date = { .now }) {
        self.delay = delay
        self.clock = clock
        accounts[Self.alex.email!] = Account(user: Self.alex, password: Self.alexPassword)
    }

    func register(email: String, password: String, displayName: String?) async throws -> AuthResult {
        try await pause()
        let email = Self.normalize(email)
        guard AuthValidation.isValidEmail(email) else { throw AuthError.validationFailed(field: "email") }
        guard AuthValidation.isValidPassword(password) else { throw AuthError.validationFailed(field: "password") }
        guard accounts[email] == nil else { throw AuthError.emailTaken }
        let user = AuthUser(id: UUID(), email: email, displayName: displayName.flatMap(AuthValidation.cleanName) ?? "",
                            providers: [.email])
        accounts[email] = Account(user: user, password: password)
        return result(for: user, isNew: true)
    }

    func login(email: String, password: String) async throws -> AuthResult {
        try await pause()
        guard let account = accounts[Self.normalize(email)], account.password == password else {
            throw AuthError.invalidCredentials
        }
        return result(for: account.user, isNew: false)
    }

    func signInWithApple(identityToken: String, nonce: String, displayName: String?) async throws -> AuthResult {
        try await social(.apple, key: "apple:" + identityToken, name: displayName)
    }

    func signInWithGoogle(idToken: String, nonce: String) async throws -> AuthResult {
        try await social(.google, key: "google:" + idToken, name: nil)
    }

    func forgotPassword(email: String) async throws {
        try await pause()
    }

    func updateDisplayName(_ name: String, tokens: AuthTokens) async throws -> AuthUser {
        guard let name = AuthValidation.cleanName(name) else { throw AuthError.validationFailed(field: "display_name") }
        guard let key = accounts.first(where: { tokens.accessToken.hasSuffix($0.value.user.id.uuidString) })?.key else {
            throw AuthError.invalidCredentials
        }
        accounts[key]?.user.displayName = name
        return accounts[key]!.user
    }

    func logout(tokens: AuthTokens) async throws {}

    func deleteAccount(tokens: AuthTokens) async throws {
        accounts = accounts.filter { !tokens.accessToken.hasSuffix($0.value.user.id.uuidString) }
    }

    // MARK: Private

    private func social(_ provider: AuthProvider, key: String, name: String?) async throws -> AuthResult {
        try await pause()
        if let account = accounts[key] { return result(for: account.user, isNew: false) }
        let user = AuthUser(id: UUID(), email: nil, displayName: name.flatMap(AuthValidation.cleanName) ?? "",
                            providers: [provider])
        accounts[key] = Account(user: user, password: nil)
        return result(for: user, isNew: true)
    }

    private func result(for user: AuthUser, isNew: Bool) -> AuthResult {
        let now = clock()
        let tokens = AuthTokens(
            accessToken: "fake-access." + user.id.uuidString,
            accessExpiresAt: now.addingTimeInterval(15 * 60),
            refreshToken: "fake-refresh." + UUID().uuidString,
            refreshExpiresAt: now.addingTimeInterval(30 * 24 * 3600)
        )
        return AuthResult(user: user, tokens: tokens, isNewUser: isNew)
    }

    private func pause() async throws {
        if delay > .zero { try await Task.sleep(for: delay) }
    }

    private static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
