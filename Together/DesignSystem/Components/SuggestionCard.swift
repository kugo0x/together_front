import SwiftUI

/// The weekly "often on your list" card on the space tint. Each item has Skip and Add; nothing is ever
/// added without a tap. Show at most 4 items. No sparkles, no "AI" wording.
struct SuggestionCard: View {
    let items: [Suggestion]
    var title = "Often on your list"
    var onAdd: (Suggestion) -> Void = { _ in }
    var onSkip: (Suggestion) -> Void = { _ in }
    /// Shows a plain "Add all" under the items when set and there is more than one item.
    var onAddAll: (() -> Void)?

    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: TG.Space.s2) {
                Icon(.history).fontWeight(.semibold)
                Text(title)
            }
            .font(TG.Font.subhead.weight(.semibold))
            .foregroundStyle(accent.ink)
            .padding(.bottom, TG.Space.s3)
            .accessibilityAddTraits(.isHeader)

            if items.isEmpty {
                Text("All caught up — nothing else you usually buy.")
                    .font(TG.Font.callout)
                    .foregroundStyle(TG.Colors.ink)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        accent.fill.opacity(0.18).frame(height: DS.hairline)
                    }
                    row(item)
                }
                if let onAddAll, items.count > 1 {
                    HStack {
                        Spacer()
                        TGButton("Add all", variant: .plain, size: .sm, action: onAddAll)
                    }
                    .padding(.top, TG.Space.s2)
                }
            }
        }
        .padding(TG.Space.s4)
        .background(accent.soft, in: RoundedRectangle(cornerRadius: TG.Radius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
    }

    private func row(_ item: Suggestion) -> some View {
        HStack(spacing: TG.Space.s3) {
            VStack(alignment: .leading, spacing: DS.rowLineGap) {
                Text(item.qty.map { "\(Text(item.name).bold()) · \($0)" } ?? "\(Text(item.name).bold())")
                    .font(TG.Font.callout)
                    .foregroundStyle(TG.Colors.ink)
                Text(item.reason)
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            HStack(spacing: TG.Space.s2) {
                Button("Skip") { onSkip(item) }
                    .buttonStyle(.tg(.secondary, size: .sm, secondaryFill: TG.Colors.surface))
                    .accessibilityLabel("Not this week: \(item.name)")
                Button { onAdd(item) } label: {
                    Label { Text("Add") } icon: { Icon(.plus) }
                }
                .buttonStyle(.tg(.primary, size: .sm))
                .accessibilityLabel("Add \(item.name)")
            }
            .fixedSize()
        }
        .padding(.vertical, TG.Space.s2)
    }
}

// MARK: - Preview

struct SuggestionCardGallery: View {
    @State private var items = [
        Suggestion(name: "Eggs", qty: "10", reason: "Bought 6 of the last 7 weeks"),
        Suggestion(name: "Bananas", reason: "Usually every week · last bought 8 days ago"),
        Suggestion(name: "Coffee beans", qty: "500 g", reason: "Every 3 weeks · last bought 20 days ago"),
    ]
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: TG.Space.s4) {
            SuggestionCard(
                items: items,
                onAdd: { remove($0, "Added") },
                onSkip: { remove($0, "Skipped") }
            )
            if !message.isEmpty {
                Text(message).font(TG.Font.footnote).foregroundStyle(TG.Colors.ink2)
            }
        }
        .padding(TG.Space.s4)
        .frame(width: 390)
    }

    private func remove(_ item: Suggestion, _ verb: String) {
        withAnimation { items.removeAll { $0 == item } }
        message = "\(verb) \(item.name)"
    }
}

#Preview("SuggestionCard · Light") { SuggestionCardGallery().catalogCanvas() }
#Preview("SuggestionCard · Dark") { SuggestionCardGallery().catalogCanvas().preferredColorScheme(.dark) }
#Preview("SuggestionCard · Add all, Personal") {
    SuggestionCard(
        items: [
            Suggestion(name: "Eggs", qty: "10", reason: "Bought 6 of the last 7 weeks"),
            Suggestion(name: "Bananas", reason: "Usually every week · last bought 8 days ago"),
        ],
        onAddAll: {}
    )
    .padding(TG.Space.s4)
    .catalogCanvas()
    .environment(\.space, .personal)
}
