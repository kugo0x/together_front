import Foundation
import Testing
@testable import Together

/// Europe/Warsaw, like the backend tests.
let warsaw: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
    return c
}()

func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d) }

func instant(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    day(y, m, d).at(hour: h, minute: min, calendar: warsaw)
}

// MARK: - Recurrence (mirrors back/internal/task/domain/repeat.go)

struct RecurrenceTests {
    @Test func monthlyKeepsAnchorDayClampedToMonthLength() {
        var d = day(2026, 1, 31)
        var seen: [CalendarDay] = []
        for _ in 0..<4 {
            d = RepeatRule.monthly.step(d, anchorDay: 31)
            seen.append(d)
        }
        #expect(seen == [day(2026, 2, 28), day(2026, 3, 31), day(2026, 4, 30), day(2026, 5, 31)])
    }

    @Test func leapYearFebruary() {
        #expect(RepeatRule.monthly.step(day(2028, 1, 30), anchorDay: 30) == day(2028, 2, 29))
    }

    @Test func everyTwoMonthsCrossesTheYear() {
        #expect(RepeatRule.everyTwoMonths.step(day(2026, 12, 31), anchorDay: 31) == day(2027, 2, 28))
        #expect(RepeatRule.everyTwoMonths.step(day(2026, 11, 9), anchorDay: 9) == day(2027, 1, 9))
    }

    @Test func weeklyIsSevenCalendarDaysAcrossDST() {
        // Clocks go back on 25 Oct 2026 in Warsaw; a week is still seven calendar days.
        #expect(RepeatRule.weekly.step(day(2026, 10, 22), anchorDay: 0) == day(2026, 10, 29))
        #expect(RepeatRule.weekly.step(day(2027, 3, 25), anchorDay: 0) == day(2027, 4, 1))
    }

    @Test func doneEarlyStepsOnce() {
        let next = RepeatRule.weekly.nextOccurrence(after: day(2026, 11, 12), anchorDay: 0, today: day(2026, 11, 9))
        #expect(next == day(2026, 11, 19))
    }

    @Test func overdueRollsToTheFirstDateAfterToday() {
        // Weekly, due 3 weeks ago (Tue 20 Oct), done Mon 9 Nov → Tue 10 Nov.
        let next = RepeatRule.weekly.nextOccurrence(after: day(2026, 10, 20), anchorDay: 0, today: day(2026, 11, 9))
        #expect(next == day(2026, 11, 10))
        // Due today → strictly after today.
        #expect(RepeatRule.weekly.nextOccurrence(after: day(2026, 11, 9), anchorDay: 0, today: day(2026, 11, 9)) == day(2026, 11, 16))
    }

    @Test func dayArithmeticAcrossDST() {
        #expect(day(2026, 10, 24).days(until: day(2026, 10, 26)) == 2)
        #expect(day(2027, 3, 27).adding(days: 2) == day(2027, 3, 29))
        // 2:30 on 28 Mar 2027 doesn't exist in Warsaw; it moves forward, not back.
        let gap = day(2027, 3, 28).at(hour: 2, minute: 30, calendar: warsaw)
        #expect(warsaw.component(.hour, from: gap) == 3)
    }
}

// MARK: - Quiet hours and reminder chips (quiet.go, reminder.go, prototype remindOptions)

struct ReminderRuleTests {
    @Test func quietHoursShiftEveningToNextMorning() {
        let (at, shifted) = QuietHours.default.apply(instant(2026, 11, 9, 23), calendar: warsaw)
        #expect(shifted)
        #expect(at == instant(2026, 11, 10, 8))
    }

    @Test func quietHoursShiftEarlyMorningToSameDay() {
        let (at, shifted) = QuietHours.default.apply(instant(2026, 11, 9, 3), calendar: warsaw)
        #expect(shifted && at == instant(2026, 11, 9, 8))
    }

    @Test func outsideQuietHoursIsUnchanged() {
        for hour in [8, 12, 21] {
            let t = instant(2026, 11, 9, hour)
            #expect(QuietHours.default.apply(t, calendar: warsaw) == (t, false))
        }
        #expect(QuietHours.default.contains(instant(2026, 11, 9, 21, 59), calendar: warsaw) == false)
        #expect(QuietHours.default.contains(instant(2026, 11, 9, 22), calendar: warsaw))
    }

