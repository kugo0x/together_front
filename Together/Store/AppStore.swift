import UIKit
import Foundation
import Observation

/// The app's state. Offline (UI tests, previews) it is seeded with `MockData`; signed in against the API it starts
/// empty and `RemoteSync` fills it from the server, sends every change (`sync?.record`) and applies the partner's
/// changes from the event stream. Changes are applied here first (optimistic UI) and rolled back by `RemoteSync`
/// when the server refuses them.
///
/// Views never filter the raw arrays themselves: they ask for a space (`groceries(in:)`, `tasks(in:)`, …),
/// so a Personal item can't leak into a Shared view by a forgotten filter. Grocery methods mirror the
/// backend grocery API (`back/api/openapi.yaml`) one-to-one, so swapping in network calls later keeps
/// the call sites; like the API, every item operation is scoped to a space and fails (returns `nil`)
/// for an item of another space.
@MainActor
@Observable
final class AppStore {
    /// The signed-in person.
    var me: Person = .alex
    /// My display name (onboarding "What should we call you?", Settings). `me` stays the identity.
    var myName = "Alex"
    /// My profile picture, picked in Settings (JPEG/PNG data; `PUT /v1/me/avatar`). Shown at once via `avatarPhotos`.
    var myAvatar: Data? {
        didSet {
            guard myAvatar != oldValue else { return }
            avatarPhotos[me.id] = myAvatar.flatMap(UIImage.init(data:))
            record(.avatarChanged(myAvatar))
        }
    }
    /// Profile photos by person, from the server (`avatar.url` on `/v1/me` and the members) or just picked here.
    /// Someone without one shows their initial.
    var avatarPhotos: [Person.ID: UIImage] = [:]
    /// Settings → Notifications (`/v1/me/settings` `notifications`).
    var notificationPrefs = NotificationPrefs() {
        didSet {
            if notificationPrefs.taskReminders != oldValue.taskReminders { resyncReminders() }
            if notificationPrefs != oldValue { record(.settingsChanged) }
        }
    }
    /// The other member of the Shared space, `nil` while alone.
    var partner: Person? = .sam
    /// Settings → "Suggestions" (phase 7). Off hides the card; nothing is ever added automatically either way.
    var suggestionsEnabled = true {
        didSet { if suggestionsEnabled != oldValue { record(.settingsChanged) } }
    }
    /// Settings → "Shopping day", a `Calendar` weekday (1 = Sunday … 7 = Saturday).
    var shoppingDay = 7 {
        didSet { if shoppingDay != oldValue { record(.shoppingDayChanged(shoppingDay)) } }
    }

    // The arrays are only written by this type and by `RemoteSync` (server state); views read them through the
    // space-scoped accessors below so nothing Personal can leak into a Shared view.
    var lists: [GroceryList]
    var groceryItems: [GroceryItem]
    var tasks: [TaskItem]
    var notes: [Note]
    var trips: [Trip]
    var suggestionsBySpace: [SpaceKind: [Suggestion]]
    private(set) var sampleReceipt: [ReceiptLine]
    @ObservationIgnored var deletedNotes: [Note.ID: DeletedNote] = [:]
    @ObservationIgnored var moveUndos: [Note.ID: MoveUndo] = [:]

    /// Each person's do-not-disturb window (Settings; the API keeps it per user).
    var quietHours: [Person: QuietHours] = [.alex: .default, .sam: .default] {
        didSet {
            if let mine = quietHours[me], mine != oldValue[me] { record(.quietHoursChanged(mine)) }
        }
    }

    /// Sends changes to the server (signed in against the API); `nil` offline (tests, previews).
    @ObservationIgnored weak var sync: StoreSync?
    /// True while server state is being applied: those writes aren't changes to send back.
    @ObservationIgnored var applyingServerState = false
    /// What the offline banner shows.
    var connection: ConnectionState = .online
    /// False until the first load from the server is done (the tabs show a loading state instead of "Nothing to
    /// buy"); always true on fakes.
    var hasLoaded = true
    /// Notes whose title/body were merged with the partner's version after a conflict — the editor reloads them
    /// and says so. The value changes with every merge.
    var noteMerges: [Note.ID: Int] = [:]

    @ObservationIgnored private let clock: @Sendable () -> Date
    /// The zone due dates, repeats and reminders are computed in (the device's; Europe/Warsaw in tests).
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored let notifier: ReminderNotifying

