import AuthenticationServices
import CryptoKit
import GoogleSignIn
import SwiftUI
import UIKit

// MARK: - Apple

/// Sign in with Apple needs a random nonce: its SHA-256 goes in the request, the raw value to our backend.
enum AppleNonce {
    static func make(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AuthError {
    /// Maps the Apple sheet's failure. Without the "Sign in with Apple" capability the sheet fails with
    /// `.unknown` (1000) — that is a configuration problem, not the user's.
    static func fromApple(_ error: Error) -> AuthError {
        switch (error as? ASAuthorizationError)?.code {
        case .canceled?: .cancelled
        case .unknown?, .notHandled?, nil: .notConfigured(provider: .apple)
        default: .network
        }
    }
}

// MARK: - Google

/// Google sign-in, behind a protocol so tests and unconfigured builds don't touch the SDK.
protocol GoogleSignInProviding: Sendable {
    /// Shows Google's sheet and returns the ID token and the raw nonce for `POST /v1/auth/google`.
    @MainActor func signIn() async throws -> (idToken: String, nonce: String)
}

/// The real GoogleSignIn SDK. Needs `GIDClientID` and the reversed-client-ID URL scheme in Info.plist
/// (see README → "Sign in with Apple and Google"); without them it reports `.notConfigured` instead of crashing.
struct GoogleSDKSignIn: GoogleSignInProviding {
    static var isConfigured: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String).map { !$0.isEmpty } ?? false
    }

    @MainActor
    func signIn() async throws -> (idToken: String, nonce: String) {
        guard Self.isConfigured else { throw AuthError.notConfigured(provider: .google) }
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else { throw AuthError.network }
        // The API binds the ID token to a nonce we make (a leaked token can't be replayed).
        let nonce = AppleNonce.make()
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter.topmost, hint: nil, additionalScopes: nil, nonce: nonce)
            guard let token = result.user.idToken?.tokenString else { throw AuthError.network }
            return (token, nonce)
        } catch let error as NSError where error.domain == kGIDSignInErrorDomain
                    && error.code == GIDSignInError.canceled.rawValue {
            throw AuthError.cancelled
        }
    }
}

private extension UIViewController {
    var topmost: UIViewController { presentedViewController?.topmost ?? self }
}

private struct GoogleSignInKey: EnvironmentKey {
    static let defaultValue: GoogleSignInProviding = GoogleSDKSignIn()
}

extension EnvironmentValues {
    var googleSignIn: GoogleSignInProviding {
        get { self[GoogleSignInKey.self] }
        set { self[GoogleSignInKey.self] = newValue }
    }
}

// MARK: - Invites

private struct InviteServiceKey: EnvironmentKey {
    static let defaultValue: InviteService = FakeInviteService()
}

extension EnvironmentValues {
    var inviteService: InviteService {
        get { self[InviteServiceKey.self] }
        set { self[InviteServiceKey.self] = newValue }
    }
}