    @Test func plannedReminderRemembersWhatWasAsked() {
        let r = TaskReminder.plan(at: instant(2026, 11, 9, 23), for: .sam, quiet: .default, calendar: warsaw)
        #expect(r.remindAt == instant(2026, 11, 10, 8))
        #expect(r.shiftedFrom == instant(2026, 11, 9, 23))
        // Moving it a week keeps the requested 23:00 and re-applies quiet hours.
        let moved = r.moved(byDays: 7, quiet: .default, calendar: warsaw)
        #expect(moved.requested == instant(2026, 11, 16, 23))
        #expect(moved.remindAt == instant(2026, 11, 17, 8))
    }

    @Test func reminderKeepsWallClockAcrossDST() {
        let r = TaskReminder.plan(at: instant(2026, 10, 22, 9), for: .alex, quiet: .default, calendar: warsaw)
        let moved = r.moved(byDays: 7, quiet: .default, calendar: warsaw)
        #expect(moved.remindAt == instant(2026, 10, 29, 9))
    }

    @Test("Chips depend on the due date", arguments: [
        (nil, ["Tomorrow · 9:00", "This evening · 19:00"]),
        (0, ["This evening · 19:00", "In 1 hour · 16:40"]),
        (1, ["Morning of · 9:00", "Tonight · 19:00"]),
        (5, ["Morning of · 9:00", "Day before · 19:00"]),
    ] as [(Int?, [String])])
    func reminderChips(dueOffset: Int?, labels: [String]) {
        let now = instant(2026, 11, 9, 15, 37) // Monday 15:37
        let due = dueOffset.map { day(2026, 11, 9).adding(days: $0) }
        let options = ReminderPlanner.options(due: due, now: now, calendar: warsaw)
        #expect(options.map(\.label) == labels)
    }

    @Test func chipTimes() {
        let now = instant(2026, 11, 9, 15, 37)
        let sat = ReminderPlanner.options(due: day(2026, 11, 14), now: now, calendar: warsaw)
        #expect(sat.map(\.at) == [instant(2026, 11, 14, 9), instant(2026, 11, 13, 19)])
    }

    @Test func pastTimesAreNotOffered() {
        let late = instant(2026, 11, 9, 20, 30)
        #expect(ReminderPlanner.options(due: day(2026, 11, 9), now: late, calendar: warsaw).map(\.label) == ["In 1 hour · 21:30"])
        #expect(ReminderPlanner.options(due: day(2026, 11, 10), now: late, calendar: warsaw).map(\.label) == ["Morning of · 9:00"])
    }

    @Test func pickTimeUsesTheDueDayOrTomorrow() {
        let now = instant(2026, 11, 9, 15)
        #expect(ReminderPlanner.custom(TimeOfDay(23), due: day(2026, 11, 12), now: now, calendar: warsaw) == instant(2026, 11, 12, 23))
        #expect(ReminderPlanner.custom(TimeOfDay(7, 30), due: nil, now: now, calendar: warsaw) == instant(2026, 11, 10, 7, 30))
    }

    @Test func notificationCopy() {
        let today = day(2026, 11, 9)
        #expect(ReminderText.dueLabel(today, today: today) == "today")
        #expect(ReminderText.dueLabel(day(2026, 11, 10), today: today) == "tomorrow")
        #expect(ReminderText.dueLabel(day(2026, 11, 14), today: today) == "Saturday")
        #expect(ReminderText.dueLabel(day(2026, 11, 20), today: today) == "20 Nov")
        #expect(ReminderText.title(setBy: .sam, recipient: .alex) == "Sam asked you to")
        #expect(ReminderText.title(setBy: .alex, recipient: .alex) == "Reminder")
    }
}

// MARK: - Store

/// Records what the store asks the notification centre to do.
@MainActor
final class FakeNotifications: ReminderNotifying {
    private(set) var pending: [String: LocalReminder] = [:]
    private(set) var scheduleCalls = 0

    func schedule(_ reminder: LocalReminder) {
        scheduleCalls += 1
        pending[reminder.id] = reminder
    }

    func cancel(id: String) { pending[id] = nil }
}

@MainActor
struct TaskStoreTests {
    /// Monday 9 Nov 2026, 15:37 in Warsaw.
    static let now = instant(2026, 11, 9, 15, 37)

    let notifications = FakeNotifications()

    func makeStore() -> AppStore {
        let now = Self.now
        return AppStore(data: .make(now: now, calendar: warsaw), clock: { now }, calendar: warsaw, notifier: notifications)
    }

    func draft(
        _ title: String, due: CalendarDay? = nil, repeat rule: RepeatRule? = nil,
        assignee: Person? = nil, reminderAt: Date? = nil, notes: String? = nil
    ) -> AppStore.TaskDraft {
        .init(title: title, notes: notes, dueDay: due, repeatRule: rule, assignee: assignee, reminderAt: reminderAt)
    }

