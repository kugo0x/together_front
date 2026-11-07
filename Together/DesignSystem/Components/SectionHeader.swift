import SwiftUI

/// Section title over a grouped list: `title-3` title, optional count in `ink-2`,
/// at most one text action in the space accent. No icons, no badges.
struct SectionHeader: View {
    let title: String
    var count: Int?
    var action: String?
    var onAction: () -> Void = {}

    @Environment(\.accent) private var accent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TG.Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: TG.Space.s2) {
                Text(title)
                    .font(TG.Font.title3)
                    .foregroundStyle(TG.Colors.ink)
                if let count {
                    Text(count, format: .number)
                        .font(TG.Font.body)
                        .monospacedDigit()
                        .foregroundStyle(TG.Colors.ink2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if let action {
                Button(action, action: onAction)
                    .buttonStyle(.plain)
                    .font(TG.Font.subhead.weight(.medium))
                    .foregroundStyle(accent.ink)
                    .hitArea(20)
            }
        }
        .textCase(nil)
        .padding(.horizontal, TG.Space.s4)
        .padding(.bottom, TG.Space.s2)
    }
}

// MARK: - Preview

struct SectionHeaderGallery: View {
    var body: some View {
        SectionHeader(title: "Groceries", count: 7, action: "See all")
            .padding(.top, TG.Space.s3)
            .frame(width: 390)
    }
}

#Preview("SectionHeader · Light") { SectionHeaderGallery().catalogCanvas() }
#Preview("SectionHeader · Dark") { SectionHeaderGallery().catalogCanvas().preferredColorScheme(.dark) }
