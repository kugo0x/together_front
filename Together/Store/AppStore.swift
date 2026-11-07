import Foundation
import Observation

/// In-memory app state for the MVP (seeded with `MockData`); phase 9 backs it with the API.
///
/// Views never filter the raw arrays themselves: they ask for a space (`groceries(in:)`, `tasks(in:)`, …),
/// so a Personal item can't leak into a Shared view by a forgotten filter.
@MainActor
@Observable
final class AppStore {
    /// The signed-in person.
    var me: Person = .alex
    /// The other member of the Shared space, `nil` while alone.
    var partner: Person? = .sam

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

    // MARK: Grocery lists

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

    // MARK: Space-scoped reads

    /// Items on the space's default list, newest first as stored.
    func groceries(in space: SpaceKind) -> [GroceryItem] {
        let listID = defaultListID(for: space)
        return groceryItems.filter { $0.listID == listID }
    }

    func toBuy(in space: SpaceKind) -> [GroceryItem] { groceries(in: space).filter { !$0.done } }
    func bought(in space: SpaceKind) -> [GroceryItem] { groceries(in: space).filter(\.done) }

    func tasks(in space: SpaceKind) -> [TaskItem] { tasks.filter { $0.space == space } }
    func pendingTasks(in space: SpaceKind) -> [TaskItem] { tasks(in: space).filter { !$0.done } }
    func doneTasks(in space: SpaceKind) -> [TaskItem] { tasks(in: space).filter(\.done) }

    func notes(in space: SpaceKind) -> [Note] {
        notes.filter { $0.space == space }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func trips(in space: SpaceKind) -> [Trip] {
        trips.filter { $0.space == space }.sorted { $0.date > $1.date }
    }

    func suggestions(in space: SpaceKind) -> [Suggestion] { suggestionsBySpace[space] ?? [] }

    // MARK: Mutations (small; the feature phases add the rest)

    /// Checks or unchecks a grocery item. Returns the previous value for Undo.
    @discardableResult
    func setGrocery(_ id: GroceryItem.ID, done: Bool) -> GroceryItem? {
        guard let i = groceryItems.firstIndex(where: { $0.id == id }) else { return nil }
        let previous = groceryItems[i]
        groceryItems[i].done = done
        groceryItems[i].boughtBy = done ? me : nil
        groceryItems[i].boughtAt = done ? now : nil
        groceryItems[i].viaReceipt = false
        return previous
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

    /// Puts back a value returned by a mutation (Undo).
    func restore(_ item: GroceryItem) {
        guard let i = groceryItems.firstIndex(where: { $0.id == item.id }) else { return }
        groceryItems[i] = item
    }

    func restore(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i] = task
    }

    private func defaultListID(for space: SpaceKind) -> GroceryList.ID? {
        lists.first { $0.space == space && $0.isDefault }?.id
    }
}
