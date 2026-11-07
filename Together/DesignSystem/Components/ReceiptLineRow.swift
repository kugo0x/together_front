import SwiftUI

/// How a scanned receipt line relates to the list.
enum ReceiptLineStatus: String, Codable, Sendable {
    /// On your list → will be marked bought.
    case matched
    /// Bought but not on the list → goes to history only.
    case extra
    /// OCR couldn't read it → tap to fix.
    case unclear

    var label: String {
        switch self {
        case .matched: "On your list"
        case .extra: "Not on your list"
        case .unclear: "Couldn’t read — tap to fix"
        }
    }
}

/// One line read from a receipt in the review step. Nothing is applied until the review is confirmed.
/// Named `ReceiptLineRow` so the model can be `ReceiptLine` (HANDOFF §4).
struct ReceiptLineRow: View {
    let name: String
    /// "2 × 4,99"
    var qty: String?
    /// Formatted with a comma decimal: "12,50 zł".
    let price: String
    var status: ReceiptLineStatus = .matched
    var included = true
    var onToggle: () -> Void = {}
    /// Tap action for unclear lines.
    var onFix: () -> Void = {}

    @ScaledMetric(relativeTo: .body) private var flagSize: CGFloat = DS.checkSize

    var body: some View {
        HStack(spacing: TG.Space.s3) {
            if status == .unclear {
                Text(verbatim: "?")
                    .font(TG.Font.footnote.weight(.bold))
                    .foregroundStyle(TG.Colors.warning)
                    .frame(width: flagSize, height: flagSize)
                    .overlay(Circle().strokeBorder(TG.Colors.warning, style: StrokeStyle(lineWidth: DS.checkStroke, dash: [3, 2.5])))
                    .accessibilityHidden(true)
            } else {
                CheckCircle(checked: included, label: (included ? "Exclude " : "Include ") + name, action: onToggle)
            }

            VStack(alignment: .leading, spacing: DS.rowLineGap) {
                Text(name)
                    .font(TG.Font.body)
                    .foregroundStyle(TG.Colors.ink)
                    .lineLimit(2)
                Text((qty.map { "\($0) · " } ?? "") + status.label)
                    .font(TG.Font.footnote)
                    .fontWeight(status == .unclear ? .medium : nil)
                    .foregroundStyle(status == .unclear ? TG.Colors.warning : TG.Colors.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }

            Text(price)
                .font(TG.Font.subhead)
                .monospacedDigit()
                .foregroundStyle(TG.Colors.ink)
        }
        .padding(.vertical, TG.Space.s3)
        .padding(.horizontal, TG.Space.s4)
        .frame(minHeight: DS.rowMinHeight)
        .contentShape(Rectangle())
        .onTapGesture { if status == .unclear { onFix() } }
        .accessibilityElement(children: status == .unclear ? .combine : .contain)
        .accessibilityAddTraits(status == .unclear ? .isButton : [])
    }
}

// MARK: - Preview

struct ReceiptLineGallery: View {
    @State private var milk = true
    @State private var bread = true
    @State private var chocolate = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "On your list", count: 2)
            TGGroup {
                ReceiptLineRow(name: "Oat milk", qty: "2 × 4,99", price: "9,98 zł", included: milk) { milk.toggle() }
                RowSeparator()
                ReceiptLineRow(name: "Sourdough bread", price: "12,50 zł", included: bread) { bread.toggle() }
            }
            Spacer().frame(height: TG.Space.s4)
            SectionHeader(title: "Not on your list", count: 2)
            TGGroup {
                ReceiptLineRow(name: "Dark chocolate", price: "7,99 zł", status: .extra, included: chocolate) { chocolate.toggle() }
                RowSeparator()
                ReceiptLineRow(name: "SPN DSH 2PK", price: "5,49 zł", status: .unclear)
            }
        }
        .padding(.vertical, TG.Space.s4)
        .frame(width: 390)
    }
}

#Preview("ReceiptLine · Light") { ReceiptLineGallery().catalogCanvas() }
#Preview("ReceiptLine · Dark") { ReceiptLineGallery().catalogCanvas().preferredColorScheme(.dark) }
