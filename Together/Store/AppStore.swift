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

    @ObservationIgnored private let clock: @Sendable () -> Date

    init(data: MockData = .make(), clock: @escaping @Sendable () -> Date = { .now }) {
        lists = data.lists
        groceryItems = data.groceries
        tasks = data.tasks
        notes = data.notes
        trips = data.trips
        suggestionsBySpace = data.suggestions
        sampleReceipt = data.receipt
        self.clock = clock
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

    // MARK: Tasks and notes (phases 4–5 extend these)

    func tasks(in space: SpaceKind) -> [TaskItem] { tasks.filter { $0.space == space } }
    func pendingTasks(in space: SpaceKind) -> [TaskItem] { tasks(in: space).filter { !$0.done } }
    func doneTasks(in space: SpaceKind) -> [TaskItem] { tasks(in: space).filter(\.done) }

    func notes(in space: SpaceKind) -> [Note] {
        notes.filter { $0.space == space }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Completes or reopens a task. Returns the previous value for Undo.
    @discardableResult
    func setTask(_ id: TaskItem.ID, done: Bool) -> TaskItem? {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        let previous = tasks[i]
        tasks[i].done = done
        tasks[i].doneBy = done ? me : nil
        return previous
    }

    func restore(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i] = task
    }

    // MARK: Private

    /// Field limits from the API (`name` 80, `qty` 20, `note` 140).
    enum Limits {
        static let name = 80, qty = 20, note = 140
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
