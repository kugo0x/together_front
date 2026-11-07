import SwiftUI

/// A brief confirmation pill with an optional Undo, or quiet partner activity with their avatar.
/// Bottom-centre above the tab bar, `shadow-float`, one at a time (the overlay lives in the app shell).
struct Toast: View {
    let message: String
    var person: Person?
    var action: String?
    var onAction: () -> Void = {}

    @ScaledMetric(relativeTo: .subheadline) private var avatarSize: CGFloat = 22

    var body: some View {
        HStack(spacing: TG.Space.s3) {
            if let person {
                Avatar(person: person, size: avatarSize)
                    .accessibilityHidden(true)
            }
            Text(message)
                .font(TG.Font.subhead)
                .foregroundStyle(TG.Colors.onToast)
            if let action {
                Button(action, action: onAction)
                    .buttonStyle(.plain)
                    .font(TG.Font.subhead.weight(.semibold))
                    .foregroundStyle(TG.Colors.onToast)
                    .padding(.vertical, 6)
                    .padding(.horizontal, TG.Space.s3)
                    .background(TG.Colors.onToast.opacity(0.14), in: Capsule())
                    .hitArea(32)
            }
        }
        .padding(.vertical, TG.Space.s2)
        .padding(.leading, TG.Space.s4)
        .padding(.trailing, action == nil ? TG.Space.s4 : TG.Space.s2)
        .background {
            Capsule().fill(TG.Colors.toast).tgShadow(TG.Shadow.float)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Preview

struct ToastGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TG.Space.s4) {
            Toast(message: "Moved to Shared", action: "Undo")
            Toast(message: "Sam checked off 3 items", person: .sam)
        }
        .padding(TG.Space.s4)
    }
}

#Preview("Toast · Light") { ToastGallery().catalogCanvas() }
#Preview("Toast · Dark") { ToastGallery().catalogCanvas().preferredColorScheme(.dark) }
