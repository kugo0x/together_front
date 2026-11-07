import SwiftUI

/// A centred, kind explanation of an empty list with at most one action. One per screen, no illustration.
struct EmptyState: View {
    let title: String
    var message: String?
    var icon: IconName = .cart
    var action: String?
    var actionIcon: IconName?
    var onAction: () -> Void = {}

    @Environment(\.accent) private var accent
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 56

    var body: some View {
        VStack(spacing: TG.Space.s2) {
            Icon(icon)
                .font(TG.Font.title2.weight(.regular))
                .foregroundStyle(accent.ink)
                .frame(width: iconSize, height: iconSize)
                .background(accent.soft, in: Circle())
                .padding(.bottom, TG.Space.s2)

            Text(title)
                .font(TG.Font.headline)
                .foregroundStyle(TG.Colors.ink)
                .accessibilityAddTraits(.isHeader)

            if let message {
                Text(message)
                    .font(TG.Font.callout)
                    .foregroundStyle(TG.Colors.ink2)
                    .frame(maxWidth: 280)
                    .padding(.bottom, TG.Space.s3)
            }

            if let action {
                TGButton(action, icon: actionIcon, variant: .tinted, size: .sm, action: onAction)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, TG.Space.s8)
        .padding(.horizontal, TG.Space.s6)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

struct EmptyStateGallery: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            EmptyState(title: "Nothing to buy",
                       message: "Add something below, or check this week’s suggestions.",
                       icon: .cart, action: "See suggestions", actionIcon: .history)
            EmptyState(title: "Your private notes",
                       message: "Notes here are only for you. Sam can’t see them.",
                       icon: .lock, action: "New note", actionIcon: .plus)
                .environment(\.space, .personal)
        }
        .frame(width: 520)
    }
}

#Preview("EmptyState · Light") { EmptyStateGallery().catalogCanvas() }
#Preview("EmptyState · Dark") { EmptyStateGallery().catalogCanvas().preferredColorScheme(.dark) }
