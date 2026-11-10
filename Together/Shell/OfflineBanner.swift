import SwiftUI

/// A calm strip under the status bar while the server can't be reached. Nothing is lost: what was changed meanwhile
/// is already on screen and is sent when the connection is back (or on Retry).
struct OfflineBanner: View {
    /// Changes waiting to be sent.
    let pending: Int
    let retry: () -> Void

    var body: some View {
        HStack(spacing: TG.Space.s3) {
            VStack(alignment: .leading, spacing: DS.rowLineGap) {
                Text("You’re offline")
                    .font(TG.Font.subhead.weight(.semibold))
                    .foregroundStyle(TG.Colors.ink)
                Text(pending == 0 ? "Showing what was here last." :
                        pending == 1 ? "1 change will sync when you’re back." : "\(pending) changes will sync when you’re back.")
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: retry)
                .font(TG.Font.subhead.weight(.semibold))
                .foregroundStyle(TG.Colors.ink)
                .hitArea(44)
        }
        .padding(.horizontal, TG.Space.s4)
        .padding(.vertical, TG.Space.s2)
        .background(TG.Colors.surface2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityAction(named: "Retry", retry)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#Preview("OfflineBanner") {
    VStack(spacing: 0) {
        OfflineBanner(pending: 2) {}
        Spacer()
    }
}
