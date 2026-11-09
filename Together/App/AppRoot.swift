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
/// Launch arguments for UI tests and screenshots (they never touch the real Keychain):
/// `-signedIn YES` starts signed in as Alex; `-signedOut YES` starts at the welcome screen.
struct AppRoot: View {
    @State private var session: Session
    @State private var toasts = ToastCenter()
    @AppStorage("appearance") private var appearance: Appearance = .system

    init() {
        let defaults = UserDefaults.standard
        let signedIn = defaults.bool(forKey: "signedIn")
        let testing = signedIn || defaults.bool(forKey: "signedOut")
        let session = Session(
            service: FakeAuthService(delay: .milliseconds(testing ? 150 : 600)),
            keychain: testing ? InMemoryKeychain() : SystemKeychain()
        )
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
        .preferredColorScheme(appearance.colorScheme)
        // Google's sign-in returns to the app through its URL scheme.
        .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        .animation(.easeInOut(duration: 0.25), value: session.state)
    }
}