    init(
        data: MockData = .make(),
        clock: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = .current,
        notifier: ReminderNotifying = NoReminderNotifications()
    ) {
        lists = data.lists
        groceryItems = data.groceries
        tasks = data.tasks
        notes = data.notes
        trips = data.trips
        suggestionsBySpace = data.suggestions
        sampleReceipt = data.receipt
        self.clock = clock
        self.calendar = calendar
        self.notifier = notifier
        for space in SpaceKind.allCases { _ = defaultList(for: space) }
    }

    var now: Date { clock() }

    // MARK: Grocery lists — GET/POST /v1/spaces/{id}/lists

    /// The list the MVP UI shows for a space; created on first use so every space always has one.
    @discardableResult
    func defaultList(for space: SpaceKind) -> GroceryList {
        if let list = lists.first(where: { $0.space == space && $0.isDefault }) { return list }
        let list = GroceryList(space: space)
        lists.append(list)
        return list
    }

    func lists(in space: SpaceKind) -> [GroceryList] { lists.filter { $0.space == space } }

    func space(of item: GroceryItem) -> SpaceKind? { lists.first { $0.id == item.listID }?.space }

    // MARK: Grocery items — GET /v1/spaces/{id}/lists/{listID}

    /// Items on the space's default list, in API order: to buy (newest first), then bought (most recent first).
    func groceries(in space: SpaceKind) -> [GroceryItem] { toBuy(in: space) + bought(in: space) }

    func toBuy(in space: SpaceKind) -> [GroceryItem] { defaultListItems(space).filter { !$0.done } }

    func bought(in space: SpaceKind) -> [GroceryItem] {
        defaultListItems(space).filter(\.done).sorted { ($0.boughtAt ?? .distantPast) > ($1.boughtAt ?? .distantPast) }
    }

    func item(_ id: GroceryItem.ID, in space: SpaceKind) -> GroceryItem? {
        groceryItems.first { $0.id == id && self.space(of: $0) == space }
    }

    /// POST …/lists/{listID}/items with `text` — the quick-add field ("2 oat milk" → Oat milk, qty 2).
    /// Blank input adds nothing.
    @discardableResult
    func addItem(text: String, in space: SpaceKind) -> GroceryItem? {
        guard let parsed = QuantityParser.groceryInput(text) else { return nil }
        return addItem(name: parsed.name, qty: parsed.qty, in: space)
    }

    /// POST …/lists/{listID}/items with explicit fields. New items go to the top of To buy.
    @discardableResult
    func addItem(name: String, qty: String? = nil, note: String? = nil, in space: SpaceKind) -> GroceryItem? {
        guard let name = Self.clean(name, max: Limits.name) else { return nil }
        let item = GroceryItem(
            listID: defaultList(for: space).id,
            name: name,
            qty: qty.flatMap { Self.clean($0, max: Limits.qty) },
            note: note.flatMap { Self.clean($0, max: Limits.note) },
            addedBy: me
        )
        groceryItems.insert(item, at: 0)
        record(.itemAdded(item, space))
        return item
    }

    /// PATCH /v1/spaces/{id}/items/{itemID}: an empty qty or note clears it; an empty name is rejected.
    @discardableResult
    func updateItem(_ id: GroceryItem.ID, in space: SpaceKind, name: String, qty: String?, note: String?) -> GroceryItem? {
        guard let i = index(of: id, in: space), let name = Self.clean(name, max: Limits.name) else { return nil }
        groceryItems[i].name = name
        groceryItems[i].qty = qty.flatMap { Self.clean($0, max: Limits.qty) }
        groceryItems[i].note = note.flatMap { Self.clean($0, max: Limits.note) }
        record(.itemEdited(groceryItems[i], space))
        return groceryItems[i]
    }

    /// POST …/items/{itemID}/bought — "You bought this"; idempotent.
    @discardableResult
    func markBought(_ id: GroceryItem.ID, in space: SpaceKind) -> GroceryItem? {
        guard let i = index(of: id, in: space) else { return nil }
        if !groceryItems[i].done {
            groceryItems[i].done = true
            groceryItems[i].boughtBy = me
            groceryItems[i].boughtAt = now
            groceryItems[i].viaReceipt = false
            record(.itemBought(id, space))
        }
        return groceryItems[i]
    }

