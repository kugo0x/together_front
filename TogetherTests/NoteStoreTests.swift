import Foundation
import Testing
@testable import Together

/// Notes in `AppStore`, shaped like the backend note API.
@MainActor
struct NoteStoreTests {
    /// A clock the test can move forward.
    final class Clock: @unchecked Sendable {
        var now = instant(2026, 11, 7, 15)
    }

    let clock = Clock()

    func makeStore() -> AppStore {
        let clock = clock
        return AppStore(data: .make(now: clock.now), clock: { clock.now })
    }

    // MARK: List and search

    @Test func listIsMostRecentlyUpdatedFirst() {
        let store = makeStore()
        let dates = store.notes(in: .shared).map(\.updatedAt)
        #expect(dates == dates.sorted(by: >))
        #expect(store.notes(in: .shared).first?.title == "Weekend in Gdańsk")
    }

    @Test func searchNeverReturnsAnotherSpacesNotes() {
        let store = makeStore()
        // "Gift ideas" exists in both spaces: Mum's (Shared) and Sam's (Personal).
        #expect(store.searchNotes("gift ideas", in: .shared).map(\.title) == ["Gift ideas for Mum’s birthday"])
        #expect(store.searchNotes("gift ideas", in: .personal).map(\.title) == ["Gift ideas for Sam"])
        // A word only in a Personal note finds nothing in Shared.
        #expect(store.searchNotes("ceramics", in: .shared).isEmpty)
        #expect(store.searchNotes("ceramics", in: .personal).count == 1)
        for query in ["a", "e", "the", "sam", "weekend"] {
            #expect(store.searchNotes(query, in: .shared).allSatisfy { $0.space == .shared })
        }
    }

    @Test("Case, Polish letters and word prefixes", arguments: [
        ("gdan", "Weekend in Gdańsk"),
        ("GDAŃSK", "Weekend in Gdańsk"),
        ("pierog", "Weekend in Gdańsk"),     // body
        ("charg", "Weekend in Gdańsk"),      // checklist
        ("wi-fi", "Wi‑Fi and building info"),
        ("bins tues", "Wi‑Fi and building info"),
    ])
    func searchMatches(query: String, title: String) {
        let store = makeStore()
        #expect(store.searchNotes(query, in: .shared).map(\.title) == [title])
    }

    @Test func everyWordMustMatchAsAPrefix() {
        let store = makeStore()
        #expect(store.searchNotes("ansk", in: .shared).isEmpty, "not a word prefix")
        #expect(store.searchNotes("weekend mum", in: .shared).isEmpty, "both words must match")
        #expect(store.searchNotes("łódź", in: .shared).isEmpty)
        #expect(AppStore.searchWords("Łódź Gdańsk") == ["lodz", "gdansk"])
    }

    @Test func blankQueryListsEverything() {
        let store = makeStore()
        #expect(store.searchNotes("  ", in: .shared).count == store.notes(in: .shared).count)
    }

    // MARK: Create and edit (version / If-Match)

    @Test func editBumpsVersionAndStaleVersionConflicts() throws {
        let store = makeStore()
        let note = store.createNote(in: .shared, title: "Plan")
        #expect(note.version == 1)
        #expect(note.createdBy == .alex)

        let saved = try #require(try store.updateNote(note.id, in: .shared, title: "Plan v2", body: "Hi", ifMatch: 1)?.get())
        #expect(saved.version == 2)

        // Someone saving from version 1 again loses and gets the current note back.
        guard case .failure(let conflict)? = store.updateNote(note.id, in: .shared, title: "Old", body: "", ifMatch: 1) else {
            Issue.record("expected a version conflict")
            return
        }
        #expect(conflict.current.title == "Plan v2")
        #expect(store.note(note.id, in: .shared)?.title == "Plan v2")
    }

    @Test func checklistChangesDontNeedOrBumpTheVersion() throws {
        let store = makeStore()
        let note = store.createNote(in: .shared, title: "Trip", items: ["Passport"])
        let item = try #require(store.addChecklistItem("Chargers", to: note.id, in: .shared))
        store.updateChecklistItem(item.id, in: note.id, space: .shared, done: true)
        #expect(store.note(note.id, in: .shared)?.version == 1)
        // A title edit from version 1 still goes through.
        #expect((try? store.updateNote(note.id, in: .shared, title: "Trip!", body: "", ifMatch: 1)?.get()) != nil)
    }

    // MARK: Checklist

    @Test func checklistAddToggleRenameReorderDelete() throws {
        let store = makeStore()
        let note = store.createNote(in: .personal, title: "Packing", items: ["Passport", "Chargers"])
        let a = note.checklist[0], b = note.checklist[1]

        let c = try #require(store.addChecklistItem("Tickets", to: note.id, in: .personal, at: 1))
        #expect(store.note(note.id, in: .personal)?.checklist.map(\.label) == ["Passport", "Tickets", "Chargers"])

        let ticked = try #require(store.updateChecklistItem(a.id, in: note.id, space: .personal, done: true))
        #expect(ticked.done && ticked.doneBy == .alex)
        store.updateChecklistItem(a.id, in: note.id, space: .personal, done: false)
        #expect(store.note(note.id, in: .personal)?.checklist[0].doneBy == nil)

        store.updateChecklistItem(c.id, in: note.id, space: .personal, text: "Train tickets")
        store.updateChecklistItem(b.id, in: note.id, space: .personal, position: 0)
        #expect(store.note(note.id, in: .personal)?.checklist.map(\.label) == ["Chargers", "Passport", "Train tickets"])

        store.deleteChecklistItem(a.id, in: note.id, space: .personal)
        #expect(store.note(note.id, in: .personal)?.checklist.map(\.label) == ["Chargers", "Train tickets"])
        #expect(store.note(note.id, in: .personal)?.preview == "Chargers, Train tickets")
    }

