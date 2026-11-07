import SwiftUI

/// What the assignee will see on their lock screen when a task reminder fires — shown in the task sheet
/// before saving. Copy names the person and the task, never nags.
struct NotificationPreview: View {
    /// "Alex asked you to"
    let title: String
    /// "Return the parcel · Monday"
    let message: String
    /// "now", "9:00"
    var when = "now"

    @ScaledMetric(relativeTo: .subheadline) private var appIconSize: CGFloat = 38

    var body: some View {
        HStack(alignment: .top, spacing: TG.Space.s3) {
            Icon(.people)
                .font(TG.Font.body.weight(.semibold))
                .foregroundStyle(TG.Colors.onShared)
                .frame(width: appIconSize, height: appIconSize)
                .background(TG.Colors.shared, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Together")
                        .fontWeight(.semibold)
                        .foregroundStyle(TG.Colors.ink)
                    Spacer(minLength: TG.Space.s2)
                    Text(when)
                        .foregroundStyle(TG.Colors.ink2)
                }
                .font(TG.Font.footnote)

                Text(title)
                    .font(TG.Font.subhead.weight(.semibold))
                    .foregroundStyle(TG.Colors.ink)
                    .padding(.top, DS.rowLineGap)
                Text(message)
                    .font(TG.Font.subhead)
                    .foregroundStyle(TG.Colors.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(TG.Colors.surface)
                .tgShadow(TG.Shadow.float)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notification: \(title). \(message)")
        .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Preview

struct NotificationPreviewGallery: View {
    var body: some View {
        NotificationPreview(title: "Alex asked you to", message: "Return the parcel · Monday", when: "9:00")
            .padding(.horizontal, TG.Space.s4)
            .padding(.vertical, TG.Space.s4)
            .frame(width: 390)
    }
}

#Preview("NotificationPreview · Light") { NotificationPreviewGallery().catalogCanvas() }
#Preview("NotificationPreview · Dark") { NotificationPreviewGallery().catalogCanvas().preferredColorScheme(.dark) }
