import SwiftUI

/// One grocery row: check circle, name, quantity and — once bought — "Sam bought this · 2 min ago"
/// with the person's dot. Named `GroceryItemRow` so the model can be `GroceryItem` (HANDOFF §4).
///
/// Use inside a `TGGroup` or a `List(.insetGrouped)` row with `.tgListRow()`; swipe-to-delete and the
/// 600ms move to "Bought" belong to the screen.
struct GroceryItemRow: View {
    let name: String
    var qty: String?
    /// Short note ("Free-range"), shown while the item is still to buy.
    var note: String?
    var done = false
    var by: Person?
    /// Relative time of the purchase ("2 min ago").
    var when: String?
    var me: Person = .alex
    var onToggle: () -> Void = {}

    private var boughtLine: String? {
        guard done, let by else { return nil }
        return "\(by.displayName(me: me)) bought this" + (when.map { " · \($0)" } ?? "")
    }

    var body: some View {
        HStack(spacing: TG.Space.s3) {
            CheckCircle(checked: done, label: (done ? "Unmark " : "Mark bought: ") + name, action: onToggle)

            VStack(alignment: .leading, spacing: DS.rowLineGap) {
                Text(name)
                    .font(TG.Font.body)
                    .foregroundStyle(done ? TG.Colors.ink2 : TG.Colors.ink)
                    .strikethrough(done, color: TG.Colors.ink3)
                    .lineLimit(2)

                if let boughtLine, let by {
                    HStack(spacing: TG.Space.s2) {
                        Circle().fill(by.color).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(boughtLine)
                    }
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
                } else if let note {
                    Text(note)
                        .font(TG.Font.footnote)
                        .foregroundStyle(TG.Colors.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            .accessibilityElement(children: .combine)
            .accessibilityValue(qty.map { "Quantity \($0)" } ?? "")

            if let qty {
                Text(qty)
                    .font(TG.Font.subhead)
                    .monospacedDigit()
                    .foregroundStyle(TG.Colors.ink2)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, TG.Space.s3)
        .padding(.horizontal, TG.Space.s4)
        .frame(minHeight: DS.rowMinHeight)
    }
}

// MARK: - Preview

struct GroceryItemGallery: View {
    @State private var milk = false
    @State private var eggs = false
    @State private var bread = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "To buy", count: 3)
            TGGroup {
                GroceryItemRow(name: "Oat milk", qty: "2", done: milk, by: .alex, when: "just now") { milk.toggle() }
                RowSeparator()
                GroceryItemRow(name: "Eggs", qty: "10", note: "Free-range", done: eggs, by: .alex, when: "just now") { eggs.toggle() }
                RowSeparator()
                GroceryItemRow(name: "Sourdough bread", done: bread, by: .sam, when: "2 min ago") { bread.toggle() }
                RowSeparator()
                GroceryItemRow(name: "Tomatoes", qty: "1 kg")
            }
        }
        .padding(.vertical, TG.Space.s4)
        .frame(width: 390)
    }
}

/// The same rows in a native inset-grouped List (how screens will use them).
private struct GroceryItemListPreview: View {
    var body: some View {
        List {
            Section {
                GroceryItemRow(name: "Oat milk", qty: "2").tgListRow()
                GroceryItemRow(name: "Eggs", qty: "10", note: "Free-range").tgListRow()
                GroceryItemRow(name: "Sourdough bread", done: true, by: .sam, when: "2 min ago").tgListRow()
            } header: {
                SectionHeader(title: "To buy", count: 3).padding(.horizontal, -TG.Space.s4)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(TG.Colors.bg)
    }
}

#Preview("GroceryItem · Light") { GroceryItemGallery().catalogCanvas() }
#Preview("GroceryItem · Dark") { GroceryItemGallery().catalogCanvas().preferredColorScheme(.dark) }
#Preview("GroceryItem · List") { GroceryItemListPreview() }
