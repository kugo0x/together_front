import SwiftUI

/// Wrapping row of views (CSS `flex-wrap`) — row metadata and chip rows, so Dynamic Type never clips.
struct FlowLayout: Layout {
    var spacing: CGFloat = TG.Space.s2
    var lineSpacing: CGFloat = DS.rowLineGap

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Lays children side by side at equal widths (CSS `grid-template-columns: 1fr 1fr`).
struct EqualWidthHStack: Layout {
    var minWidth: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let cell = max(sizes.map(\.width).max() ?? 0, minWidth / CGFloat(max(1, subviews.count)))
        return CGSize(width: cell * CGFloat(subviews.count), height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let cell = bounds.width / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + cell * CGFloat(index), y: bounds.minY),
                proposal: ProposedViewSize(width: cell, height: bounds.height)
            )
        }
    }
}

/// A grouped section (`.tg-group`): `surface` on `bg`, `radius-lg`, side gutter `space-4`.
/// For static compositions; inside a `List` use `.listStyle(.insetGrouped)` + `.tgListRow()`.
struct TGGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(TG.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: TG.Radius.lg, style: .continuous))
            .padding(.horizontal, TG.Space.s4)
    }
}

/// Inset hairline between rows of a `TGGroup`.
struct RowSeparator: View {
    var inset: CGFloat = DS.checkRowSeparatorInset

    var body: some View {
        TG.Colors.separator
            .frame(height: DS.hairline)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Row chrome for `List(.insetGrouped)`: no system insets (rows pad themselves), `surface` fill,
    /// `separator` hairlines aligned to the text column.
    func tgListRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(TG.Colors.surface)
            .listRowSeparatorTint(TG.Colors.separator)
    }
}
