import Foundation

// Task scheduling rules — a Swift mirror of back/internal/task/domain (calendar.go, repeat.go, quiet.go,
// reminder.go) so the app shows exactly what the server will do. Keep the two in step.

/// A calendar day without a time zone ("2026-11-09"), like the backend's `Date`.
struct CalendarDay: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s time zone.
    init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// The instant of this day at hh:mm in `calendar`'s zone. A time inside a DST spring-forward gap is moved
    /// forward (as Go does).
    func at(hour: Int = 0, minute: Int = 0, calendar: Calendar) -> Date {
        var c = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        c.timeZone = calendar.timeZone
        return calendar.date(from: c)
            ?? calendar.nextDate(after: at(hour: 0, minute: 0, calendar: calendar),
                                 matching: DateComponents(hour: hour, minute: minute),
                                 matchingPolicy: .nextTime)!
    }

    /// Moves by `n` calendar days.
    func adding(days n: Int) -> CalendarDay {
        let utc = Self.utc
        return CalendarDay(utc.date(byAdding: .day, value: n, to: at(hour: 12, calendar: utc))!, calendar: utc)
    }

    /// Calendar days from `self` to `other` (negative if `other` is earlier).
    func days(until other: CalendarDay) -> Int {
        let utc = Self.utc
        return utc.dateComponents([.day], from: at(calendar: utc), to: other.at(calendar: utc)).day!
    }

    /// 1 = Sunday … 7 = Saturday.
    var weekday: Int { Self.utc.component(.weekday, from: at(hour: 12, calendar: Self.utc)) }

    static func < (a: CalendarDay, b: CalendarDay) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    static func daysIn(year: Int, month: Int) -> Int {
        let utc = Self.utc
        let first = CalendarDay(year: year, month: month, day: 1).at(hour: 12, calendar: utc)
        return utc.range(of: .day, in: .month, for: first)!.count
    }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}

/// A wall-clock time ("18:00").
struct TimeOfDay: Hashable, Codable, Sendable {
    var hour: Int
    var minute: Int

    init(_ hour: Int, _ minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        self.init(c.hour!, c.minute!)
    }

    /// "9:00", "19:00".
    var text: String { String(format: "%d:%02d", hour, minute) }
}

// MARK: - Recurrence (repeat.go)

extension RepeatRule {
    /// One step forward. Monthly rules keep the anchor day (the day of month the repeat started on), clamped
    /// to the month's length: 31 Jan → 28 Feb → 31 Mar → 30 Apr.
    func step(_ day: CalendarDay, anchorDay: Int) -> CalendarDay {
        switch self {
        case .weekly: day.adding(days: 7)
        case .monthly: Self.addMonths(day, 1, anchor: anchorDay)
        case .everyTwoMonths: Self.addMonths(day, 2, anchor: anchorDay)
        }
    }

    /// The next due date after completing: step forward from the current due date until it is after today.
    /// Done early → one step; done three weeks late on a weekly task → the first future occurrence.
    func nextOccurrence(after due: CalendarDay, anchorDay: Int, today: CalendarDay) -> CalendarDay {
        var next = step(due, anchorDay: anchorDay)
        while next <= today { next = step(next, anchorDay: anchorDay) }
        return next
    }

    static func addMonths(_ d: CalendarDay, _ n: Int, anchor: Int) -> CalendarDay {
        let anchor = (1...31).contains(anchor) ? anchor : d.day
        var year = d.year, month = d.month + n
        while month > 12 { year += 1; month -= 12 }
        return CalendarDay(year: year, month: month, day: min(anchor, CalendarDay.daysIn(year: year, month: month)))
    }
}

// MARK: - Quiet hours (quiet.go)

/// The receiver's do-not-disturb window in minutes after local midnight (default 22:00–8:00). It may wrap
/// midnight; start == end means off.
struct QuietHours: Hashable, Codable, Sendable {
    var start: Int
    var end: Int

    static let `default` = QuietHours(start: 22 * 60, end: 8 * 60)

    /// "22:00–8:00".
    var text: String { TimeOfDay(start / 60, start % 60).text + "–" + TimeOfDay(end / 60, end % 60).text }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard start != end else { return false }
        let t = TimeOfDay(date, calendar: calendar)
        let m = t.hour * 60 + t.minute
        return start < end ? (m >= start && m < end) : (m >= start || m < end)
    }

    /// Moves `date` out of the window to its end — on the next day when it is in the evening part of a window
    /// that wraps midnight. 23:00 → 8:00 next day; 3:00 → 8:00 same day.
    func apply(_ date: Date, calendar: Calendar) -> (date: Date, shifted: Bool) {
        guard contains(date, calendar: calendar) else { return (date, false) }
        var day = CalendarDay(date, calendar: calendar)
        let t = TimeOfDay(date, calendar: calendar)
        if start > end, t.hour * 60 + t.minute >= start { day = day.adding(days: 1) }
        return (day.at(hour: end / 60, minute: end % 60, calendar: calendar), true)
    }
}

