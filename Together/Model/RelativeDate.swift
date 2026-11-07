import Foundation

/// Short, human date words for rows ("Today", "Sat", "Yesterday", "2 hours ago").
/// Deliberately simple for the shell; the Tasks and Notes phases may refine the wording.
struct RelativeDate: Sendable {
    var now: Date = .now
    var calendar: Calendar = .current
    /// The design writes dates day-first ("Saturday, 7 November", "15 Nov") and times as "9:00" / "19:00".
    var locale = Locale(identifier: "en_GB")

    private func dayOffset(_ date: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Due date: "Today", "Tomorrow", weekday within a week, otherwise "15 Nov". Past dates: "Overdue · 3 Nov".
    func due(_ date: Date) -> String {
        let offset = dayOffset(date)
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...7: return date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        case ..<0: return "Overdue · " + dayMonth(date)
        default: return dayMonth(date)
        }
    }

    /// Today or earlier — the due text gets the warning tone.
    func isUrgent(_ date: Date) -> Bool { dayOffset(date) <= 0 }

    /// Reminder time: "Today 19:00", "Mon 9:00".
    func reminder(_ date: Date) -> String {
        let day = dayOffset(date) == 0 ? "Today" : due(date)
        return day + " " + time(date)
    }

    /// Last edit / purchase: "Just now", "5 min ago", "2 hours ago", "Yesterday", "Wed", "30 Oct".
    /// `midSentence` lowercases the words that aren't names ("Sam bought this · yesterday").
    func past(_ date: Date, midSentence: Bool = false) -> String {
        let word = pastWord(date)
        guard midSentence, word == "Just now" || word == "Yesterday" else { return word }
        return word.prefix(1).lowercased() + word.dropFirst()
    }

    private func pastWord(_ date: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        let offset = dayOffset(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if offset == 0 {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        if offset == -1 { return "Yesterday" }
        if offset >= -6 { return date.formatted(.dateTime.weekday(.abbreviated).locale(locale)) }
        return dayMonth(date)
    }

    /// "Saturday, 7 November" — the Home subtitle.
    func longDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).locale(locale)) + ", "
            + date.formatted(.dateTime.day().month(.wide).locale(locale))
    }

    /// 24-hour time without a leading zero: "9:00", "19:00".
    func time(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }
}
