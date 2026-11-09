import Foundation

// Shapes of the backend auth API (back/api/openapi.yaml: User, Tokens, AuthResult, error codes).

enum AuthProvider: String, Codable, Sendable { case email, apple, google }

struct AuthUser: Codable, Equatable, Sendable {
    var id: UUID
    var email: String?
    var displayName: String
    var providers: [AuthProvider]
}

/// Access JWT (15 min) + single-use refresh token. Stored only in the Keychain.
struct AuthTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var accessExpiresAt: Date
    var refreshToken: String
    var refreshExpiresAt: Date
}

struct AuthResult: Equatable, Sendable {
    var user: AuthUser
    var tokens: AuthTokens
    /// true → onboarding (name → invite or solo).
    var isNewUser: Bool
}

/// The API's error codes the screens branch on, plus the client-side cases.
enum AuthError: Error, Equatable, Sendable {
    case invalidCredentials
    case emailTaken
    case validationFailed(field: String)
    case notConfigured(provider: AuthProvider)
    case cancelled
    case network

    /// What the auth screen shows (design copy for the error state).
    var message: String? {
        switch self {
        case .invalidCredentials: "That password doesn’t match this email. Try again or reset it."
        case .emailTaken: "There’s already an account with this email. Log in instead."
        case .validationFailed(let field): field == "email" ? "Enter an email like name@example.com" : "Check your password"
        case .notConfigured(let provider): "\(provider == .apple ? "Apple" : "Google") sign-in isn’t set up in this build yet."
        case .cancelled: nil
        case .network: "Can’t reach Together. Check your connection and try again."
        }
    }
}

/// The client-side rules the form checks before calling the API (`register`: email format, password 8…256).
enum AuthValidation {
    static let passwordMinLength = 8
    static let passwordMaxLength = 256
    static let nameMaxLength = 50

    static func isValidEmail(_ email: String) -> Bool {
        email.trimmingCharacters(in: .whitespaces)
            .range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    static func isValidPassword(_ password: String) -> Bool {
        (passwordMinLength...passwordMaxLength).contains(password.count)
    }

    /// The display name, trimmed and capped; `nil` when empty.
    static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(nameMaxLength))
    }
}
