import AuthenticationServices
import GoogleSignInSwift
import SwiftUI

/// Signed out: Welcome → Sign up / Log in (design/prototype Onboarding, SignUp, Login).
struct AuthFlow: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signup, login
        var id: String { rawValue }
    }

    @State private var mode: Mode?

    var body: some View {
        if let mode {
            AuthFormView(mode: mode) { self.mode = nil }
                .transition(.move(edge: .trailing))
        } else {
            WelcomeView { self.mode = $0 }
                .transition(.move(edge: .leading))
        }
    }
}

/// "Together — Groceries, chores and notes for the two of you — plus a private space that’s only yours."
struct WelcomeView: View {
    let onChoose: (AuthFlow.Mode) -> Void

    var body: some View {
        VStack(spacing: TG.Space.s6) {
            Spacer(minLength: TG.Space.s6)
            illustration
            VStack(spacing: TG.Space.s3) {
                Text("Together")
                    .font(TG.Font.largeTitle)
                    .foregroundStyle(TG.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Groceries, chores and notes for the two of you — plus a private space that’s only yours.")
                    .font(TG.Font.body)
                    .foregroundStyle(TG.Colors.ink2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, TG.Space.s5)
            Spacer(minLength: TG.Space.s6)
            VStack(spacing: TG.Space.s2) {
                TGButton("Get started", block: true) { onChoose(.signup) }
                TGButton("I already have an account", variant: .plain, block: true) { onChoose(.login) }
            }
            .padding(.horizontal, TG.Space.s5)
            .padding(.bottom, TG.Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TG.Colors.bg)
    }

    /// Two avatars and the lock of the Personal space — no logos, no stock art.
    private var illustration: some View {
        ZStack {
            Circle()
                .fill(TG.Colors.sharedSoft)
                .frame(width: 168, height: 168)
            Icon(.lock)
                .font(TG.Font.largeTitle)
                .foregroundStyle(TG.Colors.personal)
                .offset(y: -18)
            HStack(spacing: -TG.Space.s3) {
                Avatar(person: .alex, size: 48)
                Avatar(person: .sam, size: 48)
            }
            .offset(y: 46)
        }
        .accessibilityHidden(true)
    }
}

/// Email + password with the design's validation, Show/Hide, Forgot password, the error state, and the
/// official Apple and Google buttons. The primary button is pinned above the keyboard.
struct AuthFormView: View {
    @State var mode: AuthFlow.Mode
    let onBack: () -> Void

    @Environment(Session.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.googleSignIn) private var google
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var emailTouched = false
    @State private var error: AuthError?
    @State private var nonce = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var emailOK: Bool { AuthValidation.isValidEmail(email) }
    private var passwordOK: Bool { AuthValidation.isValidPassword(password) }
    private var showEmailError: Bool { emailTouched && !email.isEmpty && !emailOK }
    private var canSubmit: Bool { emailOK && passwordOK && !session.isBusy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TG.Space.s5) {
                Button(action: onBack) {
                    Label { Text("Back") } icon: { Icon(.chevron).rotationEffect(.degrees(180)) }
                        .font(TG.Font.body)
                        .foregroundStyle(TG.Colors.sharedInk)
                }
                .buttonStyle(.bare)
                .frame(minHeight: DS.minTarget)

                VStack(alignment: .leading, spacing: TG.Space.s2) {
                    Text(mode == .signup ? "Create your account" : "Welcome back")
                        .font(TG.Font.title2)
                        .foregroundStyle(TG.Colors.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(mode == .signup
                         ? "Your Personal space is created with your account — only you can see it."
                         : "Log in to see your Shared and Personal spaces.")
                        .font(TG.Font.subhead)
                        .foregroundStyle(TG.Colors.ink2)
                }

                Picker("Mode", selection: $mode) {
                    Text("Sign up").tag(AuthFlow.Mode.signup)
                    Text("Log in").tag(AuthFlow.Mode.login)
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { error = nil }

                fields

                if let message = error?.message {
                    HStack(alignment: .top, spacing: TG.Space.s2) {
                        Icon(.close).fontWeight(.bold)
                        Text(message)
                    }
                    .font(TG.Font.subhead)
                    .foregroundStyle(TG.Colors.danger)
                    .padding(TG.Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TG.Colors.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: TG.Radius.md, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isStaticText)
                }

                divider
                socialButtons

                Text("By continuing you agree to the [Terms](https://together.app/terms) and [Privacy Policy](https://together.app/privacy).")
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
                    .tint(TG.Colors.sharedInk)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, TG.Space.s5)
            .padding(.vertical, TG.Space.s3)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(TG.Colors.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) { primaryButton }
        .environment(\.space, .shared)
    }

    // MARK: Pieces

    private var fields: some View {
        VStack(alignment: .leading, spacing: TG.Space.s4) {
            VStack(alignment: .leading, spacing: TG.Space.s2) {
                label("Email")
                TextField("Email", text: $email, prompt: Text("you@example.com").foregroundStyle(TG.Colors.ink3))
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
                    .onChange(of: email) { error = nil }
                    .modifier(FieldStyle(invalid: showEmailError))
                    .accessibilityLabel("Email")
                if showEmailError {
                    Text("Enter an email like name@example.com")
                        .font(TG.Font.footnote)
                        .foregroundStyle(TG.Colors.danger)
                }
            }
            .onChange(of: focus) { old, _ in if old == .email { emailTouched = true } }

            VStack(alignment: .leading, spacing: TG.Space.s2) {
                label("Password")
                HStack(spacing: TG.Space.s2) {
                    Group {
                        if showPassword {
                            TextField("Password", text: $password, prompt: passwordPrompt)
                        } else {
                            SecureField("Password", text: $password, prompt: passwordPrompt)
                        }
                    }
                    .textContentType(mode == .signup ? .newPassword : .password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit { if canSubmit { submit() } }
                    .onChange(of: password) { error = nil }
                    .accessibilityLabel("Password")

                    Button(showPassword ? "Hide" : "Show") { showPassword.toggle() }
                        .font(TG.Font.subhead.weight(.semibold))
                        .foregroundStyle(TG.Colors.sharedInk)
                        .buttonStyle(.bare)
                        .hitArea(28)
                        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }
                .modifier(FieldStyle(invalid: error == .invalidCredentials))

                if mode == .signup {
                    HStack(spacing: TG.Space.s1) {
                        Icon(.check).fontWeight(.bold).imageScale(.small)
                        Text("At least 8 characters")
                    }
                    .font(TG.Font.footnote)
                    .foregroundStyle(passwordOK ? TG.Colors.success : TG.Colors.ink2)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(passwordOK ? "Done" : "Not yet")
                } else {
                    HStack {
                        Spacer()
                        Button("Forgot password?", action: forgotPassword)
                            .font(TG.Font.subhead.weight(.medium))
                            .foregroundStyle(TG.Colors.sharedInk)
                            .buttonStyle(.bare)
                            .frame(minHeight: DS.minTarget)
                    }
                }
            }
        }
    }

    private var passwordPrompt: Text {
        Text(mode == .signup ? "Create a password" : "Your password").foregroundStyle(TG.Colors.ink3)
    }

    private var primaryButton: some View {
        TGButton(buttonTitle, block: true, action: submit)
            .accessibilityIdentifier("authSubmit")
            .disabled(!canSubmit)
            .opacity(canSubmit || session.isBusy ? 1 : DS.disabledOpacity)
            .padding(.horizontal, TG.Space.s5)
            .padding(.vertical, TG.Space.s3)
            .background(TG.Colors.bg)
    }

    private var buttonTitle: String {
        switch (mode, session.isBusy) {
        case (.signup, true): "Creating account…"
        case (.signup, false): "Create account"
        case (.login, true): "Logging in…"
        case (.login, false): "Log in"
        }
    }

    private var divider: some View {
        HStack(spacing: TG.Space.s3) {
            TG.Colors.separator.frame(height: DS.hairline)
            Text("or").font(TG.Font.footnote).foregroundStyle(TG.Colors.ink2)
            TG.Colors.separator.frame(height: DS.hairline)
        }
        .accessibilityHidden(true)
    }

    /// The official buttons — their logos and wording come from Apple and Google, never redrawn (HANDOFF §2.9).
    private var socialButtons: some View {
        VStack(spacing: TG.Space.s3) {
            SignInWithAppleButton(mode == .signup ? .signUp : .continue) { request in
                nonce = AppleNonce.make()
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleNonce.sha256(nonce)
            } onCompletion: { result in
                appleCompleted(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: TG.Radius.md, style: .continuous))

            GoogleSignInButton(
                viewModel: GoogleSignInButtonViewModel(scheme: colorScheme == .dark ? .dark : .light, style: .wide),
                action: googleTapped
            )
            .frame(height: 50)
            .accessibilityLabel("Sign in with Google")
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(TG.Font.subhead.weight(.medium))
            .foregroundStyle(TG.Colors.ink)
            .accessibilityHidden(true)
    }

    // MARK: Actions

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        error = nil
        Task {
            do {
                if mode == .signup {
                    try await session.register(email: email, password: password)
                } else {
                    try await session.login(email: email, password: password)
                }
            } catch let failure as AuthError {
                error = failure
            } catch {
                self.error = .network
            }
        }
    }

    private func forgotPassword() {
        guard emailOK else {
            emailTouched = true
            toasts.show("Enter your email first")
            return
        }
        Task {
            try? await session.forgotPassword(email: email)
            toasts.show("Reset link sent to \(email.trimmingCharacters(in: .whitespaces))")
        }
    }

    private func appleCompleted(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                error = .network
                return
            }
            let name = credential.fullName.flatMap { PersonNameComponentsFormatter().string(from: $0) }
            Task {
                do {
                    try await session.signInWithApple(identityToken: token, nonce: nonce, displayName: name)
                } catch let failure as AuthError {
                    error = failure
                } catch {
                    self.error = .network
                }
            }
        case .failure(let failure):
            let mapped = AuthError.fromApple(failure)
            if mapped != .cancelled { error = mapped }
        }
    }

    private func googleTapped() {
        Task {
            do {
                let (token, nonce) = try await google.signIn()
                try await session.signInWithGoogle(idToken: token, nonce: nonce)
            } catch let failure as AuthError {
                if failure != .cancelled { error = failure }
            } catch {
                self.error = .network
            }
        }
    }
}

/// The design's text field: surface fill, hairline border, red border when invalid.
struct FieldStyle: ViewModifier {
    var invalid = false

    func body(content: Content) -> some View {
        content
            .font(TG.Font.body)
            .foregroundStyle(TG.Colors.ink)
            .padding(.horizontal, TG.Space.s4)
            .frame(minHeight: 50)
            .background(TG.Colors.surface, in: RoundedRectangle(cornerRadius: TG.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TG.Radius.md, style: .continuous)
                    .strokeBorder(invalid ? TG.Colors.danger : TG.Colors.separator, lineWidth: DS.hairline)
            )
    }
}
