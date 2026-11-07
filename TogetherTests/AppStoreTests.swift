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

@MainActor
struct ToastCenterTests {
    @Test func newToastReplacesCurrent() {
        let toasts = ToastCenter()
        toasts.show("First")
        toasts.show("Second")
        #expect(toasts.current?.message == "Second")
    }

    @Test func actionRunsAndHides() {
        let toasts = ToastCenter()
        var undone = false
        toasts.showUndo("Task done") { undone = true }
        #expect(toasts.current?.action == "Undo")
        toasts.performAction()
        #expect(undone)
        #expect(toasts.current == nil)
    }

    @Test func autoHides() async throws {
        let toasts = ToastCenter(duration: .milliseconds(50))
        toasts.show("Saved")
        try await Task.sleep(for: .milliseconds(300))
        #expect(toasts.current == nil)
    }

    @Test func staleTimerDoesNotHideNewerToast() async throws {
        let toasts = ToastCenter(duration: .milliseconds(150))
        toasts.show("First")
        try await Task.sleep(for: .milliseconds(100))
        toasts.show("Second")
        try await Task.sleep(for: .milliseconds(80))
        #expect(toasts.current?.message == "Second")
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
