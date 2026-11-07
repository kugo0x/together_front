import SwiftUI

/// A note in a list: bold title, two lines of preview, "Yesterday · Sam", optional privacy badge, chevron.
/// The whole row opens the editor.
struct NoteRow: View {
    let title: String
    var preview: String?
    /// "Yesterday", "Mon", "3 days ago".
    let updated: String
    /// Who edited last (shared notes).
    var by: Person?
    /// Adds a PrivacyBadge for this space (Home, search).
    var showSpace: SpaceKind?
    var me: Person = .alex
    var onTap: () -> Void = {}

    private var metaLine: String {
        updated + (by.map { " · \($0.displayName(me: me))" } ?? "")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TG.Space.s3) {
                VStack(alignment: .leading, spacing: DS.rowLineGap) {
                    Text(title)
                        .font(TG.Font.headline)
                        .foregroundStyle(TG.Colors.ink)
                        .lineLimit(1)
                    if let preview {
                        Text(preview)
                            .font(TG.Font.subhead)
                            .foregroundStyle(TG.Colors.ink2)
                            .lineLimit(2)
                    }
                    FlowLayout(spacing: TG.Space.s2, lineSpacing: DS.rowLineGap) {
                        Text(metaLine)
                        if let showSpace { PrivacyBadge(space: showSpace) }
                    }
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

                Icon(.chevron)
                    .font(TG.Font.footnote.weight(.semibold))
                    .foregroundStyle(TG.Colors.ink3)
            }
            .padding(.vertical, TG.Space.s3)
            .padding(.horizontal, TG.Space.s4)
            .frame(minHeight: DS.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(NoteRowButtonStyle())
        .alignmentGuide(.listRowSeparatorLeading) { _ in TG.Space.s4 }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the note")
    }
}

/// Pressed rows sink to `surface-2`.
private struct NoteRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? TG.Colors.surface2 : .clear)
    }
}

// MARK: - Preview

struct NoteRowGallery: View {
    var body: some View {
        TGGroup {
            NoteRow(title: "Weekend in Gdańsk",
                    preview: "Train Fri 17:40 · book the place near the old town · pack rain jackets",
                    updated: "Yesterday", by: .sam, showSpace: .shared)
            RowSeparator(inset: TG.Space.s4)
            NoteRow(title: "Wi‑Fi and building info",
                    preview: "Network: Wola-Home · Intercom code at the front desk · Bins go out Tuesday",
                    updated: "Mon", by: .alex)
            RowSeparator(inset: TG.Space.s4)
            NoteRow(title: "Gift ideas for Sam",
                    preview: "Ceramics class voucher, the green scarf from the market",
                    updated: "3 days ago", showSpace: .personal)
        }
        .padding(.vertical, TG.Space.s4)
        .frame(width: 390)
    }
}

#Preview("NoteRow · Light") { NoteRowGallery().catalogCanvas() }
#Preview("NoteRow · Dark") { NoteRowGallery().catalogCanvas().preferredColorScheme(.dark) }