    // MARK: Create / validation

    @Test func onlyTheTitleIsRequired() throws {
        let store = makeStore()
        #expect(store.createTask(draft("   "), in: .shared) == nil)
        let task = try #require(store.createTask(draft("  Water the plants ", notes: "  "), in: .shared))
        #expect(task.title == "Water the plants")
        #expect(task.notes == nil)
        #expect(task.assignee == nil, "Anyone")
        #expect(task.createdBy == .alex)
        #expect(store.activeTasks(in: .shared).contains { $0.id == task.id })
    }

    @Test func descriptionIsKept() throws {
        let store = makeStore()
        let task = try #require(store.createTask(draft("Fix the tap", notes: "Washer size 1/2\""), in: .shared))
        #expect(task.notes == "Washer size 1/2\"")
    }

    @Test func repeatNeedsADate() throws {
        let store = makeStore()
        let task = try #require(store.createTask(draft("Plants", repeat: .weekly), in: .shared))
        #expect(task.repeatRule == nil)
    }

    @Test func personalTasksAreMineAndCanHaveReminders() throws {
        let store = makeStore()
        let task = try #require(store.createTask(
            draft("Dentist", due: day(2026, 11, 12), assignee: .sam, reminderAt: instant(2026, 11, 12, 9)),
            in: .personal
        ))
        #expect(task.assignee == .alex)
        #expect(task.reminder?.recipient == .alex)
    }

    @Test func anyoneGetsNoReminder() throws {
        let store = makeStore()
        let task = try #require(store.createTask(draft("Bins", due: day(2026, 11, 10), reminderAt: instant(2026, 11, 10, 9)), in: .shared))
        #expect(task.reminder == nil)
        #expect(notifications.pending.isEmpty)
    }

    @Test func quietHoursSaveEightOClock() throws {
        let store = makeStore()
        let task = try #require(store.createTask(
            draft("Return the parcel", due: day(2026, 11, 9), assignee: .sam, reminderAt: instant(2026, 11, 9, 23)),
            in: .shared
        ))
        #expect(task.reminder?.remindAt == instant(2026, 11, 10, 8))
        #expect(task.reminder?.shiftedFrom == instant(2026, 11, 9, 23))
    }

    @Test func activeAreSortedByDueUndatedLast() {
        let store = makeStore()
        let dues = store.activeTasks(in: .shared).map(\.dueDay)
        let dated = dues.compactMap { $0 }
        #expect(dated == dated.sorted())
        #expect(dues.last == .some(nil))
    }

    // MARK: Complete / reopen

    @Test func oneOffCompletesAndUndoReopens() throws {
        let store = makeStore()
        let task = try #require(store.createTask(draft("Defrost"), in: .shared))
        let result = try #require(store.completeTask(task.id, in: .shared))
        #expect(!result.rolled)
        #expect(store.doneTasks(in: .shared).first?.id == task.id)
        #expect(store.doneTasks(in: .shared).first?.doneBy == .alex)
        #expect(store.completeTask(task.id, in: .shared) == nil, "idempotent")

        try #require(store.reopenTask(task.id, in: .shared) != nil)
        #expect(store.activeTasks(in: .shared).contains { $0.id == task.id })
    }

    @Test func repeatingTaskRollsForwardWithItsReminderAndUndoRollsBack() throws {
        let store = makeStore()
        let task = try #require(store.createTask(
            draft("Bills", due: day(2026, 10, 31), repeat: .monthly, assignee: .alex, reminderAt: instant(2026, 10, 31, 9)),
            in: .shared
        ))
        let result = try #require(store.completeTask(task.id, in: .shared))
        #expect(result.rolled)
        #expect(result.task.dueDay == day(2026, 11, 30), "overdue: first date after today, anchor 31 clamped")
        #expect(!result.task.done)
        #expect(result.task.lastDoneBy == .alex)
        #expect(result.task.reminder?.remindAt == instant(2026, 11, 30, 9))
        #expect(notifications.pending[task.id.uuidString]?.fireAt == instant(2026, 11, 30, 9))

        let reopened = try #require(store.reopenTask(task.id, in: .shared))
        #expect(reopened.dueDay == day(2026, 10, 31))
        #expect(reopened.reminder?.remindAt == instant(2026, 10, 31, 9))
        // The restored reminder is in the past, so nothing is pending for it.
        #expect(notifications.pending[task.id.uuidString] == nil)
    }

    @Test func anchorSurvivesShortMonths() throws {
        let store = makeStore()
        let task = try #require(store.createTask(draft("Rent", due: day(2026, 11, 30), repeat: .monthly), in: .shared))
        _ = store.completeTask(task.id, in: .shared)
        _ = store.completeTask(task.id, in: .shared)
        _ = store.completeTask(task.id, in: .shared)
        #expect(store.task(task.id, in: .shared)?.dueDay == day(2027, 2, 28))
        _ = store.completeTask(task.id, in: .shared)
        #expect(store.task(task.id, in: .shared)?.dueDay == day(2027, 3, 30))
    }

    // MARK: Notifications — mine only, never duplicated

    @Test func myReminderIsScheduledOnceAndFollowsEdits() throws {
        let store = makeStore()
        let task = try #require(store.createTask(
            draft("Return the parcel", due: day(2026, 11, 11), assignee: .alex, reminderAt: instant(2026, 11, 11, 9)),
            in: .shared
        ))
        let id = task.id.uuidString
        #expect(notifications.pending.count == 1)
        #expect(notifications.pending[id]?.title == "Reminder")
        #expect(notifications.pending[id]?.body == "Return the parcel · Wednesday")

        // Edit: new time replaces the old one (same id), still one.
        store.updateTask(task.id, in: .shared, with: draft("Return the parcel", due: day(2026, 11, 11), assignee: .alex, reminderAt: instant(2026, 11, 10, 19)))
        #expect(notifications.pending.count == 1)
        #expect(notifications.pending[id]?.fireAt == instant(2026, 11, 10, 19))

        // Reassigned to Sam: not mine any more → cancelled here.
        store.updateTask(task.id, in: .shared, with: draft("Return the parcel", due: day(2026, 11, 11), assignee: .sam, reminderAt: instant(2026, 11, 10, 19)))
        #expect(notifications.pending.isEmpty)
        #expect(store.task(task.id, in: .shared)?.reminder?.recipient == .sam)
    }

    @Test func completingCancelsAndUndoRestores() throws {
        let store = makeStore()
        let task = try #require(store.createTask(
            draft("Call the plumber", due: day(2026, 11, 10), assignee: .alex, reminderAt: instant(2026, 11, 10, 9)),
            in: .shared
        ))
        _ = store.completeTask(task.id, in: .shared)
        #expect(notifications.pending.isEmpty)
        _ = store.reopenTask(task.id, in: .shared)
        #expect(notifications.pending.count == 1)
    }

    @Test func deletingCancelsAndUndoRestoresOnce() throws {
        let store = makeStore()
        let task = try #require(store.createTask(
            draft("Book flights", due: day(2026, 11, 12), assignee: .alex, reminderAt: instant(2026, 11, 12, 9)),
            in: .shared
        ))
        let removed = try #require(store.deleteTask(task.id, in: .shared))
        #expect(notifications.pending.isEmpty)
        store.undoDeleteTask(removed)
        store.undoDeleteTask(removed)
        #expect(notifications.pending.count == 1)
        #expect(store.tasks(in: .shared).filter { $0.id == task.id }.count == 1)
    }

    @Test func turningTheReminderOffCancels() throws {
        let store = makeStore()
        let task = try #require(store.createTask(
            draft("Pick up keys", due: day(2026, 11, 12), assignee: .alex, reminderAt: instant(2026, 11, 12, 9)),
            in: .shared
        ))
        store.updateTask(task.id, in: .shared, with: draft("Pick up keys", due: day(2026, 11, 12), assignee: .alex))
        #expect(notifications.pending.isEmpty)
        #expect(store.task(task.id, in: .shared)?.reminder == nil)
    }

    // MARK: Space isolation

    @Test func personalTasksNeverReachShared() throws {
        let store = makeStore()
        let secret = try #require(store.createTask(draft("Surprise for Sam"), in: .personal))
        #expect(!store.activeTasks(in: .shared).contains { $0.id == secret.id })
        #expect(store.activeTasks(in: .shared).allSatisfy { $0.space == .shared })
        #expect(store.doneTasks(in: .shared).allSatisfy { $0.space == .shared })
        // Like the API's 404: a Personal task can't be touched through Shared.
        #expect(store.completeTask(secret.id, in: .shared) == nil)
        #expect(store.updateTask(secret.id, in: .shared, with: draft("x")) == nil)
        #expect(store.deleteTask(secret.id, in: .shared) == nil)
        #expect(store.task(secret.id, in: .personal)?.title == "Surprise for Sam")
    }
}
