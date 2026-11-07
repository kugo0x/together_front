import Foundation
import SwiftUI
import Testing
@testable import Together

@MainActor
struct AppStoreTests {
    /// Saturday, 7 November 2026, 15:00 — the prototype's "today".
    static let now: Date = {
        var c = DateComponents(year: 2026, month: 11, day: 7, hour: 15)
        c.timeZone = .current
        return Calendar.current.date(from: c)!
    }()

    func makeStore() -> AppStore {
        let now = Self.now
        return AppStore(data: .make(now: now), clock: { now })
    }

    // MARK: Space filtering — nothing private in Shared

    @Test func sharedViewsContainNoPersonalItems() {
        let store = makeStore()
        let personalGroceryIDs = Set(store.groceries(in: .personal).map(\.id))
        let personalTaskIDs = Set(store.tasks(in: .personal).map(\.id))
        let personalNoteIDs = Set(store.notes(in: .personal).map(\.id))

        #expect(!personalGroceryIDs.isEmpty && !personalTaskIDs.isEmpty && !personalNoteIDs.isEmpty)

        #expect(store.groceries(in: .shared).allSatisfy { store.space(of: $0) == .shared })
        #expect(store.toBuy(in: .shared).allSatisfy { !personalGroceryIDs.contains($0.id) })
        #expect(store.bought(in: .shared).allSatisfy { !personalGroceryIDs.contains($0.id) })
        #expect(store.tasks(in: .shared).allSatisfy { $0.space == .shared })
        #expect(store.pendingTasks(in: .shared).allSatisfy { !personalTaskIDs.contains($0.id) })
        #expect(store.doneTasks(in: .shared).allSatisfy { !personalTaskIDs.contains($0.id) })
        #expect(store.notes(in: .shared).allSatisfy { $0.space == .shared })
        #expect(store.trips(in: .shared).allSatisfy { $0.space == .shared })
    }

    @Test func personalViewsContainOnlyPersonalItems() {
        let store = makeStore()
        #expect(store.groceries(in: .personal).map(\.name) == ["Protein bars", "Razor blades", "Birthday card for Sam"])
        #expect(store.tasks(in: .personal).map(\.title) == ["Book a dentist appointment", "Renew gym membership", "Call Mum"])
        #expect(store.notes(in: .personal).allSatisfy { $0.space == .personal })
        #expect(store.trips(in: .personal).count == 1)
    }

    @Test func spacesPartitionAllData() {
        let store = makeStore()
        let groceries = SpaceKind.allCases.flatMap { store.groceries(in: $0) }
        #expect(groceries.count == store.groceryItems.count)
        #expect(Set(groceries.map(\.id)).count == groceries.count)
        #expect(SpaceKind.allCases.map { store.tasks(in: $0).count }.reduce(0, +) == store.tasks.count)
        #expect(SpaceKind.allCases.map { store.notes(in: $0).count }.reduce(0, +) == store.notes.count)
        #expect(SpaceKind.allCases.map { store.trips(in: $0).count }.reduce(0, +) == store.trips.count)
    }

    @Test func mockCountsMatchPrototype() {
        let store = makeStore()
        #expect(store.toBuy(in: .shared).count == 7)
        #expect(store.bought(in: .shared).count == 2)
        #expect(store.pendingTasks(in: .shared).count == 5)
        #expect(store.notes(in: .shared).count == 3)
        #expect(store.suggestions(in: .shared).count == 3)
        #expect(store.suggestions(in: .personal).isEmpty)
    }

    // MARK: Grocery lists

    @Test func everySpaceHasOneDefaultList() {
        let store = AppStore(data: .empty)
        for space in SpaceKind.allCases {
            let defaults = store.lists(in: space).filter(\.isDefault)
            #expect(defaults.count == 1)
            #expect(store.defaultList(for: space).id == defaults.first?.id)
        }
        #expect(store.lists.count == 2)
    }

    // MARK: Mutations + Undo

    @Test func checkingAGroceryRecordsWhoAndUndoRestores() throws {
        let store = makeStore()
        let item = try #require(store.toBuy(in: .shared).first)
        let previous = try #require(store.setGrocery(item.id, done: true))

        let bought = try #require(store.bought(in: .shared).first { $0.id == item.id })
        #expect(bought.boughtBy == .alex)
        #expect(bought.boughtAt == Self.now)

        store.restore(previous)
        #expect(store.toBuy(in: .shared).contains { $0.id == item.id })
    }

    @Test func completingATaskAndUndo() throws {
        let store = makeStore()
        let task = try #require(store.pendingTasks(in: .shared).first)
        let previous = try #require(store.setTask(task.id, done: true))
        #expect(store.doneTasks(in: .shared).first { $0.id == task.id }?.doneBy == .alex)
        store.restore(previous)
        #expect(store.pendingTasks(in: .shared).contains { $0.id == task.id })
    }

    // MARK: Space persistence

    @Test func spaceDefaultsToShared() {
        let defaults = Self.freshDefaults()
        let space = AppStorage(wrappedValue: SpaceSetting.defaultValue, SpaceSetting.key, store: defaults)
        #expect(space.wrappedValue == .shared)
    }

