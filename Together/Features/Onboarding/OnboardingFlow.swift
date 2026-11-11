import SwiftUI

/// New account: step 1 "What should we call you?" → step 2 "Share with someone?" (design/prototype Onboarding).
struct OnboardingFlow: View {
    let step: Session.OnboardingStep

    var body: some View {
        switch step {
        case .name: NameStep().transition(.move(edge: .trailing))
        case .share: ShareStep().transition(.move(edge: .trailing))
        }
    }
}

private struct StepHeader: View {
    let step: Int
    let title: String
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TG.Space.s2) {
            Text("STEP \(step) OF 2")
                .font(TG.Font.caption)
                .tracking(DS.captionTracking)
                .foregroundStyle(TG.Colors.ink2)
            Text(title)
                .font(TG.Font.title2)
                .foregroundStyle(TG.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(TG.Font.subhead)
                    .foregroundStyle(TG.Colors.ink2)
            }
        }
    }
}

struct NameStep: View {
    @Environment(Session.self) private var session
    @State private var name = ""
    @State private var failed = false
    @FocusState private var focused: Bool

    private var canContinue: Bool { AuthValidation.cleanName(name) != nil && !session.isBusy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TG.Space.s5) {
                StepHeader(step: 1, title: "What should we call you?")
                VStack(alignment: .leading, spacing: TG.Space.s2) {
                    Text("Your name")
                        .font(TG.Font.subhead.weight(.medium))
                        .foregroundStyle(TG.Colors.ink)
                        .accessibilityHidden(true)
                    TextField("Your name", text: $name, prompt: Text("Name").foregroundStyle(TG.Colors.ink3))
                        .textContentType(.givenName)
                        .submitLabel(.continue)
                        .focused($focused)
                        .onSubmit(next)
                        .modifier(FieldStyle(invalid: failed))
                        .accessibilityLabel("Your name")
                }
                HStack(alignment: .top, spacing: TG.Space.s3) {
                    Icon(.lock).foregroundStyle(TG.Colors.personal)
                    Text("We’ve made your **Personal** space. Notes, tasks and lists there are only for you.")
                        .font(TG.Font.subhead)
                        .foregroundStyle(TG.Colors.ink)
                }
                .padding(TG.Space.s4)
                .background(TG.Colors.personalSoft, in: RoundedRectangle(cornerRadius: TG.Radius.lg, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, TG.Space.s5)
            .padding(.top, TG.Space.s6)
        }
        .background(TG.Colors.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TGButton("Continue", block: true, action: next)
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : DS.disabledOpacity)
                .padding(.horizontal, TG.Space.s5)
                .padding(.vertical, TG.Space.s3)
                .background(TG.Colors.bg)
        }
        .environment(\.space, .shared)
        .onAppear {
            name = session.user?.displayName ?? ""
            focused = true
        }
    }

    private func next() {
        guard canContinue else { return }
        Task {
            do { try await session.setName(name) } catch { failed = true }
        }
    }
}

struct ShareStep: View {
    @Environment(Session.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.inviteService) private var invites

    @State private var code = ""
    @State private var codeError: String?
    @State private var joining = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TG.Space.s5) {
                StepHeader(
                    step: 2,
                    title: "Share with someone?",
                    message: "Share groceries, tasks and notes with one person. Your Personal space stays yours."
                )
                option(icon: .people, tint: TG.Colors.sharedInk, background: TG.Colors.sharedSoft,
                       title: "Invite your partner", detail: "Send a link — they join in one tap") {
                    session.finishOnboarding(.invite)
                }
                option(icon: .person, tint: TG.Colors.ink2, background: TG.Colors.surface2,
                       title: "Just me for now", detail: "You can invite someone later in Settings") {
                    let name = session.user?.displayName ?? ""
                    session.finishOnboarding(.solo)
                    toasts.show(name.isEmpty ? "Welcome to Together" : "Welcome, \(name)")
                }
                joinWithCode
            }
            .padding(.horizontal, TG.Space.s5)
            .padding(.top, TG.Space.s6)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(TG.Colors.bg)
        .environment(\.space, .shared)
    }

    private func option(
        icon: IconName, tint: Color, background: Color, title: String, detail: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: TG.Space.s4) {
                Icon(icon)
                    .font(TG.Font.title3)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(background, in: Circle())
                VStack(alignment: .leading, spacing: DS.rowLineGap) {
                    Text(title).font(TG.Font.headline).foregroundStyle(TG.Colors.ink)
                    Text(detail).font(TG.Font.subhead).foregroundStyle(TG.Colors.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon(.chevron).font(TG.Font.footnote.weight(.semibold)).foregroundStyle(TG.Colors.ink3)
            }
            .padding(TG.Space.s4)
            .background(TG.Colors.surface, in: RoundedRectangle(cornerRadius: TG.Radius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.bare)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Someone invited you: join their Shared space with the code from their message.
    private var joinWithCode: some View {
        VStack(alignment: .leading, spacing: TG.Space.s2) {
            Text("Have an invite code?")
                .font(TG.Font.subhead.weight(.medium))
                .foregroundStyle(TG.Colors.ink)
            HStack(spacing: TG.Space.s2) {
                TextField("Invite code", text: $code, prompt: Text("TGT-7KQ2").foregroundStyle(TG.Colors.ink3))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .onSubmit(join)
                    .onChange(of: code) { codeError = nil }
                    .modifier(FieldStyle(invalid: codeError != nil))
                    .accessibilityLabel("Invite code")
                TGButton(joining ? "Joining…" : "Join", variant: .secondary, action: join)
                    .fixedSize()
                    .disabled(code.isEmpty || joining)
            }
            if let codeError {
                Text(codeError).font(TG.Font.footnote).foregroundStyle(TG.Colors.danger)
            }
        }
    }

    private func join() {
        guard !code.isEmpty, !joining else { return }
        joining = true
        Task {
            defer { joining = false }
            do {
                let partner = try await invites.accept(code: code)
                session.finishOnboarding(.joined(partner))
            } catch let error as InviteError {
                codeError = error.message
            } catch {
                codeError = InviteError.notFound.message
            }
        }
    }
}
