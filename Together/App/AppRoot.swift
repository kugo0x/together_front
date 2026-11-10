import GoogleSignIn
import SwiftUI

/// Settings → Appearance.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Switches on the session: welcome / sign in → onboarding (name → share) → the app shell.
///
/// Normally the app talks to the API (`APIConfig.baseURL`). Launch arguments for UI tests and screenshots run it on
/// fakes instead, never touching the real Keychain: `-signedIn YES` starts signed in as Alex; `-signedOut YES` starts
/// at the welcome screen; `-fakeBackend YES` runs the fakes from the welcome screen with the real Keychain.
struct AppRoot: View {
    @State private var session: Session
    @State private var toasts = ToastCenter()
    @AppStorage("appearance") private var appearance: Appearance = .system
    /// The API side; `nil` on fakes.
    private let backend: Backend?

    @MainActor
    private final class SessionBox { weak var session: Session? }

    init() {
        let defaults = UserDefaults.standard
        let signedIn = defaults.bool(forKey: "signedIn")
        let testing = signedIn || defaults.bool(forKey: "signedOut")
        let keychain: KeychainStore = testing ? InMemoryKeychain() : SystemKeychain()
        let box = SessionBox()
        let backend = APIConfig.usesFakes ? nil
            : Backend(tokens: Session.storedTokens(in: keychain), session: { box.session })
        let session = Session(
            service: backend?.auth ?? FakeAuthService(delay: .milliseconds(testing ? 150 : 600)),
            keychain: keychain
        )
        box.session = session
        if let backend {
            session.vault = backend.vault
            session.willSignOut = { await backend.push.unregister() }
        }
        self.backend = backend
        if signedIn {
            session.adopt(AuthResult(
                user: FakeAuthService.alex,
                tokens: AuthTokens(accessToken: "fake-access." + FakeAuthService.alex.id.uuidString,
                                   accessExpiresAt: .distantFuture,
                                   refreshToken: "fake-refresh", refreshExpiresAt: .distantFuture),
                isNewUser: false
            ))
        }
        _session = State(initialValue: session)
    }

    var body: some View {
        Group {
            switch session.state {
            case .signedOut:
                AuthFlow().toastHost()
            case .onboarding(let step):
                OnboardingFlow(step: step).toastHost()
            case .signedIn:
                RootView(toasts: toasts)
            }
        }
        .environment(session)
        .environment(toasts)
        .environment(\.backend, backend)
        .environment(\.inviteService, backend?.invites ?? FakeInviteService())
        .preferredColorScheme(appearance.colorScheme)
        // Google's sign-in returns to the app through its URL scheme.
        .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        .animation(.easeInOut(duration: 0.25), value: session.state)
    }
}
