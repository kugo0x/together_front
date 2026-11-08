import SwiftUI

/// The always-ready field at the bottom of a grocery list: type, press return, done.
/// Leading quantities are parsed ("2 oat milk" → Oat milk, 2). Focus stays in the field after adding,
/// so several items go in a row. The send button uses the space fill and is disabled while empty.
struct QuickAdd: View {
    var placeholder = "Add item"
    /// First-run tip under the field only.
    var hint: String?
    var autoFocus = false
    let onAdd: (_ name: String, _ qty: String?) -> Void

    @State private var text = ""
    @State private var focused = false
    @Environment(\.accent) private var accent
    @ScaledMetric(relativeTo: .body) private var goSize: CGFloat = 38
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 52

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: TG.Space.s2) {
            HStack(spacing: TG.Space.s2) {
                ReturnKeepingTextField(
                    text: $text,
                    isFocused: $focused,
                    placeholder: placeholder,
                    tint: accent.fill,
                    onReturn: submit
                )
                .frame(maxWidth: .infinity)

                Button { submit() } label: {
                    Icon(.arrowUp)
                        .font(TG.Font.body.weight(.semibold))
                        .foregroundStyle(accent.on)
                        .frame(width: goSize, height: goSize)
                        .background(accent.fill, in: Circle())
                }
                .buttonStyle(.bare)
                .disabled(isEmpty)
                .opacity(isEmpty ? 0.35 : 1)
                .animation(.easeOut(duration: 0.12), value: isEmpty)
                .hitArea(goSize)
                .accessibilityLabel("Add")
            }
            .padding(.vertical, 6)
            .padding(.leading, TG.Space.s4)
            .padding(.trailing, 6)
            .frame(minHeight: minHeight)
            .background(TG.Colors.surface, in: RoundedRectangle(cornerRadius: TG.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TG.Radius.md, style: .continuous)
                    .strokeBorder(focused ? accent.fill : TG.Colors.separator, lineWidth: DS.hairline)
            )
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            if let hint {
                Text(hint)
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
                    .padding(.horizontal, TG.Space.s1)
            }
        }
        .onAppear { if autoFocus { focused = true } }
    }

    private func submit() { submit(text) }

    /// Adds the item and clears the field; focus never leaves it (see `ReturnKeepingTextField`).
    private func submit(_ input: String) {
        guard let result = QuantityParser.groceryInput(input) else { return }
        onAdd(result.name, result.qty)
        text = ""
    }
}

// MARK: - Preview

struct QuickAddGallery: View {
    @State private var added: [String] = []

    var body: some View {
        QuickAdd(
            placeholder: "Add to Groceries",
            hint: added.isEmpty ? "Try “2 oat milk” and press return" : "Added: " + added.joined(separator: ", ")
        ) { name, qty in
            added.append([qty, name].compactMap { $0 }.joined(separator: " "))
        }
        .frame(width: 390)
        .padding(TG.Space.s4)
    }
}

#Preview("QuickAdd · Light") { QuickAddGallery().catalogCanvas() }
#Preview("QuickAdd · Dark") { QuickAddGallery().catalogCanvas().preferredColorScheme(.dark) }
#Preview("QuickAdd · Personal") { QuickAddGallery().catalogCanvas().environment(\.space, .personal) }
