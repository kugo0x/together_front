import Foundation
import Testing
@testable import Together

/// `AppStore.home(in:)` — the in-memory `GET /v1/spaces/{id}/home`.
@MainActor
struct HomeSummaryTests {
    /// Monday 9 Nov 2026, 15:37 in Warsaw.
    static let now = instant(2026, 11, 9, 15, 37)

    func makeStore() -> AppStore {
        let now = Self.now
        return AppStore(data: .make(now: now, calendar: warsaw), clock: { now }, calendar: warsaw)
    }

    func draft(_ title: String, due: CalendarDay?, assignee: Person? = nil) -> AppStore.TaskDraft {
        .init(title: title, dueDay: due, assignee: assignee)
    }

    // MARK: Tasks

    @Test func todayShowsTasksDueTodayOnly() {
        let home = makeStore().home(in: .shared)
        #expect(home.tasks.total == 5)
        #expect(home.tasks.items.map(\.title) == ["Pay the internet bill"])
        #expect(home.tasks.items.map(\.status) == [.today])
        #expect(home.tasks.items.first?.assignedToMe == true)
        #expect(home.tasks.items.first?.reminderAt != nil)
    }

    @Test func overdueComesFirstAndLaterOrUndatedStayOff() throws {
        let store = makeStore()
        let today = store.today
        _ = try #require(store.createTask(draft("Mine later", due: today.adding(days: 5), assignee: .alex), in: .shared))
        _ = try #require(store.createTask(draft("Overdue", due: today.adding(days: -2)), in: .shared))
        _ = try #require(store.createTask(draft("Someday", due: nil), in: .shared))
        _ = try #require(store.createTask(draft("Also today", due: today), in: .shared))
        let home = store.home(in: .shared)
        #expect(home.tasks.items.map(\.title) == ["Overdue", "Pay the internet bill", "Also today"]
            || home.tasks.items.map(\.title) == ["Overdue", "Also today", "Pay the internet bill"])
        #expect(home.tasks.items.map(\.status) == [.overdue, .today, .today])
    }

    @Test func nothingForTodayIsEmpty() {
        let store = makeStore()
        for task in store.activeTasks(in: .shared) where task.dueDay == store.today { store.deleteTask(task.id, in: .shared) }
        #expect(store.home(in: .shared).tasks.items.isEmpty)
    }

    @Test func personalTasksAreAllMine() {
        let home = makeStore().home(in: .personal)
        #expect(home.tasks.items.allSatisfy { $0.assignedToMe && [.overdue, .today].contains($0.status) })
    }

    // MARK: Groceries and suggestions

    @Test func groceriesShowOpenCountNewestThreeAndSuggestions() throws {
        let store = makeStore()
        _ = try #require(store.addItem(text: "2 limes", in: .shared))
        let home = store.home(in: .shared)
        #expect(home.groceries.openCount == 8)
        #expect(home.groceries.items.map(\.name) == ["Limes", "Oat milk", "Tomatoes"])
        #expect(home.groceries.items.first?.qty == "2")
        #expect(home.groceries.listID == store.defaultList(for: .shared).id)
        #expect(home.groceries.suggestions == ["Eggs", "Bananas", "Coffee beans"])
        #expect(home.suggestionTeaser == "3 things you usually buy — review")
    }

    @Test func suggestionsOffHidesTheTeaser() {
        let store = makeStore()
        store.suggestionsEnabled = false
        let home = store.home(in: .shared)
        #expect(home.groceries.suggestions.isEmpty)
        #expect(home.suggestionTeaser == nil)
    }

    @Test func teaserCountsOne() {
        let store = makeStore()
        store.dismissSuggestion(named: "Eggs", in: .shared)
        store.dismissSuggestion(named: "Bananas", in: .shared)
        #expect(store.home(in: .shared).suggestionTeaser == "1 thing you usually buy — review")
    }

    // MARK: Invite banner

    @Test func inviteShowsOnlyInSharedWhenAlone() {
        let store = makeStore()
        #expect(store.home(in: .shared).showInvite == false)
        #expect(store.home(in: .shared).space.memberCount == 2)
        store.partner = nil
        #expect(store.home(in: .shared).showInvite)
        #expect(store.home(in: .shared).space.memberCount == 1)
        #expect(store.home(in: .personal).showInvite == false)
    }

    // MARK: Isolation

    @Test func sharedHomeNeverContainsAnythingPersonal() throws {
        let store = makeStore()
        // Make the Personal space as tempting as possible: newest, overdue, mine.
        _ = try #require(store.createTask(draft("Secret overdue", due: store.today.adding(days: -1)), in: .personal))
        _ = try #require(store.addItem(text: "Surprise gift", in: .personal))

        let home = store.home(in: .shared)
        let personalTasks = Set(store.tasks(in: .personal).map(\.id))
        let personalItems = Set(store.groceries(in: .personal).map(\.id))
        #expect(home.space.kind == .shared)
        #expect(home.tasks.items.allSatisfy { !personalTasks.contains($0.id) })
        #expect(home.groceries.items.allSatisfy { !personalItems.contains($0.id) })
        #expect(home.tasks.total == store.activeTasks(in: .shared).count)
        #expect(home.groceries.openCount == store.toBuy(in: .shared).count)

        // And the other way round.
        let personal = store.home(in: .personal)
        #expect(personal.tasks.items.first?.title == "Secret overdue")
        #expect(personal.groceries.items.first?.name == "Surprise gift")
        #expect(personal.groceries.suggestions.isEmpty)
    }
}
