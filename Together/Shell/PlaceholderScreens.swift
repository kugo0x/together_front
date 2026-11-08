import SwiftUI

// Phase 2 placeholders: each tab shows the active space's mock data with the design-system rows.
// The feature phases (3 Groceries, 4 Tasks, 5 Notes, 6 Home) replace these screens.
// Every read goes through `store.<thing>(in: space)` — never the raw arrays.

/// Reached from the avatar. Settings itself is phase 7.
struct SettingsPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EmptyState(title: "Settings", message: "Partner, suggestions, shopping day and appearance will live here.", icon: .gear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TG.Colors.bg)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
