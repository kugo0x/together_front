import SwiftUI

/// Asks before anything crosses from Personal to Shared — or is deleted. The body names the consequence
/// and the person; buttons name the result ("Move to Shared" / "Keep private"), never OK / Cancel.
/// The confirm button is filled `shared` regardless of the current space, so the destination is visible.
struct ConfirmSheet: View {
    let title: String
    let message: String
    let confirm: String
    var cancel = "Cancel"
    var icon: IconName = .people
    var destructive = false
    /// Space whose fill the confirm button takes (destination). Moving to Shared → `.shared`.
    var confirmSpace: SpaceKind = .shared
    /// Draws the grabber + surface + top corners itself (static compositions). `false` inside `.sheet`,
    /// where the system provides them.
    var chrome = true
    var onConfirm: () -> Void = {}
    var onCancel: () -> Void = {}

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if chrome {
                Capsule()
                    .fill(TG.Colors.surface2)
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, TG.Space.s4)
                    .accessibilityHidden(true)
            }

            Icon(icon)
                .font(TG.Font.title3.weight(.regular))
                .foregroundStyle(TG.Colors.sharedInk)
                .frame(width: iconSize, height: iconSize)
                .background(TG.Colors.sharedSoft, in: Circle())
                .padding(.bottom, TG.Space.s3)

            Text(title)
                .font(TG.Font.title3)
                .foregroundStyle(TG.Colors.ink)
                .padding(.bottom, TG.Space.s2)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(TG.Font.callout)
                .foregroundStyle(TG.Colors.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, TG.Space.s5)

            VStack(spacing: TG.Space.s2) {
                TGButton(confirm, variant: destructive ? .destructive : .primary, block: true, action: onConfirm)
                    .environment(\.space, confirmSpace)
                TGButton(cancel, variant: .secondary, block: true, action: onCancel)
            }
        }
        .padding(.top, chrome ? TG.Space.s2 : TG.Space.s6)
        .padding(.horizontal, TG.Space.s5)
        .padding(.bottom, TG.Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if chrome {
                UnevenRoundedRectangle(topLeadingRadius: TG.Radius.xl, topTrailingRadius: TG.Radius.xl, style: .continuous)
                    .fill(TG.Colors.surface)
                    .tgShadow(TG.Shadow.sheet)
            }
        }
    }
}

extension View {
    /// Presents a `ConfirmSheet` as a medium-detent sheet with the system grabber.
    func confirmSheet(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        confirm: String,
        cancel: String = "Cancel",
        icon: IconName = .people,
        destructive: Bool = false,
        confirmSpace: SpaceKind = .shared,
        onConfirm: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            ConfirmSheet(
                title: title, message: message, confirm: confirm, cancel: cancel, icon: icon,
                destructive: destructive, confirmSpace: confirmSpace, chrome: false,
                onConfirm: { isPresented.wrappedValue = false; onConfirm() },
                onCancel: { isPresented.wrappedValue = false }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(TG.Radius.xl)
            .presentationBackground(TG.Colors.surface)
        }
    }
}

// MARK: - Preview

struct ConfirmSheetGallery: View {
    var body: some View {
        ConfirmSheet(
            title: "Move to Shared?",
            message: "“Weekend plans” will move to your Shared space. Sam will be able to see and edit it.",
            confirm: "Move to Shared",
            cancel: "Keep private"
        )
        .padding(.top, TG.Space.s6)
        .background(TG.Colors.scrim)
        .environment(\.space, .personal)
        .frame(width: 390)
    }
}

private struct ConfirmSheetLivePreview: View {
    @State private var shown = true
    var body: some View {
        Button("Move to Shared…") { shown = true }
            .buttonStyle(.tgTinted)
            .confirmSheet(isPresented: $shown, title: "Delete this note?",
                          message: "“Weekend plans” will be deleted for you and Sam.",
                          confirm: "Delete note", cancel: "Keep note", icon: .trash, destructive: true) {}
    }
}

#Preview("ConfirmSheet · Light") { ConfirmSheetGallery().catalogCanvas() }
#Preview("ConfirmSheet · Dark") { ConfirmSheetGallery().catalogCanvas().preferredColorScheme(.dark) }
#Preview("ConfirmSheet · Presented") { ConfirmSheetLivePreview() }
