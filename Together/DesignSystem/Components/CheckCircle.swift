import SwiftUI

/// The 26pt round check used by GroceryItem, TaskRow and ReceiptLine (`.tg-check`).
/// Fills with the space colour (120ms), the check draws in (160ms). 44pt hit area.
struct CheckCircle: View {
    let checked: Bool
    /// VoiceOver label naming the result, e.g. "Mark bought: Eggs".
    let label: String
    let action: () -> Void

    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = DS.checkSize

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(checked ? accent.fill : .clear)
                    .animation(.tg(.easeOut(duration: 0.12), reduceMotion: reduceMotion), value: checked)
                Circle()
                    .strokeBorder(checked ? accent.fill : TG.Colors.ink3, lineWidth: DS.checkStroke)
                Icon(.check)
                    .font(TG.Font.footnote.weight(.bold))
                    .foregroundStyle(accent.on)
                    .scaleEffect(checked || reduceMotion ? 1 : 0.6)
                    .opacity(checked ? 1 : 0)
                    .animation(.tg(.easeOut(duration: 0.16), reduceMotion: reduceMotion), value: checked)
            }
            .frame(width: size, height: size)
            .hitArea(size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}