    @Test func checklistTickCountsAsAnEdit() throws {
        let store = makeStore()
        let note = try #require(store.notes(in: .shared).first { $0.title == "Weekend in Gdańsk" })
        #expect(note.updatedBy == .sam)
        clock.now = clock.now.addingTimeInterval(60)
        store.updateChecklistItem(note.checklist[1].id, in: note.id, space: .shared, done: true)
        let edited = try #require(store.note(note.id, in: .shared))
        #expect(edited.updatedBy == .alex)
        #expect(edited.updatedAt == clock.now)
        #expect(store.notes(in: .shared).first?.id == note.id)
    }

    // MARK: Move to Shared + Undo

    @Test func moveToSharedAndUndo() throws {
        let store = makeStore()
        let note = try #require(store.notes(in: .personal).first { $0.title == "Weekend plans" })

        let (moved, undo) = try #require(store.moveNote(note.id, from: .personal, to: .shared))
        #expect(moved.space == .shared)
        #expect(undo?.backTo == .personal)
        #expect(store.note(note.id, in: .shared) != nil)
        #expect(store.note(note.id, in: .personal) == nil)
        #expect(!store.searchNotes("exhibition", in: .personal).contains { $0.id == note.id })

        let back = try #require(store.moveNote(note.id, from: .shared, to: .personal))
        #expect(back.note.space == .personal)
        #expect(back.undo == nil)
        #expect(store.note(note.id, in: .personal) != nil)
        #expect(store.notes(in: .shared).allSatisfy { $0.id != note.id })
    }

    @Test func sharedNotesCantMoveToPersonalExceptAsUndo() throws {
        let store = makeStore()
        let shared = try #require(store.notes(in: .shared).first)
        #expect(store.moveNote(shared.id, from: .shared, to: .personal) == nil)
        #expect(store.note(shared.id, in: .shared) != nil)
    }

    @Test func moveUndoExpiresAfterTenMinutes() throws {
        let store = makeStore()
        let note = try #require(store.notes(in: .personal).first)
        _ = try #require(store.moveNote(note.id, from: .personal, to: .shared))
        clock.now = clock.now.addingTimeInterval(601)
        #expect(store.moveNote(note.id, from: .shared, to: .personal) == nil)
        #expect(store.note(note.id, in: .shared) != nil)
    }

    @Test func cantMoveWithoutAPartner() throws {
        let store = makeStore()
        store.partner = nil
        let note = try #require(store.notes(in: .personal).first)
        #expect(store.moveNote(note.id, from: .personal, to: .shared) == nil)
    }

    @Test func notesAreScopedToTheirSpace() throws {
        let store = makeStore()
        let personal = try #require(store.notes(in: .personal).first)
        // Like the API's 404: a Personal note can't be read or changed through Shared.
        #expect(store.note(personal.id, in: .shared) == nil)
        #expect(store.updateNote(personal.id, in: .shared, title: "x", body: "", ifMatch: personal.version) == nil)
        #expect(store.deleteNote(personal.id, in: .shared) == nil)
        #expect(store.addChecklistItem("x", to: personal.id, in: .shared) == nil)
        #expect(store.moveNote(personal.id, from: .shared, to: .personal) == nil)
    }

    // MARK: Delete + Undo

    @Test func deleteAndRestore() throws {
        let store = makeStore()
        let note = try #require(store.notes(in: .shared).first)
        let deleted = try #require(store.deleteNote(note.id, in: .shared))
        #expect(deleted.restoreUntil == clock.now.addingTimeInterval(3600))
        #expect(store.note(note.id, in: .shared) == nil)
        #expect(store.searchNotes(note.title, in: .shared).isEmpty)

        #expect(store.restoreNote(note.id, in: .personal) == nil, "restore is scoped to the space too")
        let restored = try #require(store.restoreNote(note.id, in: .shared))
        #expect(restored == note)
        #expect(store.restoreNote(note.id, in: .shared) == nil, "only once")
        #expect(store.notes(in: .shared).filter { $0.id == note.id }.count == 1)
    }

    @Test func restoreWindowIsOneHour() throws {
        let store = makeStore()
        let note = try #require(store.notes(in: .shared).first)
        store.deleteNote(note.id, in: .shared)
        clock.now = clock.now.addingTimeInterval(3601)
        #expect(store.restoreNote(note.id, in: .shared) == nil)
    }

    // MARK: Row text

    @Test func untitledNotesShowTheirFirstLine() {
        let note = Note(space: .shared, title: " ", body: "Milk\nBread", updatedAt: .now, updatedBy: .alex)
        #expect(note.displayTitle == "Milk")
        #expect(note.preview == "Bread")
        let list = Note(space: .shared, title: "", body: "", checklist: [.init(label: "Passport")], updatedAt: .now, updatedBy: .alex)
        #expect(list.displayTitle == "Checklist")
        #expect(list.preview == "Passport")
        #expect(Note(space: .shared, title: "", body: " ", updatedAt: .now, updatedBy: .alex).isEmpty)
    }
}
