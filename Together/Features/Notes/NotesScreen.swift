import SwiftUI

/// Notes (HANDOFF §6.5): New note, the active space's notes by last edit, and search (pull down) that only ever
/// looks inside the active space. Tapping a note opens the editor.
struct NotesScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.space) private var space

    @State private var query = ""
    @State private var openNote: Note.ID?
    @Environment(AppRouter.self) private var router

    var body: some View {
        TimelineView(.everyMinute) { _ in
            list(dates: store.dates)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search notes")
        .onChange(of: space) { query = "" }
        // Home's note rows and "Note" quick action open the editor here.
        .onAppear(perform: takeOpenRequest)
        .onChange(of: router.openNote) { takeOpenRequest() }
        .navigationDestination(item: $openNote) { id in
            NoteEditor(noteID: id)
        }
    }

    private func list(dates: RelativeDate) -> some View {
        let all = store.notes(in: space)
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let notes = searching ? store.searchNotes(query, in: space) : all

        return ShellList(subtitle: subtitle(count: all.count)) {
            if !searching {
                Section {
                    TGButton("New note", icon: .plus, variant: .tinted, block: true) { newNote() }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if notes.isEmpty {
                emptyState(searching: searching)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(notes) { note in
                        // Search results carry the space badge (PrivacyBadge README).
                        NoteRow(note: note, dates: dates, me: store.me, showSpace: searching ? space : nil) {
                            openNote = note.id
                        }
                    }
                    .tgListRow()
                }
            }
        }
    }

    @ViewBuilder
    private func emptyState(searching: Bool) -> some View {
        if searching {
            EmptyState(
                title: "No notes match “\(query.trimmingCharacters(in: .whitespaces))”",
                message: "Try another word. Search looks in titles and text.",
                icon: .search
            )
        } else if space == .shared {
            EmptyState(title: "No shared notes yet", message: "Notes here are visible to both of you.", icon: .note)
        } else {
            EmptyState(
                title: "Your private notes",
                message: "Notes here are only for you." + (store.partner.map { " \($0.name) can’t see them." } ?? ""),
                icon: .lock
            )
        }
    }

    private func subtitle(count: Int) -> String {
        let who = space == .shared
            ? store.partner.map { "Shared with \($0.name)" } ?? "Shared space"
            : "Only you can see these"
        return (count == 1 ? "1 note" : "\(count) notes") + " · " + who
    }

    private func takeOpenRequest() {
        guard let id = router.openNote else { return }
        router.openNote = nil
        query = ""
        openNote = id
    }

    private func newNote() {
        openNote = store.createNote(in: space).id
    }
}
