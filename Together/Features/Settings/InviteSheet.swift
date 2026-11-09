import SwiftUI
import UIKit

/// "Invite your partner": the code `TGT-XXXX` and a link to share; or, if someone invited you, join with their
/// code. Ends with "Sam joined your Shared space" once they accept (prototype `sendInvite`).
struct InviteSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.inviteService) private var invites
    @Environment(\.dismiss) private var dismiss

    @State private var invite: Invite?
    @State private var code = ""
    @State private var codeError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: TG.Space.s4) {
                Icon(.people)
                    .font(TG.Font.title2)
                    .foregroundStyle(TG.Colors.sharedInk)
                    .frame(width: 56, height: 56)
                    .background(TG.Colors.sharedSoft, in: Circle())
                    .accessibilityHidden(true)
                Text("Invite your partner")
                    .font(TG.Font.title3)
                    .foregroundStyle(TG.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("They’ll join your Shared space: groceries, household tasks and shared notes. Your Personal space stays private.")
                    .font(TG.Font.subhead)
                    .foregroundStyle(TG.Colors.ink2)
                    .multilineTextAlignment(.center)

                VStack(spacing: TG.Space.s1) {
                    Text("Or enter this code in Together")
                        .font(TG.Font.footnote)
                        .foregroundStyle(TG.Colors.ink2)
                    Text(invite?.code ?? "TGT-····")
                        .font(TG.Font.title2.monospaced())
                        .foregroundStyle(TG.Colors.ink)
                        .textSelection(.enabled)
                        .accessibilityLabel(invite.map { "Code \($0.code)" } ?? "Code loading")
                }
                .frame(maxWidth: .infinity)
                .padding(TG.Space.s4)
                .background(TG.Colors.surface2, in: RoundedRectangle(cornerRadius: TG.Radius.lg, style: .continuous))

                TGButton("Send invite link", icon: .share, block: true, action: share)
                    .disabled(invite == nil)
                TGButton("Not now", variant: .secondary, block: true) { dismiss() }

                joinWithCode
                    .padding(.top, TG.Space.s3)
            }
            .padding(TG.Space.s5)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(TG.Colors.surface)
        .environment(\.space, .shared)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { invite = try? await invites.createInvite() }
    }

    private var joinWithCode: some View {
        VStack(alignment: .leading, spacing: TG.Space.s2) {
            Text("Got a code from someone?")
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
                TGButton("Join", variant: .secondary, action: join)
                    .fixedSize()
                    .disabled(code.isEmpty)
            }
            if let codeError {
                Text(codeError).font(TG.Font.footnote).foregroundStyle(TG.Colors.danger)
            }
        }
    }

    private func share() {
        guard let invite else { return }
        ShareSheet.present(["Join me in Together: \(invite.link.absoluteString) (code \(invite.code))"]) { shared in
            if shared { sent(invite) }
        }
    }

    /// The link went out: close, and say so when they join (the event stream in the real app).
    private func sent(_ invite: Invite) {
        let store = store, toasts = toasts, invites = invites
        dismiss()
        toasts.show("Invite sent")
        Task {
            guard let partner = try? await invites.waitForJoin(invite) else { return }
            store.joinPartner(partner)
            toasts.show("\(partner.name) joined your Shared space", person: partner)
        }
    }

    private func join() {
        guard !code.isEmpty else { return }
        Task {
            do {
                let partner = try await invites.accept(code: code)
                store.joinPartner(partner)
                dismiss()
                toasts.show("You joined \(partner.name)’s Shared space", person: partner)
            } catch let error as InviteError {
                codeError = error.message
            } catch {
                codeError = InviteError.notFound.message
            }
        }
    }
}

/// The system share sheet, presented the UIKit way (wrapped as SwiftUI sheet content it dismisses its own
/// presenter), reporting whether something was actually shared.
@MainActor
enum ShareSheet {
    static func present(_ items: [Any], onFinish: @escaping @MainActor (_ shared: Bool) -> Void) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in onFinish(completed) }
        }
        controller.popoverPresentationController?.sourceView = top.view
        top.present(controller, animated: true)
    }
}
