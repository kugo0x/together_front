import Foundation

// Client data model (HANDOFF §4) plus the product decisions in ../CLAUDE.md:
// grocery items belong to a `GroceryList` (one default list per space in the MVP UI),
// tasks have an optional description (`notes`), one reminder per task.
//
// People are `Person` values for now; the real app swaps them for user IDs in phase 9.

extension SpaceKind: CaseIterable, Identifiable {
    static var allCases: [SpaceKind] { [.shared, .personal] }
    var id: String { rawValue }
}

/// A grocery list. The API supports many per space; the MVP UI only shows the default one.
struct GroceryList: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var space: SpaceKind
    var name: String = "Groceries"
    var isDefault: Bool = true
}

/// An item on a grocery list. Its space comes from the list — there is no separate `space` field to drift.
struct GroceryItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var listID: GroceryList.ID
    var name: String
    var qty: String?
    var note: String?
    /// Who put it on the list — the row says "Sam added" when it was the partner and there is no note.
    var addedBy: Person?
    var done: Bool = false
    var boughtBy: Person?
    var boughtAt: Date?
    var viaReceipt: Bool = false
}

enum RepeatRule: String, Codable, CaseIterable, Sendable {
    case weekly, monthly, everyTwoMonths

    var label: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .everyTwoMonths: "Every 2 months"
        }
    }
}

struct TaskItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var space: SpaceKind
    var title: String
    /// Optional description, shown in the task sheet.
    var notes: String?
    /// The day it's due (no time of day in the MVP UI; the API also allows one).
    var dueDay: CalendarDay?
    /// Needs a due date.
    var repeatRule: RepeatRule?
    /// Day of month a monthly repeat sticks to (the day it started on).
    var anchorDay: Int = 0
    /// Shared: a member or `nil` = Anyone. Personal: always the owner.
    var assignee: Person?
    /// One reminder per task, for the assignee only (never "Anyone").
    var reminder: TaskReminder?
    var createdBy: Person?
    var done: Bool = false
    var doneBy: Person?
    var doneAt: Date?
    /// Also set for repeating tasks, which never stay done.
    var lastDoneBy: Person?
    var lastDoneAt: Date?
    /// The due date before the last roll (Undo of a repeating completion).
    var previousDueDay: CalendarDay?

    /// Start of the due day in `calendar` — for date wording ("Today", "Sat").
    func dueDate(calendar: Calendar = .current) -> Date? { dueDay?.at(calendar: calendar) }
}

struct ChecklistItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var label: String
    var done: Bool = false
    var doneBy: Person?
    var doneAt: Date?
}

/// Plain-text body plus a checklist; no formatting in the MVP.
struct Note: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var space: SpaceKind
    var title: String
    var body: String
    var checklist: [ChecklistItem] = []
    var updatedAt: Date
    var updatedBy: Person
    var createdBy: Person? = nil
    /// Bumped by every title/body save; sent back as `If-Match`. Checklist changes don't bump it.
    var version: Int = 1

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && checklist.isEmpty
    }

    /// The row title: the title, or the body's first line when there is none.
    var displayTitle: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return bodyLines.first ?? (checklist.isEmpty ? "Untitled" : "Checklist")
    }

    /// The row preview: the body (lines joined), or the checklist as "Passport, Chargers".
    var preview: String? {
        let lines = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Array(bodyLines.dropFirst()) : bodyLines
        if !lines.isEmpty { return lines.joined(separator: " · ") }
        let items = checklist.map(\.label).filter { !$0.isEmpty }
        return items.isEmpty ? nil : items.joined(separator: ", ")
    }

    private var bodyLines: [String] {
        body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

struct ReceiptLine: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable { case matched, extra, unclear }

    var id: UUID = UUID()
    var name: String
    var qty: String?
    /// `nil` when the price couldn't be read.
    var price: Decimal?
    var status: Status
    var included: Bool = true
}

/// A shopping trip in History. Money appears only as trip totals and one month line.
struct Trip: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var space: SpaceKind
    var date: Date
    var shoppers: [Person]
    var itemCount: Int
    var total: Decimal?
    /// "Biedronka" — from the scanned receipt.
    var merchant: String? = nil
    var receiptImageID: String?
    var lines: [ReceiptLine] = []
}

/// Which notifications I get (back/api/openapi.yaml `Notifications`).
struct NotificationPrefs: Codable, Hashable, Sendable {
    /// My own task reminders (the local notifications).
    var taskReminders = true
    /// "Alex asked you to" when a partner assigns a task.
    var taskAssigned = true
    var partnerJoined = true
    /// Stored for the planned shopping-day reminder; nothing sends it yet.
    var groceryReminder = false
}