// MARK: - Reminder (reminder.go)

/// The one nudge of a task, for its recipient.
struct TaskReminder: Hashable, Codable, Sendable {
    /// When it fires (after quiet hours).
    var remindAt: Date
    /// What was asked for, when quiet hours moved it.
    var shiftedFrom: Date?
    var recipient: Person

    /// The time the person asked for.
    var requested: Date { shiftedFrom ?? remindAt }

    /// Plans a reminder for `requested`, shifted out of the recipient's quiet hours.
    static func plan(at requested: Date, for recipient: Person, quiet: QuietHours, calendar: Calendar) -> TaskReminder {
        let (at, shifted) = quiet.apply(requested, calendar: calendar)
        return TaskReminder(remindAt: at, shiftedFrom: shifted ? requested : nil, recipient: recipient)
    }

    /// Moves the reminder by `days` with its due date (a repeat rolled, Undo, an edit): same requested
    /// wall-clock time, quiet hours re-applied.
    func moved(byDays days: Int, quiet: QuietHours, calendar: Calendar) -> TaskReminder {
        let requested = calendar.date(byAdding: .day, value: days, to: requested)!
        return Self.plan(at: requested, for: recipient, quiet: quiet, calendar: calendar)
    }
}

/// One suggested reminder time in the task sheet ("Morning of · 9:00").
struct ReminderOption: Hashable, Sendable {
    /// Chip text.
    var label: String
    var at: Date
}

enum ReminderPlanner {
    /// The chips for a due date (design/prototype `remindOptions`), without times that have already passed:
    /// no date → Tomorrow 9:00 / This evening 19:00; today → This evening 19:00 / In 1 hour;
    /// tomorrow → Morning of 9:00 / Tonight 19:00; later → Morning of 9:00 / Day before 19:00.
    static func options(due: CalendarDay?, now: Date, calendar: Calendar) -> [ReminderOption] {
        let today = CalendarDay(now, calendar: calendar)
        let tomorrow = today.adding(days: 1)
        func at(_ day: CalendarDay, _ hour: Int) -> Date { day.at(hour: hour, calendar: calendar) }

        let all: [ReminderOption]
        switch due.map({ today.days(until: $0) }) {
        case 0?:
            let inAnHour = roundUp(now.addingTimeInterval(3600), toMinutes: 5, calendar: calendar)
            all = [
                ReminderOption(label: "This evening · 19:00", at: at(today, 19)),
                ReminderOption(label: "In 1 hour · " + TimeOfDay(inAnHour, calendar: calendar).text, at: inAnHour),
            ]
        case 1?:
            all = [
                ReminderOption(label: "Morning of · 9:00", at: at(tomorrow, 9)),
                ReminderOption(label: "Tonight · 19:00", at: at(today, 19)),
            ]
        case let n? where n > 1:
            let day = due!
            all = [
                ReminderOption(label: "Morning of · 9:00", at: at(day, 9)),
                ReminderOption(label: "Day before · 19:00", at: at(day.adding(days: -1), 19)),
            ]
        default: // no date, or overdue
            all = [
                ReminderOption(label: "Tomorrow · 9:00", at: at(tomorrow, 9)),
                ReminderOption(label: "This evening · 19:00", at: at(today, 19)),
            ]
        }
        return all.filter { $0.at > now }
    }

    /// "Pick time": that time on the due day (tomorrow without a date, or when the due day is already past).
    static func custom(_ time: TimeOfDay, due: CalendarDay?, now: Date, calendar: Calendar) -> Date {
        let today = CalendarDay(now, calendar: calendar)
        let day = due.flatMap { $0 >= today ? $0 : nil } ?? today.adding(days: 1)
        return day.at(hour: time.hour, minute: time.minute, calendar: calendar)
    }

    private static func roundUp(_ date: Date, toMinutes step: Int, calendar: Calendar) -> Date {
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let extra = (step - minute % step) % step
        let rounded = calendar.date(byAdding: .minute, value: extra, to: date)!
        return calendar.date(byAdding: .second, value: -second, to: rounded)!
    }
}

/// Notification copy (reminder.go): names the person and the task, never nags.
enum ReminderText {
    /// "today", "tomorrow", "Monday" within a week, otherwise "15 Nov".
    static func dueLabel(_ day: CalendarDay, today: CalendarDay) -> String {
        let n = today.days(until: day)
        switch n {
        case 0: return "today"
        case 1: return "tomorrow"
        case 2..<7: return symbols.weekdaySymbols[day.weekday - 1]
        default: return "\(day.day) " + symbols.shortMonthSymbols[day.month - 1]
        }
    }

    /// "Alex asked you to" when someone else set it, "Reminder" when you set it yourself.
    static func title(setBy: Person?, recipient: Person) -> String {
        guard let setBy, setBy != recipient else { return "Reminder" }
        return "\(setBy.name) asked you to"
    }

    private static let symbols: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_GB")
        return c
    }()
}