    /// DELETE …/items/{itemID}/bought — back to To buy (Undo, or unchecking).
    @discardableResult
    func unmarkBought(_ id: GroceryItem.ID, in space: SpaceKind) -> GroceryItem? {
        guard let i = index(of: id, in: space) else { return nil }
        let wasDone = groceryItems[i].done
        groceryItems[i].done = false
        groceryItems[i].boughtBy = nil
        groceryItems[i].boughtAt = nil
        groceryItems[i].viaReceipt = false
        if wasDone { record(.itemUnbought(id, space)) }
        return groceryItems[i]
    }

    /// What `removeItem` took away, so Undo can put it back where it was.
    struct RemovedItem {
        let item: GroceryItem
        let space: SpaceKind
        fileprivate let index: Int
    }

    /// DELETE /v1/spaces/{id}/items/{itemID} — no confirm; the screen offers Undo.
    @discardableResult
    func removeItem(_ id: GroceryItem.ID, in space: SpaceKind) -> RemovedItem? {
        guard let i = index(of: id, in: space) else { return nil }
        let removed = RemovedItem(item: groceryItems.remove(at: i), space: space, index: i)
        record(.itemRemoved(removed.item, space))
        return removed
    }

    /// Undo for `removeItem` (the API re-adds the item).
    func undoRemove(_ removed: RemovedItem) {
        guard !groceryItems.contains(where: { $0.id == removed.item.id }) else { return }
        groceryItems.insert(removed.item, at: min(removed.index, groceryItems.count))
        record(.itemRestored(removed.item, removed.space))
    }

    // MARK: Suggestions — /v1/spaces/{id}/suggestions, /dismiss, /accept

    /// At most 4, only while suggestions are on. Never added without a tap.
    func suggestions(in space: SpaceKind) -> [Suggestion] {
        guard suggestionsEnabled else { return [] }
        return Array((suggestionsBySpace[space] ?? []).prefix(4))
    }

    /// "Not this week" — hides the suggestion (for both partners on the server).
    func dismissSuggestion(named name: String, in space: SpaceKind) {
        hideSuggestion(named: name, in: space)
        record(.suggestionDismissed(name, space))
    }

    private func hideSuggestion(named name: String, in space: SpaceKind) {
        suggestionsBySpace[space]?.removeAll { $0.name == name }
    }

    /// Add (one) or Add all: puts the suggestions on the default list with their usual quantity,
    /// in the card's order at the top of To buy. Something already on the list isn't added twice.
    @discardableResult
    func acceptSuggestions(named names: [String], in space: SpaceKind) -> [GroceryItem] {
        let picked = suggestions(in: space).filter { names.contains($0.name) }
        let open = Set(toBuy(in: space).map { $0.name.lowercased() })
        var added: [GroceryItem] = []
        withoutRecording {
            for suggestion in picked.reversed() where !open.contains(suggestion.name.lowercased()) {
                if let item = addItem(name: suggestion.name, qty: suggestion.qty, in: space) { added.insert(item, at: 0) }
            }
            for suggestion in picked { hideSuggestion(named: suggestion.name, in: space) }
        }
        if !picked.isEmpty { record(.suggestionsAccepted(picked.map(\.name), added: added, space)) }
        return added
    }

    // MARK: Trips — GET /v1/spaces/{id}/trips

    func trips(in space: SpaceKind) -> [Trip] {
        trips.filter { $0.space == space }.sorted { $0.date > $1.date }
    }

    func recentTrips(in space: SpaceKind, limit: Int = 2) -> [Trip] { Array(trips(in: space).prefix(limit)) }

    // MARK: Tasks — /v1/spaces/{id}/tasks, …/complete, …/reopen, …/reminder

    /// What the task sheet sends (POST, or a full PATCH). `reminderAt` is the time asked for; quiet hours are
    /// applied here, like the server does.
    struct TaskDraft: Equatable {
        var title: String
        var notes: String?
        var dueDay: CalendarDay?
        var repeatRule: RepeatRule?
        var assignee: Person?
        var reminderAt: Date?
    }

    /// Result of completing a task.
    struct TaskCompletion {
        let task: TaskItem
        /// Repeating: the due date moved forward instead of the task closing.
        let rolled: Bool
        /// How many days the due date moved.
        let days: Int
    }

    /// What `deleteTask` took away, for Undo.
    struct RemovedTask {
        let task: TaskItem
        fileprivate let index: Int
    }