    @Test func spacePersistsAcrossLaunches() {
        let defaults = Self.freshDefaults()
        let first = AppStorage(wrappedValue: SpaceSetting.defaultValue, SpaceSetting.key, store: defaults)
        first.wrappedValue = .personal
        #expect(defaults.string(forKey: SpaceSetting.key) == "personal")

        // A new AppStorage over the same defaults = the next launch.
        let relaunched = AppStorage(wrappedValue: SpaceSetting.defaultValue, SpaceSetting.key, store: defaults)
        #expect(relaunched.wrappedValue == .personal)
    }

    @Test func unknownStoredSpaceFallsBackToShared() {
        let defaults = Self.freshDefaults()
        defaults.set("family", forKey: SpaceSetting.key)
        let space = AppStorage(wrappedValue: SpaceSetting.defaultValue, SpaceSetting.key, store: defaults)
        #expect(space.wrappedValue == .shared)
    }

    private static func freshDefaults() -> UserDefaults {
        let name = "AppStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

/// Hands time to the test: every `sleep` waits until `advance()`.
@MainActor
final class ManualClock {
    private(set) var requested: [Duration] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    nonisolated var sleep: ToastCenter.Sleep { { [self] duration in await self.wait(duration) } }

    private func wait(_ duration: Duration) async {
        requested.append(duration)
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Lets every pending sleep finish.
    func advance() {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }

    /// Yields until `condition` holds (the toast's hide task runs on the main actor too).
    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { await Task.yield() }
    }
}

@MainActor
struct ToastCenterTests {
    @Test func showUndoRestoresThenAutoHidesAfterDuration() async throws {
        let clock = ManualClock()
        let toasts = ToastCenter(sleep: clock.sleep)
        let now = AppStoreTests.now
        let store = AppStore(data: .make(now: now), clock: { now })
        let item = try #require(store.toBuy(in: .shared).first)

        // Check the item: toast with Undo is shown and waits 3.8 s.
        let previous = try #require(store.setGrocery(item.id, done: true))
        toasts.showUndo("\(item.name) bought") { store.restore(previous) }
        #expect(toasts.current?.message == "\(item.name) bought")
        #expect(toasts.current?.action == "Undo")
        await clock.settle { !clock.requested.isEmpty }
        #expect(clock.requested == [.milliseconds(3800)])
        #expect(toasts.current != nil, "still visible before time passes")

        // Undo restores the item and hides the toast.
        toasts.performAction()
        #expect(store.toBuy(in: .shared).contains { $0.id == item.id })
        #expect(toasts.current == nil)

        // A second toast hides by itself once 3.8 s have passed.
        toasts.show("Task done")
        await clock.settle { clock.requested.count == 2 }
        #expect(toasts.current?.message == "Task done")
        clock.advance()
        await clock.settle { toasts.current == nil }
        #expect(toasts.current == nil)
    }

    @Test func newToastReplacesCurrentAndOldTimerCantHideIt() async {
        let clock = ManualClock()
        let toasts = ToastCenter(sleep: clock.sleep)
        toasts.show("First")
        await clock.settle { clock.requested.count == 1 }
        toasts.show("Second")
        await clock.settle { clock.requested.count == 2 }
        #expect(toasts.current?.message == "Second")

        // Both timers fire: the cancelled first one must not hide "Second" early… but the second one does.
        clock.advance()
        await clock.settle { toasts.current == nil }
        #expect(toasts.current == nil)
    }

    @Test func staleTimerIgnoresNewerToast() async {
        let clock = ManualClock()
        let toasts = ToastCenter(sleep: clock.sleep)
        toasts.show("First")
        await clock.settle { clock.requested.count == 1 }
        // Fire only the first timer, then show a new toast before it runs.
        clock.advance()
        toasts.show("Second")
        for _ in 0..<20 { await Task.yield() }
        #expect(toasts.current?.message == "Second")
    }

    @Test func actionlessToastHasNoUndo() {
        let toasts = ToastCenter(sleep: { _ in })
        toasts.show("Sam bought Tomatoes", person: .sam)
        #expect(toasts.current?.action == nil)
        #expect(toasts.current?.person == .sam)
    }
}

@MainActor
struct RelativeDateTests {
    let dates = RelativeDate(now: AppStoreTests.now)
    func day(_ offset: Int, _ hour: Int = 12) -> Date {
        let cal = Calendar.current
        let d = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: AppStoreTests.now))!
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d)!
    }

    @Test func dueWords() {
        #expect(dates.due(day(0)) == "Today")
        #expect(dates.due(day(1)) == "Tomorrow")
        #expect(dates.due(day(2)) == "Mon")
        #expect(dates.due(day(8)) == "15 Nov")
        #expect(dates.isUrgent(day(0)) && !dates.isUrgent(day(1)))
    }

    @Test func reminderAndPast() {
        #expect(dates.reminder(day(0, 19)) == "Today 19:00")
        #expect(dates.reminder(day(2, 9)) == "Mon 9:00")
        #expect(dates.past(day(-1)) == "Yesterday")
        #expect(dates.past(day(-1), midSentence: true) == "yesterday")
        #expect(dates.past(day(-10)) == "28 Oct")
        #expect(dates.longDay(AppStoreTests.now) == "Saturday, 7 November")
    }
}
