import SwiftUI

/// SHARED / PRIVATE stamp for an item shown outside its own space's list. Always icon + word.
struct PrivacyBadge: View {
    let space: SpaceKind

    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 20

    private var isShared: Bool { space == .shared }

    var body: some View {
        HStack(spacing: TG.Space.s1) {
            Icon(isShared ? .people : .lock)
                .imageScale(.small)
            Text(isShared ? "Shared" : "Private")
                .textCase(.uppercase)
                .tracking(DS.captionTracking)
        }
        .font(TG.Font.caption.weight(.semibold))
        .foregroundStyle(isShared ? TG.Colors.sharedInk : TG.Colors.personal)
        .padding(.horizontal, 6)
        .frame(minHeight: height)
        .background(
            isShared ? TG.Colors.sharedSoft : TG.Colors.personalSoft,
            in: RoundedRectangle(cornerRadius: TG.Radius.sm, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isShared ? "Shared" : "Private")
    }
}

// MARK: - Preview

struct PrivacyBadgeGallery: View {
    var body: some View {
        HStack(spacing: TG.Space.s3) {
            PrivacyBadge(space: .shared)
            PrivacyBadge(space: .personal)
        }
        .padding(TG.Space.s4)
    }
}

#Preview("PrivacyBadge · Light") { PrivacyBadgeGallery().catalogCanvas() }
#Preview("PrivacyBadge · Dark") { PrivacyBadgeGallery().catalogCanvas().preferredColorScheme(.dark) }