    func tasks(in space: SpaceKind) -> [TaskItem] { tasks.filter { $0.space == space } }

    /// GET …/tasks?view=active — by due date, undated last.
    func activeTasks(in space: SpaceKind) -> [TaskItem] {
        let active = tasks(in: space).filter { !$0.done }
        return active.enumerated().sorted { a, b in
            switch (a.element.dueDay, b.element.dueDay) {
            case let (x?, y?) where x != y: x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Kept for the Home placeholder.
    func pendingTasks(in space: SpaceKind) -> [TaskItem] { activeTasks(in: space) }

    /// GET …/tasks?view=done — latest first.
    func doneTasks(in space: SpaceKind) -> [TaskItem] {
        tasks(in: space).filter(\.done).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    func task(_ id: TaskItem.ID, in space: SpaceKind) -> TaskItem? {
        tasks.first { $0.id == id && $0.space == space }
    }

    /// Who a task's reminder would go to: the assignee (Personal: always me). `nil` = Anyone → no reminder.
    func reminderRecipient(assignee: Person?, in space: SpaceKind) -> Person? {
        space == .personal ? me : assignee
    }

    /// POST /v1/spaces/{id}/tasks — only the title is required.
    @discardableResult
    func createTask(_ draft: TaskDraft, in space: SpaceKind) -> TaskItem? {
        guard let title = Self.clean(draft.title, max: Limits.taskTitle) else { return nil }
        var task = TaskItem(space: space, title: title, createdBy: me)
        apply(draft, to: &task, title: title)
        tasks.insert(task, at: 0)
        syncNotification(task)
        record(.taskCreated(task, draft))
        return task
    }

    /// PATCH /v1/spaces/{id}/tasks/{taskID} with every field (the sheet edits them all).
    @discardableResult
    func updateTask(_ id: TaskItem.ID, in space: SpaceKind, with draft: TaskDraft) -> TaskItem? {
        guard let i = taskIndex(id, in: space), let title = Self.clean(draft.title, max: Limits.taskTitle) else { return nil }
        let before = tasks[i]
        apply(draft, to: &tasks[i], title: title)
        syncNotification(tasks[i])
        record(.taskEdited(tasks[i], draft, before: before))
        return tasks[i]
    }

    /// POST …/complete — one-off: done. Repeating: stays open, due date rolls to the next occurrence after
    /// today and the reminder rolls with it. Completing a done task changes nothing (`nil`).
    @discardableResult
    func completeTask(_ id: TaskItem.ID, in space: SpaceKind) -> TaskCompletion? {
        guard let i = taskIndex(id, in: space), !tasks[i].done else { return nil }
        let before = tasks[i]
        let now = now
        tasks[i].lastDoneAt = now
        tasks[i].lastDoneBy = me
        var rolled = false, days = 0
        if let rule = tasks[i].repeatRule, let due = tasks[i].dueDay {
            let next = rule.nextOccurrence(after: due, anchorDay: tasks[i].anchorDay, today: today)
            days = due.days(until: next)
            tasks[i].previousDueDay = due
            tasks[i].dueDay = next
            tasks[i].reminder = moved(tasks[i].reminder, byDays: days)
            rolled = true
        } else {
            tasks[i].done = true
            tasks[i].doneBy = me
            tasks[i].doneAt = now
        }
        syncNotification(tasks[i])
        record(.taskCompleted(before))
        return TaskCompletion(task: tasks[i], rolled: rolled, days: days)
    }

    /// POST …/reopen — Undo of a completion: reopens a done task, or rolls a repeating one back.
    @discardableResult
    func reopenTask(_ id: TaskItem.ID, in space: SpaceKind) -> TaskItem? {
        guard let i = taskIndex(id, in: space) else { return nil }
        if tasks[i].done {
            tasks[i].done = false
            tasks[i].doneBy = nil
            tasks[i].doneAt = nil
        } else if tasks[i].repeatRule != nil, let previous = tasks[i].previousDueDay, let due = tasks[i].dueDay {
            tasks[i].reminder = moved(tasks[i].reminder, byDays: due.days(until: previous))
            tasks[i].dueDay = previous
            tasks[i].previousDueDay = nil
            tasks[i].lastDoneAt = nil
            tasks[i].lastDoneBy = nil
        } else {
            return nil
        }
        syncNotification(tasks[i])
        record(.taskReopened(tasks[i]))
        return tasks[i]
    }

    /// DELETE /v1/spaces/{id}/tasks/{taskID} — with its reminder.
    @discardableResult
    func deleteTask(_ id: TaskItem.ID, in space: SpaceKind) -> RemovedTask? {
        guard let i = taskIndex(id, in: space) else { return nil }
        let task = tasks.remove(at: i)
        notifier.cancel(id: task.id.uuidString)
        record(.taskDeleted(task))
        return RemovedTask(task: task, index: i)
    }

    func undoDeleteTask(_ removed: RemovedTask) {
        guard !tasks.contains(where: { $0.id == removed.task.id }) else { return }
        tasks.insert(removed.task, at: min(removed.index, tasks.count))
        syncNotification(removed.task)
        record(.taskRestored(removed.task))
    }

    /// Plans a reminder for the sheet's preview and for saving: quiet hours of the recipient applied.
    func planReminder(at requested: Date, for recipient: Person) -> TaskReminder {
        TaskReminder.plan(at: requested, for: recipient, quiet: quietHours[recipient] ?? .default, calendar: calendar)
    }

    var today: CalendarDay { CalendarDay(now, calendar: calendar) }

    /// Date wording in the store's clock and zone.
    var dates: RelativeDate { RelativeDate(now: now, calendar: calendar) }

    // MARK: Notes — /v1/spaces/{id}/notes, …/move, …/restore, …/items

    /// A title/body save lost to a newer version (PATCH → 409 `version_conflict`); `current` is the note as it is now.
    struct NoteConflict: Error {
        let current: Note
    }

    /// A deleted note, restorable until `restoreUntil` (the API keeps it for an hour).
    struct DeletedNote {
        let note: Note
        let restoreUntil: Date
    }

    /// Where and until when a move can be undone (the API allows 10 minutes, same person).
    struct MoveUndo: Equatable {
        let noteID: Note.ID
        let backTo: SpaceKind
        let until: Date
    }

    /// GET …/notes — most recently updated first.
    func notes(in space: SpaceKind) -> [Note] {
        notes.filter { $0.space == space }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// GET …/notes?q= — titles, bodies and checklist text of THIS space only. Case and Polish letters don't
    /// matter ("gdan" finds "Gdańsk"); every word must match as a word prefix.
    func searchNotes(_ query: String, in space: SpaceKind) -> [Note] {
        let terms = Self.searchWords(query)
        guard !terms.isEmpty else { return notes(in: space) }
        return notes(in: space).filter { note in
            let words = Self.searchWords(([note.title, note.body] + note.checklist.map(\.label)).joined(separator: " "))
            return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
        }
    }

    func note(_ id: Note.ID, in space: SpaceKind) -> Note? {
        notes.first { $0.id == id && $0.space == space }
    }

    /// POST …/notes — plain text plus an optional checklist.
    @discardableResult
    func createNote(in space: SpaceKind, title: String = "", body: String = "", items: [String] = []) -> Note {
        let now = now
        let note = Note(
            space: space,
            title: String(title.prefix(Limits.noteTitle)),
            body: String(body.prefix(Limits.noteBody)),
            checklist: items.prefix(Limits.noteItems).map { ChecklistItem(label: String($0.prefix(Limits.noteItem))) },
            updatedAt: now,
            updatedBy: me,
            createdBy: me
        )
        notes.append(note)
        record(.noteCreated(note))
        return note
    }

    /// PATCH …/notes/{id} with `If-Match: version`. A stale version fails with the current note to merge.
    func updateNote(
        _ id: Note.ID, in space: SpaceKind, title: String, body: String, ifMatch version: Int
    ) -> Result<Note, NoteConflict>? {
        guard let i = noteIndex(id, in: space) else { return nil }
        guard notes[i].version == version else { return .failure(NoteConflict(current: notes[i])) }
        let base = notes[i]
        notes[i].title = String(title.prefix(Limits.noteTitle))
        notes[i].body = String(body.prefix(Limits.noteBody))
        notes[i].version += 1
        touch(i)
        record(.noteEdited(notes[i], base: base))
        return .success(notes[i])
    }

    /// DELETE …/notes/{id} — soft; `restoreNote` brings it back within the hour.
    @discardableResult
    func deleteNote(_ id: Note.ID, in space: SpaceKind) -> DeletedNote? {
        guard let i = noteIndex(id, in: space) else { return nil }
        let deleted = DeletedNote(note: notes.remove(at: i), restoreUntil: now.addingTimeInterval(3600))
        deletedNotes[id] = deleted
        record(.noteDeleted(deleted.note))
        return deleted
    }

    /// POST …/notes/{id}/restore — Undo of a delete; `nil` once the window has passed (410).
    @discardableResult
    func restoreNote(_ id: Note.ID, in space: SpaceKind) -> Note? {
        guard let deleted = deletedNotes[id], deleted.note.space == space, now <= deleted.restoreUntil else { return nil }
        deletedNotes[id] = nil
        notes.append(deleted.note)
        record(.noteRestored(deleted.note))
        return deleted.note
    }

    /// POST …/notes/{id}/move — the only way a note changes space: my Personal note into Shared (after the
    /// ConfirmSheet), or the Undo of that move within 10 minutes. Returns the note and, for a forward move, the undo.
    func moveNote(_ id: Note.ID, from space: SpaceKind, to target: SpaceKind) -> (note: Note, undo: MoveUndo?)? {
        guard let i = noteIndex(id, in: space), space != target else { return nil }
        if space == .personal, target == .shared {
            guard partner != nil else { return nil } // no Shared space to move into yet
            notes[i].space = .shared
            touch(i)
            let undo = MoveUndo(noteID: id, backTo: .personal, until: now.addingTimeInterval(600))
            moveUndos[id] = undo
            record(.noteMoved(notes[i], from: space))
            return (notes[i], undo)
        }
        // Back to Personal: only as the Undo of my own move, in time.
        guard let undo = moveUndos[id], undo.backTo == target, now <= undo.until else { return nil }
        moveUndos[id] = nil
        notes[i].space = target
        touch(i)
        record(.noteMoved(notes[i], from: space))
        return (notes[i], nil)
    }

    // Checklist lines — never conflict with text edits, so they don't need or bump the version.

    /// POST …/notes/{id}/items — at the end, or at `position`.
    @discardableResult
    func addChecklistItem(_ text: String, to id: Note.ID, in space: SpaceKind, at position: Int? = nil) -> ChecklistItem? {
        guard let i = noteIndex(id, in: space), notes[i].checklist.count < Limits.noteItems else { return nil }
        let item = ChecklistItem(label: String(text.prefix(Limits.noteItem)))
        let at = min(max(position ?? notes[i].checklist.count, 0), notes[i].checklist.count)
        notes[i].checklist.insert(item, at: at)
        touch(i)
        record(.checklistAdded(item, note: id, at: at, space))
        return item
    }

    /// PATCH …/items/{itemID} — tick, rename or reorder one line.
    @discardableResult
    func updateChecklistItem(
        _ itemID: ChecklistItem.ID, in noteID: Note.ID, space: SpaceKind,
        text: String? = nil, done: Bool? = nil, position: Int? = nil
    ) -> ChecklistItem? {
        guard let i = noteIndex(noteID, in: space),
              var j = notes[i].checklist.firstIndex(where: { $0.id == itemID }) else { return nil }
        if let text { notes[i].checklist[j].label = String(text.prefix(Limits.noteItem)) }
        if let done, done != notes[i].checklist[j].done {
            notes[i].checklist[j].done = done
            notes[i].checklist[j].doneBy = done ? me : nil
            notes[i].checklist[j].doneAt = done ? now : nil
        }
        if let position {
            let item = notes[i].checklist.remove(at: j)
            j = min(max(position, 0), notes[i].checklist.count)
            notes[i].checklist.insert(item, at: j)
        }
        touch(i)
        record(.checklistEdited(itemID, note: noteID, text: text, done: done, position: position, space))
        return notes[i].checklist[j]
    }

    /// DELETE …/items/{itemID}.
    @discardableResult
    func deleteChecklistItem(_ itemID: ChecklistItem.ID, in noteID: Note.ID, space: SpaceKind) -> ChecklistItem? {
        guard let i = noteIndex(noteID, in: space),
              let j = notes[i].checklist.firstIndex(where: { $0.id == itemID }) else { return nil }
        let item = notes[i].checklist.remove(at: j)
        touch(i)
        record(.checklistDeleted(itemID, note: noteID, space))
        return item
    }

    // MARK: Receipts — /v1/spaces/{id}/receipts/match, POST /v1/spaces/{id}/receipts

    /// What a receipt can match: the open items, and ticks of the last 24 h (not yet filed into a trip).
    func receiptCandidates(in space: SpaceKind) -> [ReceiptCandidate] {
        let since = now.addingTimeInterval(-24 * 3600)
        let open = toBuy(in: space).map { ReceiptCandidate(itemID: $0.id, name: $0.name) }
        let recent = bought(in: space)
            .filter { ($0.boughtAt ?? .distantPast) >= since && !$0.viaReceipt }
            .map { ReceiptCandidate(itemID: $0.id, name: $0.name, alreadyBought: true) }
        return open + recent
    }

    /// Applies a reviewed receipt — nothing changes before this. Included matched lines mark their items bought
    /// "via receipt" (a tick already there just files into the trip); extras and unclear lines go to history only.
    /// Returns the saved trip and how many items were newly marked bought.
    @discardableResult
    func confirmReceipt(_ review: ReceiptReview, in space: SpaceKind) -> (trip: Trip, bought: Int) {
        let now = now
        var bought = 0
        for line in review.lines where line.included && line.status == .matched {
            guard let candidate = line.match,
                  let i = groceryItems.firstIndex(where: { $0.id == candidate.itemID && self.space(of: $0) == space })
            else { continue }
            if !groceryItems[i].done {
                groceryItems[i].done = true
                groceryItems[i].boughtBy = me
                groceryItems[i].boughtAt = now
                bought += 1
            }
            groceryItems[i].viaReceipt = true
        }
        let included = review.lines.filter(\.included)
        let trip = Trip(
            space: space,
            date: review.date,
            shoppers: [me],
            itemCount: included.count,
            total: review.total,
            merchant: review.merchant,
            receiptImageID: "scan-\(UUID().uuidString)",
            lines: included.map {
                ReceiptLine(name: $0.name, qty: $0.qty, price: $0.price,
                            status: ReceiptLine.Status(rawValue: $0.status.rawValue) ?? .extra)
            }
        )
        trips.append(trip)
        record(.receiptConfirmed(review, trip: trip, space))
        return (trip, bought)
    }

    /// The receipt lines of a trip from the server (History lists trips without them); nothing to do offline.
    func loadLines(of tripID: Trip.ID) async {
        guard let trip = trips.first(where: { $0.id == tripID }), trip.lines.isEmpty, trip.hasReceipt else { return }
        await sync?.loadLines(of: tripID)
    }

    /// History: the space's trips by month, newest first — GET /v1/spaces/{id}/trips?month=.
    func tripMonths(in space: SpaceKind) -> [TripMonth] {
        let grouped = Dictionary(grouping: trips(in: space)) { trip in
            let c = calendar.dateComponents([.year, .month], from: trip.date)
            return TripMonth.Key(year: c.year!, month: c.month!)
        }
        return grouped.map { TripMonth(key: $0.key, trips: $0.value.sorted { $0.date > $1.date }) }
            .sorted { ($0.key.year, $0.key.month) > ($1.key.year, $1.key.month) }
    }

    /// The month line ("Groceries in November · 352,60 zł") for the month `date` falls in.
    func monthSummary(containing date: Date, in space: SpaceKind) -> TripMonth {
        let c = calendar.dateComponents([.year, .month], from: date)
        let key = TripMonth.Key(year: c.year!, month: c.month!)
        return tripMonths(in: space).first { $0.key == key } ?? TripMonth(key: key, trips: [])
    }

    // MARK: Shared space membership — /v1/invites/{code}/accept, /v1/spaces/{id}/leave

    /// Someone joined my Shared space (or I joined theirs).
    func joinPartner(_ person: Person) {
        partner = person
        Task { await sync?.spacesChanged() }
    }

    /// The Shared space was created (first invite) — the server knows it before the store does.
    func sharedSpaceCreated() async {
        await sync?.spacesChanged()
    }

    /// Leave the Shared space: everything in it stays with the partner; I keep only Personal.
    func leaveShared() {
        record(.leftShared)
        partner = nil
        let sharedList = defaultList(for: .shared).id
        groceryItems.removeAll { $0.listID == sharedList }
        for task in tasks where task.space == .shared { notifier.cancel(id: task.id.uuidString) }
        tasks.removeAll { $0.space == .shared }
        notes.removeAll { $0.space == .shared }
        trips.removeAll { $0.space == .shared }
        suggestionsBySpace[.shared] = []
    }

    /// Re-checks every task's local notification (after a settings change).
    func resyncReminders() {
        for task in tasks { syncNotification(task) }
    }

    // MARK: Sync

    private func record(_ change: StoreChange) {
        guard !applyingServerState, !recordingPaused else { return }
        sync?.record(change)
    }

    @ObservationIgnored private var recordingPaused = false

    /// Runs `body` without sending its changes (they are sent as one change by the caller).
    private func withoutRecording(_ body: () -> Void) {
        let paused = recordingPaused
        recordingPaused = true
        body()
        recordingPaused = paused
    }

    /// Applies server state without sending it back.
    func applyingServer(_ body: () -> Void) {
        let applying = applyingServerState
        applyingServerState = true
        body()
        applyingServerState = applying
    }

    // MARK: Private

    /// Field limits from the API (`name` 80, `qty` 20, `note` 140).
    enum Limits {
        static let name = 80, qty = 20, note = 140
        static let taskTitle = 120, taskNotes = 2000
        static let noteTitle = 200, noteBody = 20000, noteItem = 200, noteItems = 200
    }

    private func noteIndex(_ id: Note.ID, in space: SpaceKind) -> Int? {
        notes.firstIndex { $0.id == id && $0.space == space }
    }

    /// "edited just now by you" — any change, checklist ticks included.
    private func touch(_ i: Int) {
        notes[i].updatedAt = now
        notes[i].updatedBy = me
    }

    /// Lowercased words with diacritics (and the Polish ł, which doesn't decompose) folded away.
    static func searchWords(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ł", with: "l")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func taskIndex(_ id: TaskItem.ID, in space: SpaceKind) -> Int? {
        tasks.firstIndex { $0.id == id && $0.space == space }
    }

    /// Validates a draft into a task (API rules): a repeat needs a date; Personal tasks are the owner's;
    /// a reminder needs a recipient (never Anyone) and is shifted out of their quiet hours.
    private func apply(_ draft: TaskDraft, to task: inout TaskItem, title: String) {
        task.title = title
        task.notes = draft.notes.flatMap { Self.clean($0, max: Limits.taskNotes) }
        let rule = draft.dueDay == nil ? nil : draft.repeatRule
        if task.dueDay != draft.dueDay || task.repeatRule != rule {
            task.dueDay = draft.dueDay
            task.repeatRule = rule
            task.previousDueDay = nil
            task.anchorDay = rule == nil ? 0 : draft.dueDay!.day
        }
        task.assignee = task.space == .personal ? me : draft.assignee
        if let recipient = reminderRecipient(assignee: task.assignee, in: task.space), let at = draft.reminderAt {
            task.reminder = planReminder(at: at, for: recipient)
        } else {
            task.reminder = nil
        }
    }

    private func moved(_ reminder: TaskReminder?, byDays days: Int) -> TaskReminder? {
        guard let reminder, days != 0 else { return reminder }
        return reminder.moved(byDays: days, quiet: quietHours[reminder.recipient] ?? .default, calendar: calendar)
    }

    /// Keeps the local notification in step with the task: only my own pending reminders, one per task id.
    func syncNotification(_ task: TaskItem) {
        let id = task.id.uuidString
        guard notificationPrefs.taskReminders,
              !task.done, let reminder = task.reminder, reminder.recipient == me, reminder.remindAt > now else {
            notifier.cancel(id: id)
            return
        }
        let label = task.dueDay.map { ReminderText.dueLabel($0, today: today) }
        notifier.schedule(LocalReminder(
            id: id,
            title: ReminderText.title(setBy: task.createdBy, recipient: me),
            body: [task.title, label].compactMap { $0 }.joined(separator: " · "),
            fireAt: reminder.remindAt
        ))
    }

    private func defaultListItems(_ space: SpaceKind) -> [GroceryItem] {
        let listID = defaultList(for: space).id
        return groceryItems.filter { $0.listID == listID }
    }

    private func index(of id: GroceryItem.ID, in space: SpaceKind) -> Int? {
        groceryItems.firstIndex { $0.id == id && self.space(of: $0) == space }
    }

    /// Trims and caps a field; `nil` when nothing is left.
    private static func clean(_ text: String, max: Int) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(max))
    }
}
