import SwiftUI

// Phase 2 placeholders: each tab shows the active space's mock data with the design-system rows.
// The feature phases (3 Groceries, 4 Tasks, 5 Notes, 6 Home) replace these screens.
// Every read goes through `store.<thing>(in: space)` — never the raw arrays.

struct HomeScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.space) private var space

    var body: some View {
        let dates = store.dates
        let upcoming = store.pendingTasks(in: space)
            .prefix(3)
        let toBuy = store.toBuy(in: space)
        let notes = store.notes(in: space).prefix(2)

        ShellList(subtitle: subtitle) {
            ShellSection(title: "Upcoming", count: upcoming.count) {
                if upcoming.isEmpty {
                    emptyRow("Nothing due")
                }
                ForEach(upcoming) { task in
                    TaskRow(task: task, dates: dates, me: store.me) {}
                }
            }
            ShellSection(title: "Groceries", count: toBuy.count) {
                if toBuy.isEmpty {
                    emptyRow("Nothing to buy")
                }
                ForEach(toBuy.prefix(3)) { item in
                    GroceryItemRow(item: item, dates: dates, me: store.me) {}
                }
            }
            ShellSection(title: "Recent notes") {
                if notes.isEmpty {
                    emptyRow("No notes yet")
                }
                ForEach(notes) { note in
                    NoteRow(note: note, dates: dates, me: store.me)
                }
            }
        }
    }

    private var subtitle: String {
        let now = store.now
        let date = store.dates.longDay(now)
        let hour = Calendar.current.component(.hour, from: now)
        let greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return "\(date) · \(greeting), \(store.me.name)"
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(TG.Font.body)
            .foregroundStyle(TG.Colors.ink2)
            .padding(.horizontal, TG.Space.s4)
            .frame(maxWidth: .infinity, minHeight: DS.rowMinHeight, alignment: .leading)
    }
}

struct NotesScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.space) private var space

    var body: some View {
        let dates = store.dates
        let notes = store.notes(in: space)
        let who = space == .shared
            ? store.partner.map { "Shared with \($0.name)" } ?? "Shared space"
            : "Only you can see these"

        ShellList(subtitle: "\(notes.count) notes · \(who)") {
            if notes.isEmpty {
                EmptyState(
                    title: space == .shared ? "No shared notes yet" : "Your private notes",
                    message: space == .shared
                        ? "Notes here are visible to both of you."
                        : "Notes here are only for you. Sam can’t see them.",
                    icon: .note
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(notes) { note in
                        NoteRow(note: note, dates: dates, me: store.me)
                    }
                    .tgListRow()
                }
            }
        }
    }
}

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
