import SwiftUI

/// Edit a grocery item: name, quantity, note. Empty quantity or note clears it (as PATCH does).
struct GroceryEditSheet: View {
    let item: GroceryItem
    let onSave: (_ name: String, _ qty: String?, _ note: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var name: String
    @State private var qty: String
    @State private var note: String
    @FocusState private var nameFocused: Bool

    init(item: GroceryItem, onSave: @escaping (_ name: String, _ qty: String?, _ note: String?) -> Void) {
        self.item = item
        self.onSave = onSave
        _name = State(initialValue: item.name)
        _qty = State(initialValue: item.qty ?? "")
        _note = State(initialValue: item.note ?? "")
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Name", text: $name, prompt: "Oat milk")
                        .focused($nameFocused)
                        .textInputAutocapitalization(.sentences)
                    field("Quantity", text: $qty, prompt: "2, 1 kg, 500 g")
                        .textInputAutocapitalization(.never)
                    field("Note", text: $note, prompt: "For Sunday’s pasta", axis: .vertical)
                }
                .listRowBackground(TG.Colors.surface)
            }
            .font(TG.Font.body)
            .scrollContentBackground(.hidden)
            .background(TG.Colors.bg)
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, qty, note)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .tint(accent.ink)
        .presentationDetents([.medium, .large])
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: DS.rowLineGap) {
            Text(label)
                .font(TG.Font.footnote)
                .foregroundStyle(TG.Colors.ink2)
                .accessibilityHidden(true)
            TextField(label, text: text, prompt: Text(prompt).foregroundStyle(TG.Colors.ink3), axis: axis)
                .foregroundStyle(TG.Colors.ink)
                .accessibilityLabel(label)
                .submitLabel(.done)
                .onSubmit { if canSave { onSave(name, qty, note); dismiss() } }
        }
        .padding(.vertical, TG.Space.s1)
    }
}

#Preview("GroceryEditSheet · Light") {
    Color.clear.sheet(isPresented: .constant(true)) {
        GroceryEditSheet(item: GroceryItem(listID: UUID(), name: "Spinach", note: "For Sunday’s pasta")) { _, _, _ in }
    }
}

#Preview("GroceryEditSheet · Dark") {
    Color.clear.sheet(isPresented: .constant(true)) {
        GroceryEditSheet(item: GroceryItem(listID: UUID(), name: "Oat milk", qty: "2")) { _, _, _ in }
    }
    .preferredColorScheme(.dark)
}
