import Foundation
import Observation

/// In-memory app state for the MVP (seeded with `MockData`); phase 9 backs it with the API.
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
    /// The other member of the Shared space, `nil` while alone.
    var partner: Person? = .sam
    /// Settings → "Suggestions" (phase 7). Off hides the card; nothing is ever added automatically either way.
    var suggestionsEnabled = true
    /// Settings → "Shopping day", a `Calendar` weekday (1 = Sunday … 7 = Saturday).
    var shoppingDay = 7

    private(set) var lists: [GroceryList]
    private(set) var groceryItems: [GroceryItem]
    private(set) var tasks: [TaskItem]
    private(set) var notes: [Note]
    private(set) var trips: [Trip]
    private(set) var suggestionsBySpace: [SpaceKind: [Suggestion]]
    private(set) var sampleReceipt: [ReceiptLine]

    /// Each person's do-not-disturb window (Settings later; the API keeps it per user).
    var quietHours: [Person: QuietHours] = [.alex: .default, .sam: .default]

    @ObservationIgnored private let clock: @Sendable () -> Date
    /// The zone due dates, repeats and reminders are computed in (the device's; Europe/Warsaw in tests).
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private let notifier: ReminderNotifying

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
        return item
    }

    /// PATCH /v1/spaces/{id}/items/{itemID}: an empty qty or note clears it; an empty name is rejected.
    @discardableResult
    func updateItem(_ id: GroceryItem.ID, in space: SpaceKind, name: String, qty: String?, note: String?) -> GroceryItem? {
        guard let i = index(of: id, in: space), let name = Self.clean(name, max: Limits.name) else { return nil }
        groceryItems[i].name = name
        groceryItems[i].qty = qty.flatMap { Self.clean($0, max: Limits.qty) }
        groceryItems[i].note = note.flatMap { Self.clean($0, max: Limits.note) }
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
        }
        return groceryItems[i]
    }

    /// DELETE …/items/{itemID}/bought — back to To buy (Undo, or unchecking).
    @discardableResult
    func unmarkBought(_ id: GroceryItem.ID, in space: SpaceKind) -> GroceryItem? {
        guard let i = index(of: id, in: space) else { return nil }
        groceryItems[i].done = false
        groceryItems[i].boughtBy = nil
        groceryItems[i].boughtAt = nil
        groceryItems[i].viaReceipt = false
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
        return RemovedItem(item: groceryItems.remove(at: i), space: space, index: i)
    }

    /// Undo for `removeItem` (the API re-adds the item).
    func undoRemove(_ removed: RemovedItem) {
        guard !groceryItems.contains(where: { $0.id == removed.item.id }) else { return }
        groceryItems.insert(removed.item, at: min(removed.index, groceryItems.count))
    }

    // MARK: Suggestions — /v1/spaces/{id}/suggestions, /dismiss, /accept

    /// At most 4, only while suggestions are on. Never added without a tap.
    func suggestions(in space: SpaceKind) -> [Suggestion] {
        guard suggestionsEnabled else { return [] }
        return Array((suggestionsBySpace[space] ?? []).prefix(4))
    }

    /// "Not this week" — hides the suggestion (for both partners on the server).
    func dismissSuggestion(named name: String, in space: SpaceKind) {
        suggestionsBySpace[space]?.removeAll { $0.name == name }
    }

    /// Add (one) or Add all: puts the suggestions on the default list with their usual quantity,
    /// in the card's order at the top of To buy. Something already on the list isn't added twice.
    @discardableResult
    func acceptSuggestions(named names: [String], in space: SpaceKind) -> [GroceryItem] {
        let picked = suggestions(in: space).filter { names.contains($0.name) }
        let open = Set(toBuy(in: space).map { $0.name.lowercased() })
        var added: [GroceryItem] = []
        for suggestion in picked.reversed() where !open.contains(suggestion.name.lowercased()) {
            if let item = addItem(name: suggestion.name, qty: suggestion.qty, in: space) { added.insert(item, at: 0) }
        }
        for suggestion in picked { dismissSuggestion(named: suggestion.name, in: space) }
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
        return task
    }

    /// PATCH /v1/spaces/{id}/tasks/{taskID} with every field (the sheet edits them all).
    @discardableResult
    func updateTask(_ id: TaskItem.ID, in space: SpaceKind, with draft: TaskDraft) -> TaskItem? {
        guard let i = taskIndex(id, in: space), let title = Self.clean(draft.title, max: Limits.taskTitle) else { return nil }
        apply(draft, to: &tasks[i], title: title)
        syncNotification(tasks[i])
        return tasks[i]
    }

    /// POST …/complete — one-off: done. Repeating: stays open, due date rolls to the next occurrence after
    /// today and the reminder rolls with it. Completing a done task changes nothing (`nil`).
    @discardableResult
    func completeTask(_ id: TaskItem.ID, in space: SpaceKind) -> TaskCompletion? {
        guard let i = taskIndex(id, in: space), !tasks[i].done else { return nil }
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
        return tasks[i]
    }

    /// DELETE /v1/spaces/{id}/tasks/{taskID} — with its reminder.
    @discardableResult
    func deleteTask(_ id: TaskItem.ID, in space: SpaceKind) -> RemovedTask? {
        guard let i = taskIndex(id, in: space) else { return nil }
        let task = tasks.remove(at: i)
        notifier.cancel(id: task.id.uuidString)
        return RemovedTask(task: task, index: i)
    }

    func undoDeleteTask(_ removed: RemovedTask) {
        guard !tasks.contains(where: { $0.id == removed.task.id }) else { return }
        tasks.insert(removed.task, at: min(removed.index, tasks.count))
        syncNotification(removed.task)
    }

    /// Plans a reminder for the sheet's preview and for saving: quiet hours of the recipient applied.
    func planReminder(at requested: Date, for recipient: Person) -> TaskReminder {
        TaskReminder.plan(at: requested, for: recipient, quiet: quietHours[recipient] ?? .default, calendar: calendar)
    }

    var today: CalendarDay { CalendarDay(now, calendar: calendar) }

    /// Date wording in the store's clock and zone.
    var dates: RelativeDate { RelativeDate(now: now, calendar: calendar) }

    // MARK: Notes (phase 5 extends these)

    func notes(in space: SpaceKind) -> [Note] {
        notes.filter { $0.space == space }.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Private

    /// Field limits from the API (`name` 80, `qty` 20, `note` 140).
    enum Limits {
        static let name = 80, qty = 20, note = 140
        static let taskTitle = 120, taskNotes = 2000
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
    private func syncNotification(_ task: TaskItem) {
        let id = task.id.uuidString
        guard !task.done, let reminder = task.reminder, reminder.recipient == me, reminder.remindAt > now else {
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
